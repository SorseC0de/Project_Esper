/// Wetshot Wake's Hoopfish: it starts at the map's height with the ball on its antenna, far
/// enough right that the ball's over the centre column as play starts, and swims off the side it faces; then, two seconds off screen, it comes back from that side,
/// turned round, from a height off the count, swimming ten seconds across to a height off the
/// count on the far side, swaying up and down as it goes, over and over. The ball stays on its
/// antenna until a hand takes it, crossing after crossing; what's on the antenna changes only
/// off screen, and once the ball's been taken it's the stage's rim from then on.
public struct Hoopfish: Equatable {
    public enum Carrying: Equatable { case ball, hoop, nothing }

    /// Its picture's bottom left, and which way it faces: the art faces left.
    public var position: Vec2
    public var facesRight = false
    public var carrying: Carrying
    /// Which crossing it's on, frames into it, and where it set off from and is headed.
    public var crossing = 0
    public var age = 0
    public var from: Vec2
    public var to: Vec2
    /// This crossing's swim, in frames: the first, from where it's placed, only as long as its way off.
    public var swimFrames: Int
    /// Frames left of the spin a dunk sets off, the rim out of play through it.
    public var spin = 0

    /// Where the rim, or the ball, rides on its antenna: whole art pixels from its bottom left.
    public var antenna: Vec2 {
        let across = Double(facesRight ? HoopfishRules.pixelWidth - WetshotRules.rimPixelsAcross : WetshotRules.rimPixelsAcross)
        return position + Vec2(x: across / 1.6, y: Double(WetshotRules.rimPixelsUp) / 1.6)
    }

    /// Where the ball hangs on its antenna until a hand takes it.
    public var ballPoint: Vec2 {
        let across = Double(facesRight ? HoopfishRules.pixelWidth - WetshotRules.ballPixelsAcross : WetshotRules.ballPixelsAcross)
        return position + Vec2(x: across / 1.6, y: Double(WetshotRules.ballPixelsUp) / 1.6)
    }

    /// Off screen, between crossings.
    public var away: Bool { age >= swimFrames }

    /// At the map's height, and far enough right that, swimming through the count, the ball on
    /// its antenna is over the middle of the stage's centre column the moment play starts.
    static func starting(at cell: Vec2, on stage: Stage, countdown: Int) -> Hoopfish {
        let offLeft = -HoopfishRules.size.x
        let speed = HoopfishRules.crossing(stage) / Double(HoopfishRules.swimFrames)
        let centre = (Double(stage.columns / 2) + 0.5) * Stage.tileSize
        let goal = centre - Double(WetshotRules.ballPixelsAcross) / 1.6
        // Its swim to off the side in whole frames, and from where that brings it to the goal on the count's last frame.
        let frames = max(Int(((goal + speed * Double(countdown) - offLeft) / speed).rounded()), 1)
        let share = Double(min(countdown, frames - 1)) / Double(frames)
        let start = Vec2(x: (goal - offLeft * share) / (1 - share), y: cell.y)
        return Hoopfish(position: start, carrying: .ball, from: start, to: Vec2(x: offLeft, y: HoopfishRules.height(1, on: stage)),
                          swimFrames: frames)
    }

    /// A frame on: swimming, swaying, then waiting off screen, then the next crossing back.
    mutating func step(on stage: Stage) {
        if spin > 0 { spin -= 1 }
        age += 1
        if age < swimFrames {
            let share = Double(age) / Double(swimFrames)
            let sway = HoopfishRules.swayHeight * Trig.sin(share * HoopfishRules.swaysPerCrossing * 2 * Double.pi)
            let y = min(max(from.y + (to.y - from.y) * share + sway, HoopfishRules.lowest), HoopfishRules.highest(stage))
            position = Vec2(x: from.x + (to.x - from.x) * share, y: y)
            return
        }
        position = to
        guard age >= swimFrames + HoopfishRules.waitFrames else { return }
        crossing += 1
        age = 0
        facesRight.toggle()
        if carrying == .nothing { carrying = .hoop }
        let offLeft = -HoopfishRules.size.x, offRight = stage.width
        let start = HoopfishRules.height(crossing * 2, on: stage), end = HoopfishRules.height(crossing * 2 + 1, on: stage)
        from = Vec2(x: facesRight ? offLeft : offRight, y: start)
        to = Vec2(x: facesRight ? offRight : offLeft, y: end)
        position = from
        swimFrames = HoopfishRules.swimFrames
    }
}

public enum HoopfishRules {
    /// Its picture, 96 by 48 art pixels, in units.
    public static let pixelWidth = 96
    public static let size = Vec2(x: 96 / 1.6, y: 48 / 1.6)
    /// Ten seconds across the screen, two waiting off it.
    public static let swimFrames = 600
    public static let waitFrames = 120
    /// The spin: its eight frames at fifteen a second.
    public static let spinFrames = 32
    /// It sways this far up and down, this many times a crossing, kept between its lowest and highest.
    public static let swayHeight = 30.0
    public static let swaysPerCrossing = 1.25
    /// Its bottom no lower than the twelfth row from the top (row 7 from the floor's), and no
    /// higher than its three rows of height fit under the stage's top.
    public static let lowest = 7 * Stage.tileSize
    static func highest(_ stage: Stage) -> Double { stage.height - 3 * Stage.tileSize }

    /// The way across: from wholly off one side to wholly off the other.
    static func crossing(_ stage: Stage) -> Double { stage.width + size.x }

    /// A height off the count, the same on both phones, anywhere it can be.
    static func height(_ count: Int, on stage: Stage) -> Double {
        let low = lowest, high = highest(stage)
        let pick = Double(ElementsRules.pick(count + 2_000_000) % 1000) / 999
        return low + (high - low) * pick
    }
}
