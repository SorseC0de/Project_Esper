import Foundation

/// One player's controls for one frame. Only held states: the sim works out presses by
/// comparing with the frame before, so a frame of input is a plain value that can be
/// recorded, predicted, and replayed.
public struct PlayerInput: Equatable, Hashable {
    /// Length 0 to 1, deadzone already removed. +y is up.
    public var stick: Vec2 = .zero
    /// The aim while a stance is held: the flick on the touch button, or the right stick,
    /// or the left stick if neither. Length 0 to 1.
    public var aim: Vec2 = .zero
    public var jump = false
    /// Shoots with the ball, swats without it.
    public var shoot = false
    public var throwBall = false
    public var taunt = false

    public static let idle = PlayerInput()

    public init(stick: Vec2 = .zero, aim: Vec2 = .zero, jump: Bool = false,
                shoot: Bool = false, throwBall: Bool = false, taunt: Bool = false) {
        self.stick = stick
        self.aim = aim
        self.jump = jump
        self.shoot = shoot
        self.throwBall = throwBall
        self.taunt = taunt
    }
}

/// Which side a player faces or moves. Raw value is the sign on x.
public enum Facing: Int, Hashable {
    case left = -1
    case right = 1

    public var sign: Double { Double(rawValue) }
    public var flipped: Facing { self == .left ? .right : .left }
}
