/// Trigonometry in plain arithmetic, so both phones get the same bits whatever iOS each
/// runs: the system's sin, cos and atan2 live in libm, which can round differently from
/// one version to the next, while adding, multiplying, dividing and the square root are
/// IEEE, the same everywhere. Nothing in the sim calls the system's. Accurate to about a
/// unit in the last place over the angles the game uses.
public enum Trig {
    public static let pi = Double.pi
    public static let halfPi = Double.pi / 2
    /// π/2 in two parts, the double nearest it and the rest, so the reduction to a quarter
    /// turn loses nothing.
    private static let halfPiHigh = 1.5707963267948966
    private static let halfPiLow = 6.123233995736766e-17

    /// The angle brought within an eighth of a turn of zero, and how many quarter turns
    /// were taken off.
    private static func reduce(_ x: Double) -> (r: Double, quarters: Int) {
        let k = (x / halfPiHigh).rounded()
        let r = (x - k * halfPiHigh) - k * halfPiLow
        return (r, Int(k) & 3)
    }

    /// Taylor about zero, good to the last place within an eighth of a turn.
    private static func sinSmall(_ r: Double) -> Double {
        let r2 = r * r
        var series = 1.0 / 1307674368000
        series = series * r2 - 1.0 / 6227020800
        series = series * r2 + 1.0 / 39916800
        series = series * r2 - 1.0 / 362880
        series = series * r2 + 1.0 / 5040
        series = series * r2 - 1.0 / 120
        series = series * r2 + 1.0 / 6
        series = series * r2 - 1
        return -r * series
    }

    private static func cosSmall(_ r: Double) -> Double {
        let r2 = r * r
        var series = 1.0 / 20922789888000
        series = series * r2 - 1.0 / 87178291200
        series = series * r2 + 1.0 / 479001600
        series = series * r2 - 1.0 / 3628800
        series = series * r2 + 1.0 / 40320
        series = series * r2 - 1.0 / 720
        series = series * r2 + 1.0 / 24
        series = series * r2 - 1.0 / 2
        return series * r2 + 1
    }

    public static func sin(_ x: Double) -> Double {
        let (r, quarters) = reduce(x)
        switch quarters {
        case 0: return sinSmall(r)
        case 1: return cosSmall(r)
        case 2: return -sinSmall(r)
        default: return -cosSmall(r)
        }
    }

    public static func cos(_ x: Double) -> Double {
        let (r, quarters) = reduce(x)
        switch quarters {
        case 0: return cosSmall(r)
        case 1: return -sinSmall(r)
        case 2: return -cosSmall(r)
        default: return sinSmall(r)
        }
    }

    /// The angle whose tangent is `t`, in (-π/2, π/2).
    public static func atan(_ t: Double) -> Double {
        var u = abs(t)
        let over = u > 1
        if over { u = 1 / u }
        // Halve the angle twice, so the series is short: atan(u) = 2 atan(u / (1 + √(1 + u²))).
        u = u / (1 + (1 + u * u).squareRoot())
        u = u / (1 + (1 + u * u).squareRoot())
        let u2 = u * u
        var series = 0.0
        for n in stride(from: 23, through: 1, by: -2) {
            series = series * u2 + (n % 4 == 1 ? 1.0 : -1.0) / Double(n)
        }
        var angle = 4 * u * series
        if over { angle = halfPi - angle }
        return t < 0 ? -angle : angle
    }

    /// The angle of the point (x, y) from +x, counter-clockwise, in (-π, π], as the
    /// system's atan2 has it, signed zeros included.
    public static func atan2(_ y: Double, _ x: Double) -> Double {
        if x == 0 {
            if y > 0 { return halfPi }
            if y < 0 { return -halfPi }
            let flat = x.sign == .minus ? pi : 0.0
            return y.sign == .minus ? -flat : flat
        }
        let ay = abs(y), ax = abs(x)
        let base = ay > ax ? halfPi - atan(ax / ay) : atan(ay / ax)
        let angle = x < 0 ? pi - base : base
        return y.sign == .minus ? -angle : angle
    }

    /// Ten to a whole power, by multiplying, for the sim's rounding to places.
    public static func powerOfTen(_ places: Int) -> Double {
        var scale = 1.0
        if places >= 0 {
            for _ in 0..<places { scale *= 10 }
        } else {
            for _ in 0..<(-places) { scale /= 10 }
        }
        return scale
    }
}
