import Foundation

/// Hoopfish Hideaway's jellyfish: now and then, rarer than the background's shark, one drifts
/// across the stage from one side to the other, slowly, at a height off its own dice; its bell's
/// top a one-way spring as a rim's top is: a body coming down on it is sent back up (`RimRules`),
/// and a ball comes off it. `jellyfish.png`, four 32 by 32 frames, one of its pixels an art pixel.
public enum JellyfishRules {
    /// Frames between one going and the next coming, and its pace across, units a frame (12 art
    /// pixels a second).
    public static let gapFrames = 3000...6000
    public static let speed = 12.0 / 1.6 / 60
    /// The bell's top: how far over the sprite's middle, and how far either way of it, in units.
    public static let topAbove = 10.0 / 1.6
    public static let halfWidth = 12.0 / 1.6
    /// The sprite's half width, for where it starts and finishes, off the stage's edges.
    public static let artHalfWidth = 16.0 / 1.6
    /// Its middle's height: between these rows, a tile apart.
    public static let rows = 4...13
}

public struct Jellyfish: Equatable {
    public var position: Vec2
    /// 1 right, -1 left.
    public var heading: Double
}

/// A one-way spring along a level top: something coming down onto it from above is sent back up.
public struct SpringTop: Equatable {
    public var left: Double
    public var right: Double
    public var y: Double
}

extension Match {
    /// The jellyfish a frame on: one coming in when its clock's run out, drifting across, gone off
    /// the far side; its bell's top laid as the stage's spring.
    mutating func stepJellyfish() {
        guard hoopfish != nil else { return }
        if var jelly = jellyfish {
            jelly.position.x += jelly.heading * JellyfishRules.speed
            let gone = jelly.heading > 0 ? jelly.position.x - JellyfishRules.artHalfWidth > stage.width
                : jelly.position.x + JellyfishRules.artHalfWidth < 0
            jellyfish = gone ? nil : jelly
            if gone { jellyfishIn = JellyfishRules.gapFrames.lowerBound + jellyDice.roll(JellyfishRules.gapFrames.count) }
        } else if jellyfishIn > 0 {
            jellyfishIn -= 1
        } else {
            let heading: Double = jellyDice.roll(2) == 0 ? 1 : -1
            let row = JellyfishRules.rows.lowerBound + jellyDice.roll(JellyfishRules.rows.count)
            let x = heading > 0 ? -JellyfishRules.artHalfWidth : stage.width + JellyfishRules.artHalfWidth
            jellyfish = Jellyfish(position: Vec2(x: x, y: (Double(row) + 0.5) * Stage.tileSize), heading: heading)
        }
        stage.springs = jellyfish.map { jelly in
            [SpringTop(left: jelly.position.x - JellyfishRules.halfWidth, right: jelly.position.x + JellyfishRules.halfWidth,
                       y: jelly.position.y + JellyfishRules.topAbove)]
        } ?? []
    }
}
