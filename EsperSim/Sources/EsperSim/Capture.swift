import Foundation

/// A move Capture Mode makes the other side do on its next step, cutting off whatever it's doing.
public enum ForcedMove: Equatable {
    case slash, shieldflip, floState
}

/// Capture Mode's commands, offline only.
extension Match {
    /// The ball into this player's hands at once, from wherever it is.
    public mutating func takeBall(for index: Int) {
        guard players.indices.contains(index), ball.holder != index else { return }
        if let holder = ball.holder {
            players[holder].loseBall()
            ball.holder = nil
        }
        ballInTruck = false
        ballOutAt = nil
        ballTruckReceiver = nil
        if hoopfish?.carrying == .ball { hoopfish?.carrying = .nothing }
        ball.respawnTimer = 0
        ball.tornadoCentre = nil
        hand(ballTo: index)
        ball.position = players[index].heldBallPoint
    }

    /// The move made on this player's next step; for a slash or a shieldflip, a ball in hand is let go where it is first.
    public mutating func force(_ move: ForcedMove, on index: Int) {
        guard players.indices.contains(index) else { return }
        if move != .floState, ball.holder == index {
            players[index].loseBall()
            ball.holder = nil
            ball.release(from: players[index].heldBallPoint, velocity: .zero, by: index, straight: false)
        }
        players[index].forcedMove = move
    }
}
