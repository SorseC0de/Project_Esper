import Foundation

/// Melee units. +x is screen right, +y is up, the same way SpriteKit points.
public struct Vec2: Equatable, Hashable {
    public var x: Double
    public var y: Double

    public static let zero = Vec2(x: 0, y: 0)

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var length: Double { (x * x + y * y).squareRoot() }
    public var lengthSquared: Double { x * x + y * y }
    /// Radians, counter-clockwise from +x.
    public var angle: Double { Trig.atan2(y, x) }

    public var normalized: Vec2 {
        let l = length
        return l > 0 ? self / l : .zero
    }

    public func distance(to o: Vec2) -> Double { (self - o).length }

    public func clamped(to limit: Double) -> Vec2 {
        let l = length
        return l > limit ? self * (limit / l) : self
    }

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x + b.x, y: a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x - b.x, y: a.y - b.y) }
    public static prefix func - (a: Vec2) -> Vec2 { Vec2(x: -a.x, y: -a.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(x: a.x * s, y: a.y * s) }
    public static func / (a: Vec2, s: Double) -> Vec2 { Vec2(x: a.x / s, y: a.y / s) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }
    public static func -= (a: inout Vec2, b: Vec2) { a = a - b }
}

/// Moves `value` toward `target` by at most `step`.
public func approach(_ value: Double, _ target: Double, _ step: Double) -> Double {
    value < target ? min(value + step, target) : max(value - step, target)
}

public func degrees(_ d: Double) -> Double { d * .pi / 180 }
