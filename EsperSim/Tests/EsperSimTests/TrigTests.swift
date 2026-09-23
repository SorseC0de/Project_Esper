import Foundation
import XCTest
@testable import EsperSim

final class TrigTests: XCTestCase {
    private var sweep: [Double] {
        var angles: [Double] = [0, -0.0, 1e-9, -1e-9, 0.5, -0.5, 1, -1]
        for step in -400...400 {
            angles.append(Double(step) * 0.0173)
            angles.append(Double(step) * Double.pi / 8)
        }
        angles += [Double.pi, -Double.pi, Double.pi / 2, -Double.pi / 2, 2 * Double.pi, 100, -100, 12345.678]
        return angles
    }

    func testSineAndCosineMatchTheSystemsToTheLastPlaces() {
        for angle in sweep {
            XCTAssertEqual(Trig.sin(angle), Foundation.sin(angle), accuracy: 1e-12 * max(1, abs(angle)), "sin \(angle)")
            XCTAssertEqual(Trig.cos(angle), Foundation.cos(angle), accuracy: 1e-12 * max(1, abs(angle)), "cos \(angle)")
        }
        XCTAssertEqual(Trig.sin(0), 0)
        XCTAssertEqual(Trig.cos(0), 1)
        XCTAssertEqual(Trig.sin(Trig.halfPi), 1, accuracy: 1e-15)
    }

    func testArctangentMatchesTheSystemsInEveryQuadrant() {
        var points: [(Double, Double)] = []
        for y in stride(from: -5.0, through: 5.0, by: 0.37) {
            for x in stride(from: -5.0, through: 5.0, by: 0.41) {
                points.append((y, x))
            }
        }
        points += [(1, 0), (-1, 0), (0, 1), (0, -1), (0, 0), (0, -0.0), (-0.0, -0.0), (-0.0, 1), (1e-300, 1), (1, 1e-300), (3, 4), (-3, 4), (3, -4), (-3, -4), (1e6, 1), (1, 1e6)]
        for (y, x) in points {
            let mine = Trig.atan2(y, x), theirs = Foundation.atan2(y, x)
            XCTAssertEqual(mine, theirs, accuracy: 1e-14, "atan2(\(y), \(x))")
            XCTAssertEqual(mine.sign, theirs.sign, "atan2(\(y), \(x)) sign")
        }
        for t in stride(from: -20.0, through: 20.0, by: 0.173) {
            XCTAssertEqual(Trig.atan(t), Foundation.atan(t), accuracy: 1e-14, "atan \(t)")
        }
    }

    func testPowerOfTen() {
        XCTAssertEqual(Trig.powerOfTen(0), 1)
        XCTAssertEqual(Trig.powerOfTen(3), 1000)
        XCTAssertEqual(Trig.powerOfTen(-2), 0.01, accuracy: 1e-18)
    }

    /// Same bits every time, on its own arithmetic: two sweeps in different orders agree exactly.
    func testTheSameAngleAlwaysGivesTheSameBits() {
        let forward = sweep.map { Trig.sin($0) + Trig.cos($0) * 3 + Trig.atan2($0, 1.5) }
        let backward = sweep.reversed().map { Trig.sin($0) + Trig.cos($0) * 3 + Trig.atan2($0, 1.5) }.reversed()
        XCTAssertEqual(forward, Array(backward))
    }
}
