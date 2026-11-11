import Foundation

/// Phantom Frappe: the Spin Move or the taunt turns the body phantom, or back. A phantom and a
/// solid body pass through each other and everything the other does: blades, snatches, throws,
/// powers. A phantom passes through the stage's hazards and through every wall and floor but the
/// stage's four outermost, moves through lava as through Hoopfish Hideaway's water, and a dunk
/// passes through the rim. Inside a wall or a floor it can't turn back solid: the spin or the taunt
/// goes, the form stays. The ball a phantom holds is phantom too, and stays
/// so let go: through the walls and floors the same, through the rims without scoring, and only a
/// phantom can take it. Level two: a second Spin Move before landing.
public enum PhantomRules {
    public static let levelTwoSpinsPerAirtime = 2
    /// Online, with the power not FloState's to run out: back solid after this long, unshown, so
    /// nobody can hold the ball out of reach for good.
    public static let failsafeFrames = 600
}

extension Match {
    /// A phantom and a solid body: nothing passes between them.
    func phantomApart(_ first: Int, _ second: Int) -> Bool {
        players[first].phantomMode != players[second].phantomMode
    }

    /// Whether `striker` can touch `victim` at all.
    func reachable(_ victim: Int, by striker: Int) -> Bool {
        !untouchable(victim) && !attacksPass(victim, striker)
    }

    /// Whether `winner`'s counter can stun `loser`: Breaker Ball's snatch still parries a shield.
    func parryable(_ loser: Int, by winner: Int) -> Bool {
        !untouchable(loser) && !phantomApart(loser, winner)
    }

    /// Who's phantom, for the ball to know who can touch it (`Ball.isOpen`).
    var phantomPlayerBits: Int {
        players.indices.reduce(0) { bits, index in players[index].phantomMode ? bits | (1 << index) : bits }
    }

    /// After the bodies move: the held ball as phantom as its holder; a phantom only while the ball
    /// is, so none is left phantom with no ball it can ever take (the ball reset, or taken solid by
    /// another); a phantom ball only while someone is, so it's never left where nobody can take it.
    mutating func settlePhantoms() {
        for index in players.indices where players[index].phantomMode {
            players[index].phantomFrames += 1
            let lasting = players[index].floStatePower == .none && players[index].floStateDrink == nil
            if players[index].power != .phantomFrappe || (phantomFailsafe && lasting && players[index].phantomFrames >= PhantomRules.failsafeFrames) {
                players[index].phantomMode = false
                events.append(.phantomToggled(player: index, phantom: false))
            }
        }
        if let holder = ball.holder { ball.phantom = players[holder].phantomMode }
        if !ball.phantom {
            for index in players.indices where players[index].phantomMode {
                players[index].phantomMode = false
                events.append(.phantomToggled(player: index, phantom: false))
            }
        } else if !players.contains(where: \.phantomMode) {
            ball.phantom = false
        }
        ball.phantomPlayers = phantomPlayerBits
    }
}

extension Stage {
    /// The stage as a phantom meets it: only its four outermost walls, the grid's edge tiles and what's
    /// past them; nothing inside, nothing standing on the stage, no one-ways, no slopes. Under the lava's
    /// surface, `submerged`, it's water.
    public func phantomShell(submerged: Bool = false) -> Stage {
        var shell = self
        var kept = Array(repeating: Tile.empty, count: tiles.count)
        for row in 0..<rows {
            for column in 0..<columns where (row == 0 || row == rows - 1 || column == 0 || column == columns - 1)
                && tiles[row * columns + column] == .solid {
                kept[row * columns + column] = .solid
            }
        }
        shell.tiles = kept
        shell.skyWallColumns = []
        if submerged { shell.features.underwater = true }
        shell.extras = []
        shell.fixedExtras = []
        shell.slopes = []
        shell.fixedSlopes = []
        shell.ceilingSlopes = []
        shell.oneWayBoxes = []
        shell.rightwardWalls = []
        shell.shieldWalls = []
        shell.platformBoxes = []
        shell.springs = []
        shell.conveyors = []
        shell.dropPlatforms = []
        shell.unridable = []
        shell.ballBlockers = []
        return shell
    }
}
