/// The Wreck Center's pieces, from its map: the conveyors on the backboard blocks, which carry
/// whatever's on them as fast as their belts are drawn moving; and the one-way platforms, which turn once when someone drops through one,
/// standable again only once it's back on its first frame.
public struct Conveyor: Equatable {
    public let box: Box
    /// +1 to the right, -1 to the left.
    public let way: Double
    /// Carrying what's on it; stopped, it's only a floor (the Tutorial's, till it's started).
    public var running = true
    /// Units a frame it carries at.
    public var speed = WreckCenterRules.beltSpeed
}

public struct DropPlatform: Equatable {
    public let columns: ClosedRange<Int>
    public let row: Int
    public var top: Double { Double(row + 1) * Stage.tileSize }
}

public enum WreckCenterRules {
    /// The platform's eight art frames, at twenty a second: twice the other pieces' pace.
    public static let platformArtFrames = 8
    public static let platformFramesPerArtFrame = 3
    public static var platformFrames: Int { platformArtFrames * platformFramesPerArtFrame }
    /// What a belt carries at, in units a frame: its art moves 2 pixels a frame at the pieces'
    /// 10 frames a second, 1.6 pixels a unit, over the sim's 60.
    public static let beltArtPixelsPerFrame = 2.0
    public static let beltSpeed = beltArtPixelsPerFrame * 10 / 1.6 / 60

    /// The platform's art frame for the frames left of its turn.
    public static func platformArtFrame(framesLeft: Int) -> Int {
        framesLeft <= 0 ? 0 : min((platformFrames - framesLeft) / platformFramesPerArtFrame, platformArtFrames - 1)
    }
}

extension Stage {
    /// Each piece is two cells wide and two high, its bottom left on its cell: a platform's top
    /// row is one-way; a conveyor's top is the block under it.
    mutating func layWreckCenterPieces(_ props: [StageMap.Prop]) {
        for prop in props {
            let column = prop.cell.column
            switch prop.kind {
            case .onewayPlatform:
                let platform = DropPlatform(columns: column...(column + 1), row: prop.cell.row + 1)
                fill(.oneWay, columns: platform.columns, rows: platform.row...platform.row)
                dropPlatforms.append(platform)
            case .conveyorL, .conveyorM, .conveyorR, .flippedConveyorL, .flippedConveyorM, .flippedConveyorR:
                let top = Double(prop.cell.row + 2) * Stage.tileSize
                let flipped = [.flippedConveyorL, .flippedConveyorM, .flippedConveyorR].contains(prop.kind)
                conveyors.append(Conveyor(box: Box(min: Vec2(x: Double(column) * Stage.tileSize, y: top - Stage.tileSize),
                                                   max: Vec2(x: Double(column + 2) * Stage.tileSize, y: top)),
                                          way: flipped ? -1 : 1))
            default: break
            }
        }
    }
}

extension Match {
    /// The belts carry what's on them; a platform mid-turn counts down, standable again at its end.
    mutating func stepWreckCenter() {
        guard !stage.conveyors.isEmpty || !stage.dropPlatforms.isEmpty else { return }
        if dropPlatformFrames.count != stage.dropPlatforms.count { dropPlatformFrames = Array(repeating: 0, count: stage.dropPlatforms.count) }
        for index in dropPlatformFrames.indices where dropPlatformFrames[index] > 0 {
            dropPlatformFrames[index] -= 1
            if dropPlatformFrames[index] == 0 {
                let platform = stage.dropPlatforms[index]
                stage.fill(.oneWay, columns: platform.columns, rows: platform.row...platform.row)
            }
        }
        // A body on a belt, carried once whatever pieces it straddles.
        for index in players.indices {
            guard let belt = stage.conveyors.first(where: { $0.running && stands(players[index], on: $0.box) }) else { continue }
            carry(index, by: belt.way * belt.speed)
        }
        // The loose ball sitting on one, along it till it's off the end and drops.
        if ball.isLive, ball.holder == nil, ball.tether == nil, ball.frozen == 0, ball.velocity.y == 0,
           let belt = stage.conveyors.first(where: { $0.running && abs(ball.position.y - BallRules.radius - $0.box.max.y) < 0.5
               && ball.position.x + BallRules.radius > $0.box.min.x && ball.position.x - BallRules.radius < $0.box.max.x }) {
            ball.position.x += belt.way * belt.speed
            ball.resting = false
            // Off the end it drops into the rim below, and goes in.
            ball.scoring = true
        }
    }

    /// Whoever just dropped through a platform sets that one turning; till it's done it holds nobody.
    mutating func turnDroppedPlatforms() {
        guard !stage.dropPlatforms.isEmpty else { return }
        if dropPlatformFrames.count != stage.dropPlatforms.count { dropPlatformFrames = Array(repeating: 0, count: stage.dropPlatforms.count) }
        for player in players where player.dropThrough == DropRules.passFrames {
            let x = player.position.x
            guard let index = stage.dropPlatforms.indices.first(where: { index in
                let platform = stage.dropPlatforms[index]
                return dropPlatformFrames[index] == 0 && abs(player.position.y - platform.top) <= Stage.tileSize / 2
                    && x >= Double(platform.columns.lowerBound) * Stage.tileSize && x <= Double(platform.columns.upperBound + 1) * Stage.tileSize
            }) else { continue }
            dropPlatformFrames[index] = WreckCenterRules.platformFrames
            let platform = stage.dropPlatforms[index]
            stage.fill(.empty, columns: platform.columns, rows: platform.row...platform.row)
        }
    }
}

/// The Tutorial's rooms (`Stage.tutorial`): each a court wide, side by side; its doors, in the
/// openings at the floor's ends of the walls (the first room's left, between each two rooms, the
/// last's right), four rows high over the floor; its belt this many times the Wreck Center's.
public enum TutorialRules {
    public static let roomColumns = 34
    public static let rooms = 2
    public static let doorRows = 1...4
    public static let beltSpeed = WreckCenterRules.beltSpeed * 6
    /// Each door's wall columns, left to right.
    public static var doorColumns: [ClosedRange<Int>] {
        [0...0] + (1..<rooms).map { ($0 * roomColumns - 1)...($0 * roomColumns) } + [(rooms * roomColumns - 1)...(rooms * roomColumns - 1)]
    }
    /// The hub's hoops on its back wall (`Hoop.frontFacing`), art pixels from a room's bottom
    /// left to each rim's middle: in staggered rows, three, then four, the top row's at
    /// `hubTopRow`, the columns `hubColumnSpacing` apart and the rows `hubRowSpacing` (HUB
    /// COLUMNS and HUB ROWS on the debug strip).
    public static let hubRowCounts = [3, 4]
    public static let hubTopRow = 156.0
    nonisolated(unsafe) public static var hubColumnSpacing = 100.0
    nonisolated(unsafe) public static var hubRowSpacing = 60.0
    public static var hubSlots: [Vec2] {
        let middle = 272.0
        return hubRowCounts.enumerated().flatMap { row, count in
            (0..<count).map { index in
                Vec2(x: middle + (Double(index) - Double(count - 1) / 2) * hubColumnSpacing, y: hubTopRow - Double(row) * hubRowSpacing)
            }
        }
    }
    public static var hubSlotCount: Int { hubRowCounts.reduce(0, +) }
    /// A slot's row, top first.
    public static func hubRow(of slot: Int) -> Int {
        var first = 0
        for (row, count) in hubRowCounts.enumerated() {
            if slot < first + count { return row }
            first += count
        }
        return hubRowCounts.count - 1
    }
    /// A page turned, the hub's rows carried along their belts, the top right and the next left
    /// and so on, each hoop off one end of the room coming back on at the other: `hubLap` art
    /// pixels round, a room and a picture's width (half off each end), so a hoop's out of sight
    /// as it goes round, and a whole lap brings each back to its slot.
    public static let hubWrapMargin = 24.0
    public static var hubLap: Double { Double(roomColumns) * 16 + 2 * hubWrapMargin }
    /// Where a slot's hoop is with its row carried `slide` art pixels along (up to `hubLap` either
    /// way, back negative), and whether it's gone round yet.
    public static func hubPlace(slot: Int, slide: Double) -> (place: Vec2, wrapped: Bool) {
        let home = hubSlots[slot]
        let way = hubRow(of: slot) % 2 == 0 ? 1.0 : -1.0
        let carried = home.x + way * slide + hubWrapMargin
        let lapped = carried - (carried / hubLap).rounded(.down) * hubLap
        return (Vec2(x: lapped - hubWrapMargin, y: home.y), carried < 0 || carried >= hubLap)
    }
    /// The stage's hoops, by place: each room's rim on its right (the lessons'), then each room's
    /// hub hoops, slot by slot, then each room's rim on its left (up in the hub alone). Every one
    /// parked off the stage till the room shows it.
    public static func hoops(rim: Vec2) -> [Hoop] {
        let side = (0..<rooms).map { _ in Hoop(position: HighwayRules.parked, owner: 0, backboard: .right, shared: true) }
        let hub = (0..<(rooms * hubSlotCount)).map { _ in
            var hoop = Hoop(position: HighwayRules.parked, owner: 0, backboard: .right, shared: true)
            hoop.frontFacing = true
            return hoop
        }
        let left = (0..<rooms).map { _ in Hoop(position: HighwayRules.parked, owner: 0, backboard: .left, shared: true) }
        sideRim = rim
        return side + hub + left
    }
    /// The first room's rim, as the stage lays it: each room's is this one rooms along; its left
    /// one the mirror of it.
    nonisolated(unsafe) public static var sideRim = Vec2.zero
    public static func sideHoop(room: Int) -> Int { room }
    public static func hubHoop(slot: Int, room: Int) -> Int { rooms + room * hubSlotCount + slot }
    public static func leftHoop(room: Int) -> Int { rooms + rooms * hubSlotCount + room }
    /// Which hub slot a hoop is, if it's one.
    public static func hubSlot(of hoop: Int) -> Int? {
        let index = hoop - rooms
        guard index >= 0, index < rooms * hubSlotCount else { return nil }
        return index % hubSlotCount
    }
    /// The first room's blocks, the rims' beams, left and right: their columns, and their rows.
    nonisolated(unsafe) public static var blockColumns: [ClosedRange<Int>] = []
    nonisolated(unsafe) public static var blockRows = 0...0
    public static func roomWidth() -> Double { Double(roomColumns) * Stage.tileSize }
    /// The rims' backboards stand down to the blocks' undersides, as the court's do.
    nonisolated(unsafe) public static var backboardUnderside = 0.0

    /// A room's middle across, units.
    public static func roomMiddle(_ room: Int) -> Double { (Double(room) + 0.5) * Double(roomColumns) * Stage.tileSize }
    /// A door's middle across, units.
    public static func doorMiddle(_ door: Int) -> Double {
        let columns = doorColumns[door]
        return Double(columns.lowerBound + columns.upperBound + 1) / 2 * Stage.tileSize
    }
}

extension Match {
    /// A Tutorial door's opening walked through or shut again.
    public mutating func setTutorialDoor(_ door: Int, open: Bool) {
        guard TutorialRules.doorColumns.indices.contains(door) else { return }
        stage.fill(open ? .empty : .solid, columns: TutorialRules.doorColumns[door], rows: TutorialRules.doorRows)
    }
}

/// A Tutorial room laid out: its rim on the right; or the hub's hoops on its back wall, carried
/// along their belts as far as a page turn has them, with rims on both sides; or nothing,
/// everything of it parked.
public enum TutorialRoomLayout { case rim, hub, empty }

extension Stage {
    /// A room's hoops put up or parked, and the backboards of the rims up solid behind them.
    public mutating func layTutorialRoom(_ room: Int, as layout: TutorialRoomLayout, slide: Double = 0) {
        guard room < TutorialRules.rooms, hoops.count > TutorialRules.leftHoop(room: TutorialRules.rooms - 1) else { return }
        let shift = Double(room) * TutorialRules.roomWidth()
        let sides = layout != .empty
        hoops[TutorialRules.sideHoop(room: room)].position = sides ? TutorialRules.sideRim + Vec2(x: shift, y: 0) : HighwayRules.parked
        hoops[TutorialRules.leftHoop(room: room)].position = layout == .hub
            ? Vec2(x: TutorialRules.roomWidth() - TutorialRules.sideRim.x + shift, y: TutorialRules.sideRim.y) : HighwayRules.parked
        for slot in 0..<TutorialRules.hubSlotCount {
            hoops[TutorialRules.hubHoop(slot: slot, room: room)].position = layout == .hub
                ? TutorialRules.hubPlace(slot: slot, slide: slide).place / 1.6 + Vec2(x: shift, y: 0) : HighwayRules.parked
        }
        fixedExtras = hoops.filter { !$0.frontFacing && $0.position != HighwayRules.parked }.map { hoop in
            let side = hoop.backboard.sign
            let face = hoop.position.x + side * Stage.backboardFace, back = face + side * Stage.backboardDepth
            return Box(min: Vec2(x: min(face, back), y: hoop.position.y + Stage.backboardBottom), max: Vec2(x: max(face, back), y: TutorialRules.backboardUnderside))
        }
        extras = fixedExtras
    }
}

extension Match {
    public mutating func layTutorialRoom(_ room: Int, as layout: TutorialRoomLayout, slide: Double = 0) { stage.layTutorialRoom(room, as: layout, slide: slide) }
}
