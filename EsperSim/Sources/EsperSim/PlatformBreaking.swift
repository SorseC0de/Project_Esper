import Foundation

/// Platform Protein Shake's slabs and walls broken. A blade, a throw, and whatever a power fires
/// break one, and it takes the hit: the blade is spent and the shot stops there. A shot ball
/// bounces off; a burning one breaks it. Titan Tea landing on one breaks it, and so does
/// Pulsepistol Punch's repulsion snipe. Its maker's own hits leave it standing.
extension Match {
    mutating func shatter(_ platform: Platform) {
        events.append(.platformShattered(player: platform.owner, box: platform.box))
        platforms.removeAll { $0.id == platform.id }
        refreshExtras()
    }

    /// Breaks every slab and wall `box` overlaps, but `striker`'s own; true when one broke.
    @discardableResult
    mutating func shatterPlatforms(touching box: Box, by striker: Int?) -> Bool {
        let broken = platforms.filter { $0.box.overlaps(box) && $0.owner != striker }
        for platform in broken { shatter(platform) }
        return !broken.isEmpty
    }

    /// Breaks the first slab or wall along a beam, which stops there: how far the beam gets.
    mutating func platformStopsTheBeam(_ beam: Beam) -> Double {
        guard !platforms.isEmpty else { return beam.reach }
        var travelled = 0.0
        while travelled <= beam.reach {
            let at = beam.origin + beam.direction * travelled
            if let hit = platforms.first(where: { $0.owner != beam.owner && $0.box.distance(to: at) <= ZRules.halfThickness }) {
                shatter(hit)
                return travelled
            }
            travelled += 2
        }
        return beam.reach
    }

    /// Whether a point is under the stage's lava, which a phantom moves through as water.
    func underLava(_ point: Vec2) -> Bool {
        stage.features.lavaSurface.map { point.y < $0 } ?? false
    }

    /// Titan Tea landing on a slab breaks it, and falls on through: true when it did.
    mutating func titanBreaksItsLanding(_ index: Int) -> Bool {
        let feet = players[index].body
        let under = Box(min: Vec2(x: feet.min.x, y: feet.min.y - 1), max: Vec2(x: feet.max.x, y: feet.min.y))
        guard shatterPlatforms(touching: under, by: nil) else { return false }
        players[index].fallThroughBrokenPlatform()
        return true
    }
}
