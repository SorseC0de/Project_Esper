import EsperSim
import Foundation
import QuartzCore
import ImageIO
import UniformTypeIdentifiers

/// The change into FloState played on its own and saved frame by frame, for an animated
/// picture of it: launched with `-captureTransform`, or with `debug.captureTransform` set in
/// the defaults (debug builds only; the setting's cleared once it's done), the first side alone
/// on the Tutorial's floor, in gold with the third skin tone, no ball, no hoops, nothing of the
/// stage drawn; standing a moment, the change, then standing in FloState. Each sim frame's
/// picture is the game's own, glow and cubes and all, drawn twice, over black and then over
/// white with the clock held: where the two agree it's opaque, and where they don't it's light,
/// as opaque as it's bright. Saved as a PNG named by its frame to `folder`, and a `done` file
/// once it's over.
final class TransformCapture {
    static var requested: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-captureTransform") || UserDefaults.standard.bool(forKey: defaultsKey)
        #else
        false
        #endif
    }
    static let defaultsKey = "debug.captureTransform"
    static let energy = EnergyColour.gold
    /// The third skin tone.
    static let skinTone = 2
    /// Sim frames standing before the change is pressed, and in FloState after it's done.
    static let standingFrames = 60
    static let floStateFrames = 150
    /// Out of the way: the other side and the ball.
    static let parked = Vec2(x: -1000, y: 300)

    /// Its own clock, a sim frame on for each frame drawn over black (held for the one over
    /// white), so everything drawn by time (the effects' actions, the strings) keeps step with
    /// the sim however slowly the frames come.
    private(set) var clock = CACurrentMediaTime()
    func tick() -> CFTimeInterval {
        if !holding { clock += 1.0 / 60 }
        return clock
    }

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TransformCapture", isDirectory: true)
    /// Sim frames since it started, once the bodies' frames are made in its colours (`armed`).
    var armed = false
    private(set) var frames = 0
    /// The frame stepped and due to be drawn over black; then, drawn, the frame due over white,
    /// the sim held for it.
    private var blackDue: Int?
    private(set) var whiteDue: Int?
    /// Drawn over white and being read back.
    private var whiteReading: Int?
    private var overBlack: [Int: [UInt8]] = [:]
    private var overWhite: [Int: [UInt8]] = [:]
    private let writer = DispatchQueue(label: "TransformCapture")

    init() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        print("[CAPTURE] frames to \(folder.path)")
    }

    var pressFrame: Int { TransformCapture.standingFrames }
    var lastFrame: Int { pressFrame + TransformRules.frames + TransformCapture.floStateFrames }
    /// Whether the sim's held: a frame's still to be drawn over white.
    var holding: Bool { whiteDue != nil || blackDue != nil || whiteReading != nil }
    /// The background the frame now drawn goes over.
    var drawsOverWhite: Bool { whiteDue != nil }

    /// A sim frame's input for the first side, the match kept to the shot first: the other side,
    /// the ball and every hoop parked, the FLO full for the change.
    func step(match: Match, mutate: ((inout Match) -> Void) -> Void) -> PlayerInput {
        let press = armed && frames == pressFrame
        mutate { match in
            match.countdown = 0
            if match.players.indices.contains(1) {
                match.players[1].position = TransformCapture.parked
                match.players[1].velocity = .zero
                match.players[1].frozen = 2
            }
            match.players[0].hasBall = false
            match.ball.respawn(at: TransformCapture.parked)
            match.ball.frozen = 2
            for room in 0..<TutorialRules.rooms { match.layTutorialRoom(room, as: .empty) }
            if press {
                match.players[0].flo = FloRules.full
                match.players[0].floStateLockout = 0
            }
        }
        guard armed, frames < lastFrame else { return .idle }
        frames += 1
        blackDue = frames
        return press ? PlayerInput(shoot: true, throwBall: true) : .idle
    }

    /// The frame now being drawn, if it's to be kept, and over which background.
    func take() -> (index: Int, overWhite: Bool)? {
        if let index = whiteDue {
            whiteDue = nil
            whiteReading = index
            return (index, true)
        }
        guard let index = blackDue else { return nil }
        blackDue = nil
        whiteDue = index
        return (index, false)
    }

    /// A drawn frame's composite read back (BGRA); with both of a frame's in, saved, and the sim
    /// let go on.
    func save(_ index: Int, overWhite white: Bool, composite: [UInt8], width: Int, height: Int) {
        if white {
            overWhite[index] = composite
            if whiteReading == index { whiteReading = nil }
        } else {
            overBlack[index] = composite
        }
        guard let black = overBlack[index], let lit = overWhite[index] else { return }
        overBlack[index] = nil
        overWhite[index] = nil
        let folder = folder
        let last = index >= lastFrame
        writer.async {
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            for pixel in 0..<(width * height) {
                let at = pixel * 4
                let b = Int(black[at]), g = Int(black[at + 1]), r = Int(black[at + 2])
                // How far white showed through, the most of any channel; and the light's brightness.
                let through = max(Int(lit[at + 2]) - r, Int(lit[at + 1]) - g, Int(lit[at]) - b, 0)
                let alpha = max(255 - through, r, g, b)
                guard alpha > 0 else { continue }
                let share = 255 / Double(alpha)
                rgba[at] = UInt8(min(Double(r) * share, 255).rounded())
                rgba[at + 1] = UInt8(min(Double(g) * share, 255).rounded())
                rgba[at + 2] = UInt8(min(Double(b) * share, 255).rounded())
                rgba[at + 3] = UInt8(alpha)
            }
            guard let provider = CGDataProvider(data: Data(rgba) as CFData),
                  let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
            let url = folder.appendingPathComponent(String(format: "frame_%04d.png", index))
            if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                CGImageDestinationFinalize(destination)
            }
            if last {
                DispatchQueue.main.async { UserDefaults.standard.removeObject(forKey: TransformCapture.defaultsKey) }
                try? "done".write(to: folder.appendingPathComponent("done"), atomically: true, encoding: .utf8)
                print("[CAPTURE] done")
            }
        }
    }
}
