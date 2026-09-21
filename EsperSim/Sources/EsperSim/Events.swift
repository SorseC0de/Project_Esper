import Foundation

/// Something that happened this frame that the screen might want to show. Cleared every
/// frame; nothing in the sim reads them back.
public enum MatchEvent: Equatable {
    case jumped(player: Int)
    case doubleJumped(player: Int)
    case wallJumped(player: Int, wall: Facing)
    case dashed(player: Int)
    case landed(player: Int)
    case caught(player: Int)
    case shot(player: Int)
    case thrown(player: Int)
    case dunked(player: Int)
    case swatted(player: Int, hit: Bool)
    case scored(player: Int, hoop: Int)
    case ballBounced(position: Vec2)
    case ballRespawned
    case webSwung(player: Int)
    case webShot(player: Int, hit: Bool)
}

/// What a player's step asks the match to do with the ball.
public enum PlayerAction: Equatable {
    case releaseShot(velocity: Vec2)
    case releaseThrow(velocity: Vec2)
    case dunk(hoop: Int)
    case swat
    case webShot(direction: Vec2)
}
