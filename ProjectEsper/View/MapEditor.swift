import EsperSim
import Foundation
import SpriteKit

/// A hand-laid stage's map, as last kept between launches by the map maker; nil until it's
/// used, and put aside (under its `beforeBake` key, not deleted) when a newer map has been
/// baked since.
enum SavedStageMap {
    private static func key(_ stage: MapStage) -> String { stage == .elements ? "esper.elementsMap" : "esper.\(stage.rawValue)Map" }
    private static func versionKey(_ stage: MapStage) -> String { key(stage) + ".bakedVersion" }
    private static func beforeBakeKey(_ stage: MapStage) -> String { key(stage) + ".beforeBake" }

    /// A map kept against an older baked one is moved aside, once.
    private static func putAsideIfStale(_ stage: MapStage) {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: versionKey(stage)) != StageMap.bakedVersion(stage) else { return }
        if let data = defaults.data(forKey: key(stage)) { defaults.set(data, forKey: beforeBakeKey(stage)) }
        defaults.removeObject(forKey: key(stage))
        defaults.set(StageMap.bakedVersion(stage), forKey: versionKey(stage))
    }

    static func value(_ stage: MapStage) -> StageMap? {
        putAsideIfStale(stage)
        let map = UserDefaults.standard.data(forKey: key(stage)).flatMap { try? JSONDecoder().decode(StageMap.self, from: $0) }
        return stage == .flight ? movedToFlightStride(map) : map
    }

    /// A Flight map kept when each sheet had 16 columns, its art cells moved to `MapTiles.flightStride`, once.
    private static let flightStrideKey = "esper.flightMap.artStride"
    private static func movedToFlightStride(_ kept: StageMap?) -> StageMap? {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: flightStrideKey) != MapTiles.flightStride else { return kept }
        defaults.set(MapTiles.flightStride, forKey: flightStrideKey)
        guard var map = kept else { return nil }
        map.tiles = map.tiles.map { tile in
            var moved = tile
            moved.art.column = tile.art.column / 16 * MapTiles.flightStride + tile.art.column % 16
            return moved
        }
        store(map, for: .flight)
        return map
    }

    static func store(_ map: StageMap?, for stage: MapStage) {
        putAsideIfStale(stage)
        if let map, let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key(stage))
        } else {
            UserDefaults.standard.removeObject(forKey: key(stage))
        }
    }
}

#if !os(tvOS)
import UIKit

/// The map maker, for a mouse, for the Elements and Wetshot Wake: the stage under a grid, and
/// a panel to pick from: the Elements' tileset, or Wetshot Wake's plants, rocks and Hoopfish.
/// Drag a tile or a prop from the panel onto the stage to drop it; press one on the stage to
/// pick it up and move it, dropping it back on the panel to take it away; press an empty cell
/// with a tile or a prop chosen to place it (tiles paint as the pointer drags). The markers
/// (the Elements' two rims, the two starts and the ball) are chosen and dropped the same way;
/// Wetshot Wake's one rim rides the Hoopfish, and there's only ever one. UNDO steps back,
/// COPY puts the map on the clipboard as Swift for the stage's baked map. The map is kept
/// between launches and stands in for the baked one offline.
final class MapEditor: SKNode {
    private enum Tool: Equatable {
        case brush(StageMap.Cell)
        /// A block of the sheet, its top left and bottom right art cells, put down whole.
        case stamp(StageMap.Cell, StageMap.Cell)
        case erase
        case marker(Marker)
        /// A whole tornado, placed by the cell its base's middle is in.
        case tornado
        /// In walls mode: a wall kind, or nil to open a cell.
        case wall(StageMap.Kind?)
        /// Wetshot Wake's: a prop to place whole.
        case prop(StageMap.PropKind)
        /// A piece of the background pile, put down anywhere.
        case pile(StageMap.PilePiece.Kind)
    }

    private enum Marker: Equatable, CaseIterable {
        case leftRim, rightRim, firstStart, secondStart, ball

        /// The markers a stage has: Wetshot Wake's one rim rides the Hoopfish, so no rims.
        static func on(_ stage: MapStage) -> [Marker] { stage == .wetshot ? [.firstStart, .secondStart, .ball] : allCases }

        var label: String {
            switch self {
            case .leftRim: "RIM ◀"
            case .rightRim: "RIM ▶"
            case .firstStart: "P1"
            case .secondStart: "P2"
            case .ball: "BALL"
            }
        }
        var colour: SKColor {
            switch self {
            case .leftRim, .rightRim: SKColor(red: 1, green: 0.5, blue: 0.1, alpha: 1)
            case .firstStart: SKColor(red: 0.2, green: 0.9, blue: 1, alpha: 1)
            case .secondStart: SKColor(red: 1, green: 0.3, blue: 0.9, alpha: 1)
            case .ball: SKColor(red: 1, green: 1, blue: 0.3, alpha: 1)
            }
        }
    }

    /// What's on the pointer between pressing and letting go.
    private enum Carried {
        case tile(art: StageMap.Cell, taken: Bool)
        case marker(Marker, from: StageMap.Cell)
        case tornado(from: StageMap.Cell)
        case prop(StageMap.PropKind, taken: Bool)
        case pile(StageMap.PilePiece.Kind, rotation: Double, taken: Bool)
    }

    /// Which hand-laid stage this is the map of, its tiles, and which of their sheets the panel shows.
    private let stage: MapStage
    private let tiles: MapTiles
    /// The sheet the panel shows, kept between openings and launches.
    private var sheetIndex: Int {
        didSet { UserDefaults.standard.set(sheetIndex, forKey: MapEditor.sheetKey(stage)) }
    }
    private static func sheetKey(_ stage: MapStage) -> String { "esper.\(stage.rawValue)Map.sheet" }
    private(set) var map: StageMap
    private var history: [StageMap] = []
    private var tool: Tool
    private var carried: Carried?
    private var painting = false
    private var lastCell: StageMap.Cell?
    /// MULTI: a drag on the sheet picks a block of it, put down whole. OVER: tiles go on the
    /// layer over the ground, drawn on top of what's there, and bring no wall.
    private var multiSelect = false
    private var overlaying = false
    private var layer: Int { overlaying ? 1 : 0 }
    /// Where a drag across the sheet started, while picking a block.
    private var blockStart: StageMap.Cell?
    /// Where a stroke of stamps started, so it lays them side by side.
    private var stampOrigin: StageMap.Cell?
    /// Cells whose tile changed since the game was last told, and whether the tornados did.
    private var dirty: Set<StageMap.Cell> = []
    private var tornadosDirty = false
    private var propsDirty = false
    private var wallsDirty = false
    /// Walls mode: the walls shown as transparent red over the stage, and painted instead of tiles.
    private var wallsMode = false
    /// While a stroke paints walls: the kind it lays, nil opening cells.
    private var strokeKind: StageMap.Kind?
    private let wallLayer = SKNode()

    private let halfWidth: CGFloat, halfHeight: CGFloat
    /// Stage units for a HUD point and back: the camera's place and how many units a point covers.
    private let world: (CGPoint) -> CGPoint
    private let hudFromWorld: (CGPoint) -> CGPoint
    private let unitsPerHud: CGFloat
    private let onTiles: ([StageMap.Cell]) -> Void
    private let onMarkers: () -> Void
    private let onTornados: () -> Void
    private let onProps: () -> Void
    private let onWalls: () -> Void
    private let onClose: () -> Void

    private let grid = SKShapeNode()
    private let markerLayer = SKNode()
    private let panel = SKNode()
    private let selection = SKShapeNode()
    private let hover = SKShapeNode()
    private var ghost: SKSpriteNode?
    private var ghostMarker: SKNode?
    private var buttons: [(rect: CGRect, action: () -> Void)] = []
    private var paletteRect = CGRect.zero
    /// Wetshot Wake's props laid out in the panel in place of a tileset, each where it's drawn.
    private var propButtons: [(rect: CGRect, kind: StageMap.PropKind)] = []
    private var pileButtons: [(rect: CGRect, kind: StageMap.PilePiece.Kind)] = []
    /// The two turn sliders, for the newest pile piece and the one before it, and the one being dragged.
    private var turnSliders: [(track: CGRect, piece: Int)] = []
    private var turning: Int?
    /// A slider's travel either way, in degrees.
    private static let turnRange = 180.0
    private var panelRect = CGRect.zero
    private var paletteShown = true
    /// Screen points to a tileset pixel: small, in the corner, or less if the sheet is big for the screen.
    private var paletteScale: CGFloat {
        let sheet = tiles.sheets[sheetIndex].size()
        // Flight's big sheets get more of the screen's height, or their cells are too small to pick.
        let heightShare: CGFloat = tiles.sheets.count > 1 ? 0.8 : 0.5
        return min(0.85, halfWidth * 0.6 / max(sheet.width, 1), halfHeight * heightShare / max(sheet.height, 1))
    }

    init(stage: MapStage, map: StageMap, halfWidth: CGFloat, halfHeight: CGFloat, unitsPerHud: CGFloat, world: @escaping (CGPoint) -> CGPoint,
         hudFromWorld: @escaping (CGPoint) -> CGPoint, onTiles: @escaping ([StageMap.Cell]) -> Void,
         onMarkers: @escaping () -> Void, onTornados: @escaping () -> Void, onProps: @escaping () -> Void, onWalls: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        self.stage = stage
        tiles = MapTiles.of(stage)
        sheetIndex = min(max(UserDefaults.standard.integer(forKey: MapEditor.sheetKey(stage)), 0), tiles.sheets.count - 1)
        self.map = map
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        self.unitsPerHud = unitsPerHud
        self.world = world
        self.hudFromWorld = hudFromWorld
        self.onTiles = onTiles
        self.onMarkers = onMarkers
        self.onTornados = onTornados
        self.onProps = onProps
        self.onWalls = onWalls
        self.onClose = onClose
        tool = MapEditor.firstTool(for: stage)
        super.init()
        zPosition = 500
        addChild(grid)
        addChild(wallLayer)
        addChild(markerLayer)
        addChild(panel)
        hover.strokeColor = .white
        hover.lineWidth = 1
        hover.zPosition = 5
        hover.isHidden = true
        addChild(hover)
        buildGrid()
        buildPanel()
        showMarkers()
        showWalls()
        wallLayer.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    /// What's in hand to start with, and back from walls mode: a tile, or Wetshot Wake's first plant.
    private static func firstTool(for stage: MapStage) -> Tool {
        switch stage {
        case .wetshot: .prop(.plant1)
        case .elements: .brush(ElementsArt.filled.first { $0 == StageMap.Cell(3, 3) } ?? ElementsArt.filled[0])
        case .flight: .brush(MapTiles.flight.filled(sheet: 0).first ?? StageMap.Cell(0, 0))
        }
    }

    // MARK: Geometry

    private var cellSide: CGFloat { ElementsArt.tileSide / unitsPerHud }

    private func cell(at hudPoint: CGPoint) -> StageMap.Cell? {
        let point = world(hudPoint)
        let column = Int((point.x / ElementsArt.tileSide).rounded(.down)), row = Int((point.y / ElementsArt.tileSide).rounded(.down))
        guard (0..<stage.columns).contains(column), (0..<stage.rows).contains(row) else { return nil }
        return StageMap.Cell(column, row)
    }

    private func hudRect(of cell: StageMap.Cell) -> CGRect {
        let origin = hudFromWorld(CGPoint(x: CGFloat(cell.column) * ElementsArt.tileSide, y: CGFloat(cell.row) * ElementsArt.tileSide))
        return CGRect(x: origin.x, y: origin.y, width: cellSide, height: cellSide)
    }

    private func buildGrid() {
        let path = CGMutablePath()
        for column in 0...stage.columns {
            let x = hudFromWorld(CGPoint(x: CGFloat(column) * ElementsArt.tileSide, y: 0)).x
            path.move(to: CGPoint(x: x, y: hudFromWorld(.zero).y))
            path.addLine(to: CGPoint(x: x, y: hudFromWorld(CGPoint(x: 0, y: CGFloat(stage.rows) * ElementsArt.tileSide)).y))
        }
        for row in 0...stage.rows {
            let y = hudFromWorld(CGPoint(x: 0, y: CGFloat(row) * ElementsArt.tileSide)).y
            path.move(to: CGPoint(x: hudFromWorld(.zero).x, y: y))
            path.addLine(to: CGPoint(x: hudFromWorld(CGPoint(x: CGFloat(stage.columns) * ElementsArt.tileSide, y: 0)).x, y: y))
        }
        grid.path = path
        grid.strokeColor = SKColor(white: 1, alpha: 0.13)
        grid.lineWidth = 0.5
        grid.isAntialiased = false
    }

    // MARK: The panel

    /// The panel, small, in the upper right corner: a row of actions, a row of tools (the wall kinds in
    /// walls mode), and under them the tileset to pick tiles from.
    private func buildPanel() {
        panel.removeAllChildren()
        buttons = []
        let scale = paletteScale
        let sheetSize = tiles.sheets[sheetIndex].size()
        let showsSheet = paletteShown && !wallsMode && stage != .wetshot
        let showsProps = paletteShown && !wallsMode && stage == .wetshot
        // The props in a row, each scaled to the row's height but no wider than it allows.
        let propHeight: CGFloat = 28
        let propSizes = StageMap.PropKind.allCases.map { kind -> CGSize in
            let pixels = kind.pixelSize
            let fit = min(propHeight / CGFloat(pixels.height), 48 / CGFloat(pixels.width))
            return CGSize(width: CGFloat(pixels.width) * fit, height: CGFloat(pixels.height) * fit)
        }
        let pileSide = propHeight
        let pileWidth = (pileSide + 3) * CGFloat(StageMap.PilePiece.Kind.allCases.count)
        let propsWidth = propSizes.reduce(CGFloat(0)) { $0 + $1.width } + 3 * CGFloat(propSizes.count - 1) + 6 + pileWidth
        let paletteSize = showsSheet ? CGSize(width: sheetSize.width * scale, height: sheetSize.height * scale)
            : (showsProps ? CGSize(width: propsWidth, height: propHeight) : .zero)
        let margin: CGFloat = 5, rowHeight: CGFloat = 15, gap: CGFloat = 3, fontSize: CGFloat = 7
        let actionRow: [(String, () -> Void)] = [
            ("UNDO", { [weak self] in self?.undo() }), ("RESET", { [weak self] in self?.reset() }), ("COPY", { [weak self] in self?.copy() }),
            (wallsMode ? "TILES" : "WALLS", { [weak self] in self?.toggleWallsMode() }),
        ] + (wallsMode ? [] : [(paletteShown ? "HIDE" : "PALETTE", { [weak self] in self?.togglePalette() })])
            + [("CLOSE", { [weak self] in self?.onClose() })]
        // The tools, each with the tool it picks, so the one in hand can be lit.
        let tools: [(String, Tool)]
        if wallsMode {
            let kinds: [(String, StageMap.Kind?)] = [("SOLID", .solid), ("\u{25E2}", .lowerRight), ("\u{25E3}", .lowerLeft),
                                                       ("\u{25E5}", .upperRight), ("\u{25E4}", .upperLeft),
                                                       ("SLIDE \u{25E2}", .slideLowerRight), ("SLIDE \u{25E3}", .slideLowerLeft),
                                                       ("ONE-WAY", .oneWay), ("OPEN", nil)]
            tools = kinds.map { ($0.0, .wall($0.1)) }
        } else {
            tools = (stage == .elements ? [("ERASE", .erase), ("TORNADO", .tornado)] : [("ERASE", .erase)])
                + Marker.on(stage).map { ($0.label, .marker($0)) }
        }
        let toolRow: [(String, () -> Void)] = tools.map { title, picked in (title, { [weak self] in self?.tool = picked; self?.buildPanel() }) }
        // With a sheet: MULTI and OVER, and with more than one sheet, paging through them.
        let sheetRow: [(String, () -> Void)] = !showsSheet ? [] : [
            ("MULTI \(multiSelect ? "ON" : "OFF")", { [weak self] in self?.multiSelect.toggle(); self?.buildPanel() }),
            ("OVER \(overlaying ? "ON" : "OFF")", { [weak self] in self?.overlaying.toggle(); self?.buildPanel() }),
        ] + (tiles.sheets.count > 1 ? [
            ("\u{25C0}", { [weak self] in self?.turnSheet(-1) }), ("SHEET \(sheetIndex + 1)/\(tiles.sheets.count)", {}),
            ("\u{25B6}", { [weak self] in self?.turnSheet(1) }),
        ] : [])
        let lit = Set(tools.filter { $0.1 == tool }.map(\.0))
        func labelWidth(_ title: String) -> CGFloat {
            let label = SKLabelNode(text: title)
            label.fontName = "Menlo-Bold"
            label.fontSize = fontSize
            return label.frame.width + 8
        }
        let rows = [actionRow, toolRow] + (sheetRow.isEmpty ? [] : [sheetRow])
        let rowWidths = rows.map { row in row.reduce(CGFloat(0)) { $0 + labelWidth($1.0) } + gap * CGFloat(max(row.count - 1, 0)) }
        let contentWidth = max(rowWidths.max() ?? 0, paletteSize.width)
        // Under the props, a slider each for the newest two pile pieces' turns.
        let sliderRows = showsProps ? 2 : 0
        let contentHeight = rowHeight * CGFloat(rows.count + sliderRows) + (showsSheet || showsProps ? paletteSize.height + margin : 0)
        let right = halfWidth - margin, top = halfHeight - margin
        let left = right - contentWidth
        panelRect = CGRect(x: left - 4, y: top - contentHeight - 4, width: contentWidth + 8, height: contentHeight + 8)
        let back = SKSpriteNode(color: SKColor(white: 0.05, alpha: 0.88), size: panelRect.size)
        back.anchorPoint = .zero
        back.position = panelRect.origin
        panel.addChild(back)
        selection.removeFromParent()
        for (index, items) in rows.enumerated() {
            var x = left
            let y = top - rowHeight * CGFloat(index + 1)
            for (title, action) in items {
                let width = labelWidth(title)
                let rect = CGRect(x: x, y: y + 1, width: width, height: rowHeight - 3)
                let box = SKShapeNode(rect: rect, cornerRadius: 2)
                box.fillColor = index == 1 && lit.contains(title) ? SKColor(red: 0.75, green: 0.55, blue: 0.1, alpha: 1) : SKColor(white: 0.25, alpha: 1)
                box.strokeColor = SKColor(white: 1, alpha: 0.3)
                box.lineWidth = 0.5
                box.zPosition = 1
                let label = SKLabelNode(text: title)
                label.fontName = "Menlo-Bold"
                label.fontSize = fontSize
                label.fontColor = .white
                label.verticalAlignmentMode = .center
                label.horizontalAlignmentMode = .center
                label.position = CGPoint(x: rect.midX, y: rect.midY)
                label.zPosition = 2
                panel.addChild(box)
                panel.addChild(label)
                buttons.append((rect, action))
                x += width + gap
            }
        }
        if showsSheet {
            paletteRect = CGRect(x: left, y: top - contentHeight, width: paletteSize.width, height: paletteSize.height)
            let sheet = SKSpriteNode(texture: tiles.sheets[sheetIndex])
            sheet.anchorPoint = .zero
            sheet.size = paletteSize
            sheet.position = paletteRect.origin
            sheet.zPosition = 1
            panel.addChild(sheet)
            selection.zPosition = 2
            selection.strokeColor = SKColor(red: 1, green: 0.9, blue: 0.2, alpha: 1)
            selection.lineWidth = 1
            selection.fillColor = .clear
            panel.addChild(selection)
        } else {
            paletteRect = .zero
        }
        propButtons = []
        if showsProps {
            var x = left
            let bottom = top - contentHeight
            for (kind, size) in zip(StageMap.PropKind.allCases, propSizes) {
                let rect = CGRect(x: x, y: bottom, width: size.width, height: size.height)
                let sprite = SKSpriteNode(texture: WetshotArt.texture(kind))
                sprite.anchorPoint = .zero
                sprite.size = size
                sprite.position = rect.origin
                sprite.zPosition = 1
                panel.addChild(sprite)
                if case .prop(let held) = tool, held == kind {
                    let ring = SKShapeNode(rect: rect.insetBy(dx: -1, dy: -1))
                    ring.strokeColor = SKColor(red: 1, green: 0.9, blue: 0.2, alpha: 1)
                    ring.lineWidth = 1
                    ring.zPosition = 2
                    panel.addChild(ring)
                }
                propButtons.append((rect, kind))
                x += size.width + 3
            }
            // The pile's pieces after them.
            x += 6
            pileButtons = []
            for kind in StageMap.PilePiece.Kind.allCases {
                let rect = CGRect(x: x, y: bottom, width: pileSide, height: pileSide)
                let sprite = SKSpriteNode(texture: WetshotArt.pileTexture(kind))
                sprite.anchorPoint = .zero
                sprite.size = rect.size
                sprite.position = rect.origin
                sprite.zPosition = 1
                panel.addChild(sprite)
                if case .pile(let held) = tool, held == kind {
                    let ring = SKShapeNode(rect: rect.insetBy(dx: -1, dy: -1))
                    ring.strokeColor = SKColor(red: 1, green: 0.9, blue: 0.2, alpha: 1)
                    ring.lineWidth = 1
                    ring.zPosition = 2
                    panel.addChild(ring)
                }
                pileButtons.append((rect, kind))
                x += pileSide + 3
            }
            // The turn sliders, newest piece first.
            turnSliders = []
            for row in 0..<2 {
                let index = map.pile.count - 1 - row
                let y = top - rowHeight * CGFloat(rows.count + row + 1)
                let label = SKLabelNode(text: index >= 0 ? "TURN \(row == 0 ? "LAST" : "2ND") \(Int(map.pile[index].rotation.rounded()))\u{00B0}" : "TURN —")
                label.fontName = "Menlo-Bold"
                label.fontSize = fontSize
                label.fontColor = .white
                label.horizontalAlignmentMode = .left
                label.verticalAlignmentMode = .center
                label.position = CGPoint(x: left, y: y + rowHeight / 2)
                label.zPosition = 2
                panel.addChild(label)
                let track = CGRect(x: left + 78, y: y + 2, width: contentWidth - 78, height: rowHeight - 4)
                let bar = SKShapeNode(rect: CGRect(x: track.minX, y: track.midY - 1, width: track.width, height: 2))
                bar.fillColor = SKColor(white: 0.5, alpha: 1)
                bar.strokeColor = .clear
                bar.zPosition = 1
                panel.addChild(bar)
                guard index >= 0 else { continue }
                let share = (map.pile[index].rotation + MapEditor.turnRange) / (MapEditor.turnRange * 2)
                let knob = SKShapeNode(circleOfRadius: 4)
                knob.fillColor = SKColor(red: 1, green: 0.9, blue: 0.2, alpha: 1)
                knob.strokeColor = .clear
                knob.position = CGPoint(x: track.minX + track.width * CGFloat(share), y: track.midY)
                knob.zPosition = 2
                panel.addChild(knob)
                turnSliders.append((track, index))
            }
        } else {
            pileButtons = []
            turnSliders = []
        }
        showSelection()
    }

    /// The panel on to the next sheet, or back.
    private func turnSheet(_ by: Int) {
        sheetIndex = (sheetIndex + by + tiles.sheets.count) % tiles.sheets.count
        buildPanel()
    }

    private func togglePalette() {
        paletteShown.toggle()
        buildPanel()
    }

    /// Into walls mode, the tool a wall kind (or back to a tile brush), the overlay shown or hidden.
    private func toggleWallsMode() {
        wallsMode.toggle()
        if wallsMode {
            tool = .wall(.solid)
        } else if case .wall = tool {
            tool = MapEditor.firstTool(for: stage)
        }
        wallLayer.isHidden = !wallsMode
        buildPanel()
    }

    /// The chosen tile ringed in the panel.
    private func showSelection() {
        let block: (StageMap.Cell, StageMap.Cell)
        switch tool {
        case .brush(let art): block = (art, art)
        case .stamp(let first, let last): block = (first, last)
        default: selection.isHidden = true; return
        }
        guard paletteShown, tiles.sheet(of: block.0) == sheetIndex else { selection.isHidden = true; return }
        selection.isHidden = false
        let side = tiles.cellPixels(of: sheetIndex) * paletteScale
        let column = block.0.column - sheetIndex * tiles.stride
        let across = CGFloat(block.1.column - block.0.column + 1), down = CGFloat(block.1.row - block.0.row + 1)
        selection.path = CGPath(rect: CGRect(x: paletteRect.minX + CGFloat(column) * side,
                                             y: paletteRect.maxY - (CGFloat(block.0.row) + down) * side, width: side * across, height: side * down), transform: nil)
    }

    /// The sheet's cell under a point, drawn in or not, held to the sheet: for a block's corner.
    private func sheetCell(at point: CGPoint) -> StageMap.Cell {
        let side = tiles.cellPixels(of: sheetIndex) * paletteScale
        let column = min(max(Int((point.x - paletteRect.minX) / side), 0), tiles.columns(of: sheetIndex) - 1)
        let row = min(max(Int((paletteRect.maxY - point.y) / side), 0), tiles.rows(of: sheetIndex) - 1)
        return StageMap.Cell(sheetIndex * tiles.stride + column, row)
    }

    /// A block's two corners as its top left and bottom right.
    private static func block(_ a: StageMap.Cell, _ b: StageMap.Cell) -> Tool {
        .stamp(StageMap.Cell(min(a.column, b.column), min(a.row, b.row)), StageMap.Cell(max(a.column, b.column), max(a.row, b.row)))
    }

    private func paletteCell(at point: CGPoint) -> StageMap.Cell? {
        guard paletteShown, !wallsMode, stage != .wetshot, paletteRect.contains(point) else { return nil }
        let side = tiles.cellPixels(of: sheetIndex) * paletteScale
        let cell = StageMap.Cell(sheetIndex * tiles.stride + Int((point.x - paletteRect.minX) / side), Int((paletteRect.maxY - point.y) / side))
        return tiles.filled(sheet: sheetIndex).contains(cell) ? cell : nil
    }

    // MARK: The map

    /// The tile on the layer being worked, at a cell.
    private func tile(at cell: StageMap.Cell) -> StageMap.Placed? { map.tiles.first { $0.cell == cell && $0.layer == layer } }

    private func markerCell(_ marker: Marker) -> StageMap.Cell {
        switch marker {
        case .leftRim: map.leftRim
        case .rightRim: map.rightRim
        case .firstStart: map.spawns[0]
        case .secondStart: map.spawns[1]
        case .ball: map.ball
        }
    }

    /// The tornado whose sprite has this cell in it, if any.
    private func tornado(at cell: StageMap.Cell) -> Int? {
        map.tornados.firstIndex { base in
            let span = StageMap.tornadoCells(base)
            return span.columns.contains(cell.column) && span.rows.contains(cell.row)
        }
    }

    private func marker(at cell: StageMap.Cell) -> Marker? { Marker.on(stage).first { markerCell($0) == cell } }

    /// The last placed prop whose picture covers this cell, if any.
    private func prop(at cell: StageMap.Cell) -> Int? {
        map.props.lastIndex { prop in
            let size = prop.kind.pixelSize
            let columns = Int((CGFloat(size.width) / ElementsArt.tileSide).rounded(.up)), rows = Int((CGFloat(size.height) / ElementsArt.tileSide).rounded(.up))
            return (prop.cell.column..<(prop.cell.column + columns)).contains(cell.column) && (prop.cell.row..<(prop.cell.row + rows)).contains(cell.row)
        }
    }

    /// The newest pile piece under a point in the stage, within its picture's middle.
    private func pilePiece(at worldPoint: CGPoint) -> Int? {
        map.pile.lastIndex { abs(CGFloat($0.x) - worldPoint.x) <= 16 && abs(CGFloat($0.y) - worldPoint.y) <= 16 }
    }

    /// A pile piece put down by its middle on the nearest whole art pixel.
    private func placePile(_ kind: StageMap.PilePiece.Kind, rotation: Double, at hudPoint: CGPoint) {
        let point = world(hudPoint)
        map.pile.append(.init(kind, x: Double(point.x.rounded()), y: Double(point.y.rounded()), rotation: rotation))
        propsDirty = true
    }

    /// A turn slider dragged: its piece turned to the whole degree under the finger.
    private func turn(_ slider: (track: CGRect, piece: Int), to point: CGPoint) {
        guard map.pile.indices.contains(slider.piece) else { return }
        let share = min(max((point.x - slider.track.minX) / slider.track.width, 0), 1)
        map.pile[slider.piece].rotation = (Double(share) * MapEditor.turnRange * 2 - MapEditor.turnRange).rounded()
        propsDirty = true
        commit()
        buildPanel()
    }

    /// A prop put down with its bottom left on the cell; there's only ever one Hoopfish.
    private func place(_ kind: StageMap.PropKind, at cell: StageMap.Cell) {
        if kind == .hoopfish { map.props.removeAll { $0.kind == .hoopfish } }
        map.props.append(.init(kind, at: cell))
        propsDirty = true
    }

    private func move(_ marker: Marker, to cell: StageMap.Cell) {
        switch marker {
        case .leftRim: map.leftRim = cell
        case .rightRim: map.rightRim = cell
        case .firstStart: map.spawns[0] = cell
        case .secondStart: map.spawns[1] = cell
        case .ball: map.ball = cell
        }
    }

    private func place(_ art: StageMap.Cell, at cell: StageMap.Cell) {
        let layer = layer
        map.tiles.removeAll { $0.cell == cell && $0.layer == layer }
        map.tiles.append(.init(cell, art: art, layer: layer))
        dirty.insert(cell)
        // A ground tile brings a block with it where there's no wall yet, the Elements' decoration excepted.
        if layer == 0, !(stage == .elements && StageMap.decoration.contains(art)), map.wall(at: cell) == nil { setWall(.solid, at: cell) }
    }

    /// The block in hand put down with its top left at `cell`, its empty cells leaving what's under them.
    private func stamp(at cell: StageMap.Cell) {
        guard case .stamp(let first, let last) = tool else { return }
        let drawn = Set(tiles.filled(sheet: tiles.sheet(of: first)))
        for down in 0...(last.row - first.row) {
            for across in 0...(last.column - first.column) {
                let art = StageMap.Cell(first.column + across, first.row + down)
                let target = StageMap.Cell(cell.column + across, cell.row - down)
                guard drawn.contains(art), (0..<stage.columns).contains(target.column), (0..<stage.rows).contains(target.row) else { continue }
                place(art, at: target)
            }
        }
    }

    /// A tile taken off its cell takes a block with it; a slope painted there stays.
    private func takeAwayTile(at cell: StageMap.Cell) {
        let layer = layer
        map.tiles.removeAll { $0.cell == cell && $0.layer == layer }
        dirty.insert(cell)
        if layer == 0, map.wall(at: cell) == .solid { setWall(nil, at: cell) }
    }

    private func erase(at cell: StageMap.Cell) {
        guard tile(at: cell) != nil else { return }
        takeAwayTile(at: cell)
    }

    private func remember() {
        history.append(map)
        if history.count > 200 { history.removeFirst() }
    }

    // MARK: The walls

    private func setWall(_ kind: StageMap.Kind?, at cell: StageMap.Cell) {
        guard map.wall(at: cell) != kind else { return }
        map.walls.removeAll { $0.cell == cell }
        if let kind { map.walls.append(.init(cell, kind)) }
        wallsDirty = true
    }

    /// Every wall as a transparent red square, or a triangle for a slope where its solid half lies.
    private func showWalls() {
        wallLayer.removeAllChildren()
        for wall in map.walls {
            let rect = hudRect(of: wall.cell)
            let side = rect.width
            let path = CGMutablePath()
            switch wall.kind {
            case .solid: path.addRect(CGRect(x: 0, y: 0, width: side, height: side))
            case .lowerRight, .slideLowerRight: path.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: side, y: 0), CGPoint(x: side, y: side)])
            case .lowerLeft, .slideLowerLeft: path.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: side, y: 0), CGPoint(x: 0, y: side)])
            case .upperRight: path.addLines(between: [CGPoint(x: 0, y: side), CGPoint(x: side, y: side), CGPoint(x: side, y: 0)])
            case .upperLeft: path.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: side), CGPoint(x: side, y: side)])
            // A one-way as a bar along the cell's top, what's stood on.
            case .oneWay: path.addRect(CGRect(x: 0, y: side * 0.75, width: side, height: side * 0.25))
            }
            path.closeSubpath()
            let node = SKShapeNode(path: path)
            node.position = rect.origin
            // Slide slopes in orange, apart from the red of the rest.
            let slides = wall.kind == .slideLowerRight || wall.kind == .slideLowerLeft
            node.fillColor = slides ? SKColor(red: 1, green: 0.6, blue: 0.1, alpha: 0.45) : SKColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.38)
            node.strokeColor = slides ? SKColor(red: 1, green: 0.7, blue: 0.2, alpha: 0.9) : SKColor(red: 1, green: 0.2, blue: 0.2, alpha: 0.85)
            node.lineWidth = 0.75
            wallLayer.addChild(node)
        }
    }

    /// The map kept and given to the game, which is told which tiles changed.
    private func commit() {
        SavedStageMap.store(map, for: stage)
        StageMap.current[stage] = map
        if !dirty.isEmpty {
            let changed = Array(dirty)
            dirty = []
            onTiles(changed)
        }
        if tornadosDirty {
            tornadosDirty = false
            onTornados()
        }
        if propsDirty {
            propsDirty = false
            onProps()
        }
        if wallsDirty {
            wallsDirty = false
            showWalls()
            onWalls()
        }
        showMarkers()
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        applyWholeMap(previous)
    }

    private func reset() {
        remember()
        applyWholeMap(StageMap.baked(stage))
    }

    private func applyWholeMap(_ next: StageMap) {
        let changed = Set(map.tiles.map(\.cell)).symmetricDifference(Set(next.tiles.map(\.cell)))
            .union(Set(map.tiles).symmetricDifference(Set(next.tiles)).map(\.cell))
        tornadosDirty = tornadosDirty || next.tornados != map.tornados
        propsDirty = propsDirty || next.props != map.props || next.pile != map.pile
        wallsDirty = wallsDirty || next.walls != map.walls
        map = next
        dirty.formUnion(changed)
        commit()
        onMarkers()
        buildPanel()
    }

    private func copy() {
        // For now, on Hoopfish Hideaway, the pile: each piece's place and turn.
        UIPasteboard.general.string = stage == .wetshot ? map.pileSource : map.swiftSource(stage)
    }

    /// Where each marker sits, as a coloured square with its letters.
    private func showMarkers() {
        markerLayer.removeAllChildren()
        for marker in Marker.on(stage) {
            guard !(isCarrying(marker)) else { continue }
            markerLayer.addChild(markerNode(marker, at: markerCell(marker)))
        }
    }

    private func isCarrying(_ marker: Marker) -> Bool {
        if case .marker(let carriedMarker, _) = carried { return carriedMarker == marker }
        return false
    }

    private func markerNode(_ marker: Marker, at cell: StageMap.Cell) -> SKNode {
        let rect = hudRect(of: cell)
        let node = SKShapeNode(rect: CGRect(origin: .zero, size: rect.size))
        node.position = rect.origin
        node.fillColor = marker.colour.withAlphaComponent(0.55)
        node.strokeColor = marker.colour
        node.lineWidth = 1.5
        let label = SKLabelNode(text: marker.label)
        label.fontName = "Menlo-Bold"
        label.fontSize = max(5, cellSide * 0.42)
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: rect.width / 2, y: rect.height / 2)
        node.addChild(label)
        return node
    }

    // MARK: The pointer

    private func over(_ point: CGPoint) -> Bool { panelRect.contains(point) }

    func began(at point: CGPoint) {
        for button in buttons where button.rect.contains(point) {
            button.action()
            return
        }
        if let slider = turnSliders.first(where: { $0.track.insetBy(dx: -4, dy: -3).contains(point) }) {
            remember()
            turning = turnSliders.firstIndex { $0.track == slider.track }
            turn(slider, to: point)
            return
        }
        if let button = pileButtons.first(where: { $0.rect.contains(point) }) {
            tool = .pile(button.kind)
            buildPanel()
            carried = .pile(button.kind, rotation: 0, taken: false)
            showGhost(at: point)
            return
        }
        if let button = propButtons.first(where: { $0.rect.contains(point) }) {
            tool = .prop(button.kind)
            buildPanel()
            carried = .prop(button.kind, taken: false)
            showGhost(at: point)
            return
        }
        if multiSelect, paletteShown, !wallsMode, stage != .wetshot, paletteRect.contains(point) {
            // MULTI: a block of the sheet, from here to where the drag lets go.
            let corner = sheetCell(at: point)
            blockStart = corner
            tool = MapEditor.block(corner, corner)
            showSelection()
            return
        }
        if let art = paletteCell(at: point) {
            tool = .brush(art)
            showSelection()
            carried = .tile(art: art, taken: false)
            showGhost(at: point)
            return
        }
        guard !over(point), let cell = cell(at: point) else { return }
        lastCell = cell
        if stage == .wetshot, !wallsMode, case .pile = tool, let index = pilePiece(at: world(point)) {
            // Picked up whole, to be moved, keeping its turn.
            remember()
            let picked = map.pile.remove(at: index)
            propsDirty = true
            commit()
            carried = .pile(picked.kind, rotation: picked.rotation, taken: true)
            showGhost(at: point)
            return
        }
        if stage == .wetshot, !wallsMode, tool == .erase, let index = pilePiece(at: world(point)) {
            remember()
            map.pile.remove(at: index)
            propsDirty = true
            commit()
            buildPanel()
            return
        }
        if wallsMode {
            // Walls mode: lay the chosen kind, or open a cell that already has it; a stroke goes on doing the same.
            guard case .wall(let kind) = tool else { return }
            remember()
            strokeKind = map.wall(at: cell) == kind ? nil : kind
            painting = true
            setWall(strokeKind, at: cell)
            commit()
            return
        }
        if let marker = marker(at: cell) {
            remember()
            carried = .marker(marker, from: cell)
            showMarkers()
            showGhost(at: point)
            return
        }
        if let index = prop(at: cell) {
            remember()
            let picked = map.props.remove(at: index)
            propsDirty = true
            if tool == .erase {
                painting = true
                commit()
            } else {
                // Picked up whole, to be moved.
                commit()
                carried = .prop(picked.kind, taken: true)
                showGhost(at: point)
            }
            return
        }
        if let index = tornado(at: cell) {
            remember()
            let base = map.tornados.remove(at: index)
            tornadosDirty = true
            if tool == .erase {
                painting = true
                commit()
            } else {
                // Picked up whole, to be moved.
                commit()
                carried = .tornado(from: base)
                showGhost(at: point)
            }
            return
        }
        switch tool {
        case .pile(let kind):
            remember()
            placePile(kind, rotation: 0, at: point)
            commit()
            buildPanel()
        case .prop(let kind):
            remember()
            place(kind, at: cell)
            commit()
        case .tornado:
            remember()
            map.tornados.append(StageMap.fittingTornado(cell))
            tornadosDirty = true
            commit()
        case .erase:
            remember()
            painting = true
            erase(at: cell)
            commit()
        case .marker(let marker):
            remember()
            move(marker, to: cell)
            commit()
            onMarkers()
        case .brush(let art):
            if let placed = tile(at: cell) {
                // Picked up to be moved.
                remember()
                takeAwayTile(at: cell)
                commit()
                carried = .tile(art: placed.art, taken: true)
                showGhost(at: point)
            } else {
                remember()
                painting = true
                place(art, at: cell)
                commit()
            }
        case .stamp:
            // The block put down here, and on along the stroke side by side.
            remember()
            painting = true
            stampOrigin = cell
            stamp(at: cell)
            commit()
        case .wall:
            // Only in walls mode, handled above.
            break
        }
    }

    func moved(to point: CGPoint) {
        if let turning, turnSliders.indices.contains(turning) {
            turn(turnSliders[turning], to: point)
            return
        }
        if let blockStart {
            // Picking a block: from where the drag started to here.
            tool = MapEditor.block(blockStart, sheetCell(at: point))
            showSelection()
            return
        }
        let under = over(point) ? nil : cell(at: point)
        if let under {
            // A block shows its whole size, hanging down and right from the cell.
            var size = (across: 1, down: 1)
            if case .stamp(let first, let last) = tool, !wallsMode { size = (last.column - first.column + 1, last.row - first.row + 1) }
            let rect = hudRect(of: under)
            hover.path = CGPath(rect: CGRect(x: 0, y: -CGFloat(size.down - 1) * cellSide, width: cellSide * CGFloat(size.across),
                                             height: cellSide * CGFloat(size.down)), transform: nil)
            hover.position = rect.origin
            hover.isHidden = false
        } else {
            hover.isHidden = true
        }
        if case .pile = carried {
            ghost?.position = point
        } else if case .prop = carried {
            ghost?.position = CGPoint(x: point.x - cellSide / 2, y: point.y - cellSide / 2)
        } else {
            ghost?.position = point
        }
        ghostMarker?.position = point
        guard painting, let under, under != lastCell else { return }
        lastCell = under
        switch tool {
        case .erase:
            erase(at: under)
            if let index = tornado(at: under) {
                map.tornados.remove(at: index)
                tornadosDirty = true
            }
            if let index = prop(at: under) {
                map.props.remove(at: index)
                propsDirty = true
            }
        case .brush(let art): place(art, at: under)
        case .stamp(let first, let last):
            // Only where a whole block lies beside the last, so they tile.
            if let origin = stampOrigin, (under.column - origin.column) % (last.column - first.column + 1) == 0,
               (origin.row - under.row) % (last.row - first.row + 1) == 0 {
                stamp(at: under)
            }
        case .wall: setWall(strokeKind, at: under)
        case .marker, .tornado, .prop, .pile: break
        }
        commit()
    }

    func ended(at point: CGPoint) {
        turning = nil
        stampOrigin = nil
        if blockStart != nil {
            blockStart = nil
            buildPanel()
            return
        }
        defer {
            carried = nil
            painting = false
            ghost?.removeFromParent()
            ghost = nil
            ghostMarker?.removeFromParent()
            ghostMarker = nil
            hover.isHidden = true
        }
        guard let carried else { return }
        let target = over(point) ? nil : cell(at: point)
        switch carried {
        case .tile(let art, let taken):
            if let target {
                if !taken { remember() }
                place(art, at: target)
                commit()
            } else if taken {
                // Dropped back on the panel or off the stage: taken away, as picked up.
                commit()
            }
        case .marker(let marker, let from):
            move(marker, to: target ?? from)
            commit()
            onMarkers()
        case .prop(let kind, let taken):
            // Dropped on the stage it stands there whole; on the panel or off the stage it's taken away.
            if let target {
                if !taken { remember() }
                place(kind, at: target)
            }
            commit()
        case .tornado:
            // Dropped on the stage it stands there whole; on the panel or off the stage it's taken away.
            if let target {
                map.tornados.append(StageMap.fittingTornado(target))
                tornadosDirty = true
            }
            commit()
        case .pile(let kind, let rotation, let taken):
            // Dropped on the stage it lies there, anywhere; on the panel or off the stage it's taken away.
            if target != nil {
                if !taken { remember() }
                placePile(kind, rotation: rotation, at: point)
            }
            commit()
            buildPanel()
        }
        showMarkers()
    }

    private func showGhost(at point: CGPoint) {
        ghost?.removeFromParent()
        ghostMarker?.removeFromParent()
        ghost = nil
        ghostMarker = nil
        switch carried {
        case .tile(let art, _):
            let sprite = SKSpriteNode(texture: tiles.tile(art))
            sprite.size = CGSize(width: cellSide, height: cellSide)
            sprite.alpha = 0.8
            sprite.zPosition = 10
            sprite.position = point
            addChild(sprite)
            ghost = sprite
        case .tornado:
            let sprite = SKSpriteNode(texture: ElementsArt.tornadoPreview)
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
            sprite.size = CGSize(width: cellSide * 3, height: cellSide * 3)
            sprite.alpha = 0.8
            sprite.zPosition = 10
            sprite.position = point
            addChild(sprite)
            ghost = sprite
        case .pile(let kind, let rotation, _):
            // Held by its middle, as it's put down.
            let sprite = SKSpriteNode(texture: WetshotArt.pileTexture(kind))
            sprite.size = CGSize(width: 48 * cellSide / ElementsArt.tileSide, height: 48 * cellSide / ElementsArt.tileSide)
            sprite.zRotation = CGFloat(rotation) * .pi / 180
            sprite.alpha = 0.8
            sprite.zPosition = 10
            sprite.position = point
            addChild(sprite)
            ghost = sprite
        case .prop(let kind, _):
            // Held by its bottom left cell's middle.
            let sprite = SKSpriteNode(texture: WetshotArt.texture(kind))
            sprite.anchorPoint = .zero
            let pixels = kind.pixelSize
            sprite.size = CGSize(width: CGFloat(pixels.width) * cellSide / ElementsArt.tileSide, height: CGFloat(pixels.height) * cellSide / ElementsArt.tileSide)
            sprite.alpha = 0.8
            sprite.zPosition = 10
            sprite.position = CGPoint(x: point.x - cellSide / 2, y: point.y - cellSide / 2)
            addChild(sprite)
            ghost = sprite
        case .marker(let marker, _):
            let node = markerNode(marker, at: StageMap.Cell(0, 0))
            let holder = SKNode()
            holder.zPosition = 10
            node.position = CGPoint(x: -cellSide / 2, y: -cellSide / 2)
            holder.addChild(node)
            holder.position = point
            addChild(holder)
            ghostMarker = holder
        case nil:
            break
        }
    }
}
#endif
