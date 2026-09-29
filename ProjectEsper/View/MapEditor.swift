import EsperSim
import Foundation
import SpriteKit

/// The Elements' map, as last kept between launches by the map maker; nil until it's used.
enum SavedElementsMap {
    private static let key = "esper.elementsMap"
    static var value: ElementsMap? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(ElementsMap.self, from: $0) }
    }
    static func store(_ map: ElementsMap?) {
        if let map, let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

#if !os(tvOS)
import UIKit

/// The Elements' map maker, for a mouse: the tileset laid out in a panel to pick tiles from,
/// the stage under a grid. Drag a tile from the panel onto the stage to drop it; press one on
/// the stage to pick it up and move it, dropping it back on the panel to take it away; press
/// an empty cell with a tile chosen and drag to paint with it. The markers (the two rims,
/// the two starts and the ball) are chosen and dropped the same way. UNDO steps back, COPY
/// puts the map on the clipboard as Swift for `ElementsMap.defaultMap`. The map is kept
/// between launches and stands in for the baked one offline.
final class MapEditor: SKNode {
    private enum Tool: Equatable {
        case brush(ElementsMap.Cell)
        case erase
        case marker(Marker)
    }

    private enum Marker: Equatable, CaseIterable {
        case leftRim, rightRim, firstStart, secondStart, ball

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
        case tile(art: ElementsMap.Cell, taken: Bool)
        case marker(Marker, from: ElementsMap.Cell)
    }

    private(set) var map: ElementsMap
    private var history: [ElementsMap] = []
    private var tool: Tool
    private var carried: Carried?
    private var painting = false
    private var lastCell: ElementsMap.Cell?
    /// Cells whose tile changed since the game was last told.
    private var dirty: Set<ElementsMap.Cell> = []

    private let halfWidth: CGFloat, halfHeight: CGFloat
    /// Stage units for a HUD point and back: the camera's place and how many units a point covers.
    private let world: (CGPoint) -> CGPoint
    private let hudFromWorld: (CGPoint) -> CGPoint
    private let unitsPerHud: CGFloat
    private let onTiles: ([ElementsMap.Cell]) -> Void
    private let onMarkers: () -> Void
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
    private var panelRect = CGRect.zero
    private var paletteShown = true
    private static let paletteScale: CGFloat = 1.25

    init(map: ElementsMap, halfWidth: CGFloat, halfHeight: CGFloat, unitsPerHud: CGFloat, world: @escaping (CGPoint) -> CGPoint,
         hudFromWorld: @escaping (CGPoint) -> CGPoint, onTiles: @escaping ([ElementsMap.Cell]) -> Void,
         onMarkers: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.map = map
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        self.unitsPerHud = unitsPerHud
        self.world = world
        self.hudFromWorld = hudFromWorld
        self.onTiles = onTiles
        self.onMarkers = onMarkers
        self.onClose = onClose
        tool = .brush(ElementsArt.filled.first { $0 == ElementsMap.Cell(3, 3) } ?? ElementsArt.filled[0])
        super.init()
        zPosition = 500
        addChild(grid)
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
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Geometry

    private var cellSide: CGFloat { ElementsArt.tileSide / unitsPerHud }

    private func cell(at hudPoint: CGPoint) -> ElementsMap.Cell? {
        let point = world(hudPoint)
        let column = Int((point.x / ElementsArt.tileSide).rounded(.down)), row = Int((point.y / ElementsArt.tileSide).rounded(.down))
        guard (0..<ElementsRules.columns).contains(column), (0..<ElementsRules.rows).contains(row) else { return nil }
        return ElementsMap.Cell(column, row)
    }

    private func hudRect(of cell: ElementsMap.Cell) -> CGRect {
        let origin = hudFromWorld(CGPoint(x: CGFloat(cell.column) * ElementsArt.tileSide, y: CGFloat(cell.row) * ElementsArt.tileSide))
        return CGRect(x: origin.x, y: origin.y, width: cellSide, height: cellSide)
    }

    private func buildGrid() {
        let path = CGMutablePath()
        for column in 0...ElementsRules.columns {
            let x = hudFromWorld(CGPoint(x: CGFloat(column) * ElementsArt.tileSide, y: 0)).x
            path.move(to: CGPoint(x: x, y: hudFromWorld(.zero).y))
            path.addLine(to: CGPoint(x: x, y: hudFromWorld(CGPoint(x: 0, y: CGFloat(ElementsRules.rows) * ElementsArt.tileSide)).y))
        }
        for row in 0...ElementsRules.rows {
            let y = hudFromWorld(CGPoint(x: 0, y: CGFloat(row) * ElementsArt.tileSide)).y
            path.move(to: CGPoint(x: hudFromWorld(.zero).x, y: y))
            path.addLine(to: CGPoint(x: hudFromWorld(CGPoint(x: CGFloat(ElementsRules.columns) * ElementsArt.tileSide, y: 0)).x, y: y))
        }
        grid.path = path
        grid.strokeColor = SKColor(white: 1, alpha: 0.13)
        grid.lineWidth = 0.5
        grid.isAntialiased = false
    }

    // MARK: The panel

    private func buildPanel() {
        panel.removeAllChildren()
        buttons = []
        let scale = MapEditor.paletteScale
        let paletteSize = CGSize(width: 240 * scale, height: 112 * scale)
        let margin: CGFloat = 8
        let left = -halfWidth + margin, bottom = -halfHeight + margin
        let rowHeight: CGFloat = 22
        let controlRows: CGFloat = 2
        let panelHeight = (paletteShown ? paletteSize.height + margin : 0) + rowHeight * controlRows + margin
        panelRect = CGRect(x: left - 4, y: bottom - 4, width: max(paletteSize.width, 330) + 8, height: panelHeight + 8)
        let back = SKSpriteNode(color: SKColor(white: 0.05, alpha: 0.9), size: panelRect.size)
        back.anchorPoint = .zero
        back.position = panelRect.origin
        panel.addChild(back)
        selection.removeFromParent()
        var y = bottom
        if paletteShown {
            paletteRect = CGRect(x: left, y: y, width: paletteSize.width, height: paletteSize.height)
            let sheet = SKSpriteNode(texture: ElementsArt.tileset)
            sheet.anchorPoint = .zero
            sheet.size = paletteSize
            sheet.position = paletteRect.origin
            sheet.zPosition = 1
            panel.addChild(sheet)
            selection.zPosition = 2
            selection.strokeColor = SKColor(red: 1, green: 0.9, blue: 0.2, alpha: 1)
            selection.lineWidth = 1.5
            selection.fillColor = .clear
            panel.addChild(selection)
            y += paletteSize.height + margin
        } else {
            paletteRect = .zero
        }
        // Two rows of buttons: the tools and markers, then the actions.
        let toolRow: [(String, () -> Void)] = [("ERASE", { [weak self] in self?.tool = .erase; self?.showSelection() })]
            + Marker.allCases.map { marker in (marker.label, { [weak self] in self?.tool = .marker(marker); self?.showSelection() }) }
        let actionRow: [(String, () -> Void)] = [
            ("UNDO", { [weak self] in self?.undo() }), ("RESET", { [weak self] in self?.reset() }), ("COPY", { [weak self] in self?.copy() }),
            (paletteShown ? "HIDE TILES" : "TILES", { [weak self] in self?.togglePalette() }), ("CLOSE", { [weak self] in self?.onClose() }),
        ]
        for (row, items) in [actionRow, toolRow].enumerated() {
            var x = left
            for (title, action) in items {
                let label = SKLabelNode(text: title)
                label.fontName = "Menlo-Bold"
                label.fontSize = 9
                label.fontColor = .white
                label.verticalAlignmentMode = .center
                label.horizontalAlignmentMode = .left
                let width = label.frame.width + 10
                let rect = CGRect(x: x, y: y + CGFloat(row) * rowHeight, width: width, height: rowHeight - 4)
                let box = SKShapeNode(rect: rect, cornerRadius: 3)
                box.fillColor = SKColor(white: 0.25, alpha: 1)
                box.strokeColor = SKColor(white: 1, alpha: 0.3)
                box.zPosition = 1
                label.position = CGPoint(x: rect.minX + 5, y: rect.midY)
                label.zPosition = 2
                panel.addChild(box)
                panel.addChild(label)
                buttons.append((rect, action))
                x += width + 4
            }
        }
        showSelection()
    }

    private func togglePalette() {
        paletteShown.toggle()
        buildPanel()
    }

    /// The chosen tile ringed in the panel.
    private func showSelection() {
        guard paletteShown, case .brush(let art) = tool else { selection.isHidden = true; return }
        selection.isHidden = false
        let side = 16 * MapEditor.paletteScale
        selection.path = CGPath(rect: CGRect(x: paletteRect.minX + CGFloat(art.column) * side,
                                             y: paletteRect.maxY - CGFloat(art.row + 1) * side, width: side, height: side), transform: nil)
    }

    private func paletteCell(at point: CGPoint) -> ElementsMap.Cell? {
        guard paletteShown, paletteRect.contains(point) else { return nil }
        let side = 16 * MapEditor.paletteScale
        let cell = ElementsMap.Cell(Int((point.x - paletteRect.minX) / side), Int((paletteRect.maxY - point.y) / side))
        return ElementsArt.filled.contains(cell) ? cell : nil
    }

    // MARK: The map

    private func tile(at cell: ElementsMap.Cell) -> ElementsMap.Placed? { map.tiles.first { $0.cell == cell } }

    private func markerCell(_ marker: Marker) -> ElementsMap.Cell {
        switch marker {
        case .leftRim: map.leftRim
        case .rightRim: map.rightRim
        case .firstStart: map.spawns[0]
        case .secondStart: map.spawns[1]
        case .ball: map.ball
        }
    }

    private func marker(at cell: ElementsMap.Cell) -> Marker? { Marker.allCases.first { markerCell($0) == cell } }

    private func move(_ marker: Marker, to cell: ElementsMap.Cell) {
        switch marker {
        case .leftRim: map.leftRim = cell
        case .rightRim: map.rightRim = cell
        case .firstStart: map.spawns[0] = cell
        case .secondStart: map.spawns[1] = cell
        case .ball: map.ball = cell
        }
    }

    private func place(_ art: ElementsMap.Cell, at cell: ElementsMap.Cell) {
        map.tiles.removeAll { $0.cell == cell }
        map.tiles.append(.init(cell, art: art))
        dirty.insert(cell)
    }

    private func erase(at cell: ElementsMap.Cell) {
        guard tile(at: cell) != nil else { return }
        map.tiles.removeAll { $0.cell == cell }
        dirty.insert(cell)
    }

    private func remember() {
        history.append(map)
        if history.count > 200 { history.removeFirst() }
    }

    /// The map kept and given to the game, which is told which tiles changed.
    private func commit() {
        SavedElementsMap.store(map)
        ElementsMap.current = map
        if !dirty.isEmpty {
            let changed = Array(dirty)
            dirty = []
            onTiles(changed)
        }
        showMarkers()
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        applyWholeMap(previous)
    }

    private func reset() {
        remember()
        applyWholeMap(ElementsMap.baked)
    }

    private func applyWholeMap(_ next: ElementsMap) {
        let changed = Set(map.tiles.map(\.cell)).symmetricDifference(Set(next.tiles.map(\.cell)))
            .union(Set(map.tiles).symmetricDifference(Set(next.tiles)).map(\.cell))
        map = next
        dirty.formUnion(changed)
        commit()
        onMarkers()
    }

    private func copy() {
        UIPasteboard.general.string = map.swiftSource
    }

    /// Where each marker sits, as a coloured square with its letters.
    private func showMarkers() {
        markerLayer.removeAllChildren()
        for marker in Marker.allCases {
            guard !(isCarrying(marker)) else { continue }
            markerLayer.addChild(markerNode(marker, at: markerCell(marker)))
        }
    }

    private func isCarrying(_ marker: Marker) -> Bool {
        if case .marker(let carriedMarker, _) = carried { return carriedMarker == marker }
        return false
    }

    private func markerNode(_ marker: Marker, at cell: ElementsMap.Cell) -> SKNode {
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
        if let art = paletteCell(at: point) {
            tool = .brush(art)
            showSelection()
            carried = .tile(art: art, taken: false)
            showGhost(at: point)
            return
        }
        guard !over(point), let cell = cell(at: point) else { return }
        lastCell = cell
        if let marker = marker(at: cell) {
            remember()
            carried = .marker(marker, from: cell)
            showMarkers()
            showGhost(at: point)
            return
        }
        switch tool {
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
                map.tiles.removeAll { $0.cell == cell }
                dirty.insert(cell)
                commit()
                carried = .tile(art: placed.art, taken: true)
                showGhost(at: point)
            } else {
                remember()
                painting = true
                place(art, at: cell)
                commit()
            }
        }
    }

    func moved(to point: CGPoint) {
        let under = over(point) ? nil : cell(at: point)
        if let under {
            let rect = hudRect(of: under)
            hover.path = CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil)
            hover.position = rect.origin
            hover.isHidden = false
        } else {
            hover.isHidden = true
        }
        ghost?.position = point
        ghostMarker?.position = point
        guard painting, let under, under != lastCell else { return }
        lastCell = under
        switch tool {
        case .erase: erase(at: under)
        case .brush(let art): place(art, at: under)
        case .marker: break
        }
        commit()
    }

    func ended(at point: CGPoint) {
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
            let sprite = SKSpriteNode(texture: ElementsArt.tile(art))
            sprite.size = CGSize(width: cellSide, height: cellSide)
            sprite.alpha = 0.8
            sprite.zPosition = 10
            sprite.position = point
            addChild(sprite)
            ghost = sprite
        case .marker(let marker, _):
            let node = markerNode(marker, at: ElementsMap.Cell(0, 0))
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
