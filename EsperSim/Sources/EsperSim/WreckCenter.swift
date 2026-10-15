/// The Wreck Center's pieces, from its map: the conveyors on the backboard blocks, which carry
/// whatever's on them as fast as their belts are drawn moving; and the one-way platforms, which turn once when someone drops through one,
/// standable again only once it's back on its first frame.
public struct Conveyor: Equatable {
    public let box: Box
    /// +1 to the right, -1 to the left.
    public let way: Double
}

public struct DropPlatform: Equatable {
    public let columns: ClosedRange<Int>
    public let row: Int
    public var top: Double { Double(row + 1) * Stage.tileSize }
}

public enum WreckCenterRules {
    /// The platform's eight art frames at the pieces' ten a second.
    public static let platformArtFrames = 8
    public static let platformFramesPerArtFrame = 6
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
            guard let belt = stage.conveyors.first(where: { stands(players[index], on: $0.box) }) else { continue }
            carry(index, by: belt.way * WreckCenterRules.beltSpeed)
        }
        // The loose ball sitting on one, along it till it's off the end and drops.
        if ball.isLive, ball.holder == nil, ball.tether == nil, ball.frozen == 0, ball.velocity.y == 0,
           let belt = stage.conveyors.first(where: { abs(ball.position.y - BallRules.radius - $0.box.max.y) < 0.5
               && ball.position.x + BallRules.radius > $0.box.min.x && ball.position.x - BallRules.radius < $0.box.max.x }) {
            ball.position.x += belt.way * WreckCenterRules.beltSpeed
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
