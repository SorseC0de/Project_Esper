import CoreGraphics
import Foundation
import ImageIO

let atlasDir = CommandLine.arguments[1]
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "maps"
func load(_ name: String) -> CGImage? {
    let dir = "\(atlasDir)/\(name).imageset"
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir), let png = files.first(where: { $0.hasSuffix(".png") }),
          let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(dir)/\(png)") as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}
// As SpriteLibrary has them.
let plainHood = load("player_hoodheads_v2_0")!
let turnedHoods = Dictionary(uniqueKeysWithValues: (1..<HoodView.count).compactMap { v in load("player_hoodheads_v2_\(v)").map { (v, $0) } })
let floHoods = Dictionary(uniqueKeysWithValues: (0..<HoodView.count).compactMap { v in load("player_hoodheads_flostate_\(v)").map { (v, $0) } })
func mirrored(_ image: CGImage) -> CGImage? {
    guard let (context, _) = PlayerRecolour.canvas(width: image.width, height: image.height) else { return nil }
    context.translateBy(x: CGFloat(image.width), y: 0); context.scaleBy(x: -1, y: 1)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()
}
func hoodShape(view: Int, flipped: Bool, energy: Bool) -> CGImage {
    let plain = view == 0 ? plainHood : turnedHoods[view] ?? plainHood
    let shape = energy ? floHoods[turnedHoods[view] == nil ? 0 : view] ?? plain : plain
    return flipped ? mirrored(shape) ?? shape : shape
}
let hoodDrawnForHead: CGPoint? = {
    let image = load("player_idle_2")!
    let width = image.width, height = image.height
    let (context, pixels) = PlayerRecolour.canvas(width: width, height: height)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var sum = CGPoint.zero, heads = 0
    for pixel in 0..<(width * height) where pixels[pixel * 4 + 3] == 255 {
        let index = pixel * 4
        guard BodyPart.owning(RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])) == .head else { continue }
        sum.x += CGFloat(pixel % width) + 0.5; sum.y += CGFloat(pixel / width) + 0.5; heads += 1
    }
    return heads > 0 ? CGPoint(x: sum.x / CGFloat(heads), y: sum.y / CGFloat(heads)) : nil
}()
let armColoursSwapped: [Animation: ClosedRange<Int>] = [.throwForward: 4...7]
let armSkinSwapped: [Animation: Set<Int>] = [.spinBall: [2], .spinDunk: [1]]
let handsLit: [Animation: Set<Int>] = [.spinBall: [1], .spinDunk: [0]]
func row(_ f: AnimationFrame) -> Int {
    if armColoursSwapped[f.animation]?.contains(f.frame) == true { return 1 }
    if armSkinSwapped[f.animation]?.contains(f.frame) == true { return 2 }
    if handsLit[f.animation]?.contains(f.frame) == true { return 3 }
    return 0
}

let looks: [(String, Look, PlayerLineStyle)] = {
// Looks: both players, energy forms, turned, ice, and dressings that differ.
var looks: [(String, Look, PlayerLineStyle)] = []
for (i, base) in Look.byPlayer.enumerated() {
    looks.append(("p\(i)", base, .normal)); looks.append(("p\(i)T", base.transformed, .normal)); looks.append(("p\(i)R", base.turnedRound, .normal))
}
looks.append(("ice", Look.ice, .normal))
var sleeves = Dressing(); sleeves.frontSleeve = true; sleeves.backBoot = false; sleeves.skinTone = 3
for (i, glow) in [EnergyColour.allCases.first!, EnergyColour.allCases.last!].enumerated() {
    let look = Look.team(glow.glow, body: glow.glow, dressing: sleeves)
    looks.append(("sl\(i)", look, .normal)); looks.append(("sl\(i)T", look.transformed, .normal)); looks.append(("sl\(i)R", look.turnedRound, .bold))
}
var skin2 = Dressing(); skin2.skinTone = 4
looks.append(("skin4", Look.team(Look.byPlayer[0].glow, body: Look.byPlayer[0].glow, dressing: skin2), .normal))
looks.append(("p0semi", Look.byPlayer[0], .semibold))

    return looks
}()
let frames: [(AnimationFrame, CGImage)] = {
var frames: [(AnimationFrame, CGImage)] = []
for animation in Animation.allCases {
    for index in 0..<animation.frameCount {
        guard let image = load("\(animation.rawValue)_\(index)") else { print("missing \(animation.rawValue)_\(index)"); continue }
        frames.append((AnimationFrame(animation, index), image))
    }
}
    return frames
}()

