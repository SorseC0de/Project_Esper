func runMaps() {
var failures: [String: Int] = [:]
var maps: [String: [UInt8]] = [:]   // shape|frame|variant -> bytes
var mapsNoSkin: [String: (String, [UInt8])] = [:]
var mismatches = 0, mismatchesNoSkin = 0, made = 0
var presentCounts: [PlayerMapShaders.Layer: Int] = [:]
for (name, look, style) in looks {
    let palette = PlayerMap.palette(look)
    let key = PlayerMap.ShapeKey(look, lineStyle: style)
    let noSkin = key
    for (frame, image) in frames {
        for holds in frame.animation.holdsBall ? [true, false] : [false] {
            let r = row(frame)
            let layers = PlayerRecolour.recolour(image: image, look: PlayerRecolour.adjusted(look, row: r), holdsBall: holds, detach: true,
                                                 hoodShape: hoodShape(view: HoodView.of(frame), flipped: HoodView.isFlipped(frame), energy: look.energyForm),
                                                 bareLine: !look.energyForm, lineStyle: style, hoodDrawnForHead: hoodDrawnForHead, ballMinPixels: 12,
                                                 map: (r, palette, false))
            guard let map = layers.map else { failures["\(name) \(frame.animation.rawValue)_\(frame.frame)", default: 0] += 1; continue }
            made += 1
            for layer in map.present { presentCounts[layer, default: 0] += 1 }
            let id = "\(key.name)|\(frame.animation.rawValue)_\(frame.frame)|\(holds)"
            if let other = maps[id] { if other != map.bytes { mismatches += 1; if mismatches < 5 { print("MISMATCH \(id) \(name)") } } } else { maps[id] = map.bytes }
            let id2 = "\(noSkin.name)|\(frame.animation.rawValue)_\(frame.frame)|\(holds)"
            if let other = mapsNoSkin[id2] { if other.1 != map.bytes { mismatchesNoSkin += 1; if mismatchesNoSkin < 5 { print("NOSKIN MISMATCH \(id2) \(name) vs \(other.0)") } } } else { mapsNoSkin[id2] = (name, map.bytes) }
        }
    }
    print("look \(name) shape \(key.name) done")
}
print("made \(made), failed \(failures.values.reduce(0, +)), shared-shape mismatches \(mismatches), skin-free mismatches \(mismatchesNoSkin)")
print("distinct maps \(maps.count), distinct without skin \(mapsNoSkin.count)")
for (k, v) in failures.sorted(by: { $0.key < $1.key }).prefix(40) { print("FAIL \(k) x\(v)") }
print(presentCounts.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))

}
