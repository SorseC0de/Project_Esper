import Foundation

/// One player's controls for one frame. Only held states: the sim works out presses by
/// comparing with the frame before, so a frame of input is a plain value that can be
/// recorded, predicted, and replayed.
public struct PlayerInput: Equatable, Hashable, Codable {
    /// Length 0 to 1, deadzone already removed. +y is up.
    public var stick: Vec2 = .zero
    /// The aim while a stance is held: the flick on the touch button, or the right stick,
    /// or the left stick if neither. Length 0 to 1.
    public var aim: Vec2 = .zero
    public var jump = false
    /// Which shoot buttons are down, one bit each. Any of them shoots with the ball and
    /// swats without it; a second one pressed during a stance cancels the shot.
    public var shootButtons: UInt8 = 0
    public var throwBall = false
    public var taunt = false
    /// The shield's own button (`Shield.swift`).
    public var shield = false

    public static let idle = PlayerInput()

    public init(stick: Vec2 = .zero, aim: Vec2 = .zero, jump: Bool = false,
                shoot: Bool = false, shootButtons: UInt8? = nil, throwBall: Bool = false, taunt: Bool = false, shield: Bool = false) {
        self.stick = stick
        self.aim = aim
        self.jump = jump
        self.shootButtons = shootButtons ?? (shoot ? 1 : 0)
        self.throwBall = throwBall
        self.taunt = taunt
        self.shield = shield
    }

    /// Kept inputs from before the shield's button (ZONES' recorded runs and turns) read with it up.
    private enum CodingKeys: String, CodingKey { case stick, aim, jump, shootButtons, throwBall, taunt, shield }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        stick = try values.decode(Vec2.self, forKey: .stick)
        aim = try values.decode(Vec2.self, forKey: .aim)
        jump = try values.decode(Bool.self, forKey: .jump)
        shootButtons = try values.decode(UInt8.self, forKey: .shootButtons)
        throwBall = try values.decode(Bool.self, forKey: .throwBall)
        taunt = try values.decode(Bool.self, forKey: .taunt)
        shield = try values.decodeIfPresent(Bool.self, forKey: .shield) ?? false
    }

    public var shoot: Bool {
        get { shootButtons != 0 }
        set { shootButtons = newValue ? 1 : 0 }
    }
}

/// Which side a player faces or moves. Raw value is the sign on x.
public enum Facing: Int, Hashable {
    case left = -1
    case right = 1

    public var sign: Double { Double(rawValue) }
    public var flipped: Facing { self == .left ? .right : .left }
}
