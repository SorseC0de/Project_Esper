/// Wetshot Wake's Hooperfish: it starts where the map puts it with the ball on its antenna and
/// swims off the side it faces; then, two seconds off screen, it comes back from that side,
/// turned round, at a height off the count, swimming five seconds across to a height off the
/// count on the far side, swaying up and down as it goes, over and over. What's on its antenna
/// changes only off screen: after the first crossing it's always the stage's rim.
public struct Hooperfish: Equatable {
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

    /// Where the rim, or the ball, rides on its antenna: whole art pixels from its bottom left.
    public var antenna: Vec2 {
        let across = Double(facesRight ? HooperfishRules.pixelWidth - WetshotRules.rimPixelsAcross : WetshotRules.rimPixelsAcross)
        return position + Vec2(x: across / 1.6, y: Double(WetshotRules.rimPixelsUp) / 1.6)
    }

    /// Off screen, between crossings.
    public var away: Bool { age >= swimFrames }

    static func starting(at cell: Vec2, on stage: Stage) -> Hooperfish {
        let offLeft = -HooperfishRules.size.x
        let distance = cell.x - offLeft
        let frames = max(Int((distance / HooperfishRules.crossing(stage) * Double(HooperfishRules.swimFrames)).rounded()), 1)
        return Hooperfish(position: cell, carrying: .ball, from: cell, to: Vec2(x: offLeft, y: HooperfishRules.height(1, on: stage)),
                          swimFrames: frames)
    }

    /// A frame on: swimming, swaying, then waiting off screen, then the next crossing back.
    mutating func step(on stage: Stage) {
        age += 1
        if age < swimFrames {
            let share = Double(age) / Double(swimFrames)
            let sway = HooperfishRules.swayHeight * Trig.sin(share * HooperfishRules.swaysPerCrossing * 2 * Double.pi)
            position = Vec2(x: from.x + (to.x - from.x) * share, y: from.y + (to.y - from.y) * share + sway)
            return
        }
        position = to
        guard age >= swimFrames + HooperfishRules.waitFrames else { return }
        crossing += 1
        age = 0
        facesRight.toggle()
        carrying = .hoop
        let offLeft = -HooperfishRules.size.x, offRight = stage.width
        let start = HooperfishRules.height(crossing * 2, on: stage), end = HooperfishRules.height(crossing * 2 + 1, on: stage)
        from = Vec2(x: facesRight ? offLeft : offRight, y: start)
        to = Vec2(x: facesRight ? offRight : offLeft, y: end)
        position = from
        swimFrames = HooperfishRules.swimFrames
    }
}

public enum HooperfishRules {
    /// Its picture, 96 by 48 art pixels, in units.
    public static let pixelWidth = 96
    public static let size = Vec2(x: 96 / 1.6, y: 48 / 1.6)
    /// Five seconds across the screen, two waiting off it.
    public static let swimFrames = 300
    public static let waitFrames = 120
    /// It sways this far up and down, this many times a crossing.
    public static let swayHeight = 14.0
    public static let swaysPerCrossing = 2.5
    /// Its heights: its bottom no lower than this over the floor, its top no nearer the stage's top.
    public static let lowest = 20.0
    public static let topClearance = 20.0

    /// The way across: from wholly off one side to wholly off the other.
    static func crossing(_ stage: Stage) -> Double { stage.width + size.x }

    /// A height off the count, the same on both phones, inside the swaying room.
    static func height(_ count: Int, on stage: Stage) -> Double {
        let low = lowest + swayHeight, high = stage.height - size.y - topClearance - swayHeight
        let pick = Double(ElementsRules.pick(count + 2_000_000) % 1000) / 999
        return low + (high - low) * pick
    }
}
