import SwiftUI

// Ported from Variaball (CardCourt's `ModeCardView`), itself from Project Stars: the Z card.
// Its pass-through kept whole, the movement being the part worth having; the hold-for-Start,
// emblems, affixes and wormhole left behind, since nothing here calls for them. Esper's words
// are FLO lettering, and each bar's streaks are its own colour.

/// Two slanted bars that come in from opposite sides, settle a little past centre as one Z,
/// hold while the words across the seam are read, and carry on out the way they were going:
/// the upper one left to right, the lower one right to left. The words spring up as the bars
/// land. CardCourt's arrive, hold and leave, the hold timed rather than waiting on a press.
struct ZCardView<Words: View>: View {
    /// What's called out across the seam.
    let words: Words
    /// Each bar's streaks: the world going by inside it, in one colour a bar.
    var upperStreaks: Color
    var lowerStreaks: Color
    /// Called once the bars are gone. The card removes itself.
    let onFinished: () -> Void
    /// Seconds before it comes in, held with the words up, and taken going on out.
    var delay: Double
    var hold: Double
    var departure: Double

    init(upperStreaks: Color, lowerStreaks: Color, delay: Double = 0, hold: Double = ZCardStyle.hold, departure: Double = ZCardStyle.departure,
         onFinished: @escaping () -> Void, @ViewBuilder words: () -> Words) {
        self.upperStreaks = upperStreaks
        self.lowerStreaks = lowerStreaks
        self.delay = delay
        self.hold = hold
        self.departure = departure
        self.onFinished = onFinished
        self.words = words()
    }

    @State private var stage: Stage = .offstage
    /// Whether the words are showing: the gathered moment's alone.
    @State private var said: Double = 0

    private enum Stage { case offstage, gathered, parted }
    private typealias Slat = ZCardSlat

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let bar = ZCardStyle.bar(across: geometry.size)
            ZStack {
                ForEach([Slat.upper, Slat.lower], id: \.self) { slat in
                    // The bar, and the streaks inside it seen through it, its own colour.
                    ZStack {
                        self.slat(slat, bar: bar, width: width)
                        SideStreaks(ink: slat == .upper ? upperStreaks : lowerStreaks, thickness: ZCardStyle.streakThickness * bar.height)
                            .frame(width: width, height: bar.height)
                            .mask { self.slat(slat, bar: bar, width: width) }
                    }
                    .frame(width: width, height: bar.height)
                    .offset(y: slat == .upper ? -bar.height / 2 : bar.height / 2)
                }
                words
                    .offset(y: -bar.height / 2 + ZCardStyle.wordsDrop * bar.height)
                    .scaleEffect(said)
                    .opacity(said)
                    .animation(ZCardStyle.pop, value: said)
            }
            .frame(width: width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
        .task { await play() }
    }

    /// One bar at its place along its line of travel, fading out at its outer end.
    private func slat(_ slat: Slat, bar: ZCardStyle.Bar, width: CGFloat) -> some View {
        Parallelogram(lean: ZCardStyle.lean)
            .fill(ZCardStyle.taper(towards: slat))
            .frame(width: bar.width, height: bar.height)
            .offset(x: travel(slat, width: width, bar: bar)
                    + slat.outward * (ZCardStyle.length + ZCardStyle.spread) * bar.height / 2)
    }

    /// How far this bar is from centre: waiting off one side, resting on its own side of the
    /// card a little past centre, or gone off the other side.
    private func travel(_ slat: Slat, width: CGFloat, bar: ZCardStyle.Bar) -> CGFloat {
        let away = width / 2 + bar.width + ZCardStyle.spread * bar.height
        switch stage {
        case .offstage: return -slat.heading * away
        case .gathered: return slat.outward * ZCardStyle.overshoot * bar.height
        case .parted: return slat.heading * away
        }
    }

    /// In, the words springing up as the bars land; held; the words gone and the bars on out.
    private func play() async {
        if delay > 0 { await sleep(delay) }
        withAnimation(.easeOut(duration: ZCardStyle.arrival)) { stage = .gathered }
        said = 1
        await sleep(ZCardStyle.arrival + hold)
        said = 0
        withAnimation(.easeIn(duration: departure)) { stage = .parted }
        await sleep(departure)
        onFinished()
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

/// BALL OUT's card's timing, on the debug strip's BALL OUT sliders, kept between launches: seconds
/// after the call before it comes in, held with the words up, and taken going on out.
enum BallOutTiming {
    private static func stored(_ key: String, _ fallback: Double) -> Double { UserDefaults.standard.object(forKey: key) as? Double ?? fallback }
    static var delay: Double {
        get { stored("ballOut.delay", 0) }
        set { UserDefaults.standard.set(newValue, forKey: "ballOut.delay") }
    }
    static var hold: Double {
        get { stored("ballOut.hold.3", 0.4) }
        set { UserDefaults.standard.set(newValue, forKey: "ballOut.hold.3") }
    }
    static var departure: Double {
        get { stored("ballOut.departure.2", 0.1) }
        set { UserDefaults.standard.set(newValue, forKey: "ballOut.departure.2") }
    }
}

/// Which of the two bars, which way it travels, and which side of the card it rests on.
enum ZCardSlat: Hashable {
    case upper, lower
    var heading: CGFloat { self == .upper ? 1 : -1 }
    var outward: CGFloat { self == .upper ? -1 : 1 }
}

/// The card's proportions and timing, CardCourt's but for its size: there a share of the
/// screen's width, drawn for a tall screen; here of its height, the game being wide, or the
/// pair would cover most of it.
enum ZCardStyle {
    /// Both bars' face: black, just short of opaque.
    static let faceOpacity: Double = 0.90
    static let face = Color.black.opacity(faceOpacity)
    /// The top edge's shift, as a share of the bar's height.
    static let lean: CGFloat = 0.97
    /// A bar's thickness as a share of the screen's height, and how much longer than thick it is.
    static let barHeight: CGFloat = 0.16
    static let barAspect: CGFloat = 5.18
    static let length: CGFloat = 2.22
    static let spread: CGFloat = -0.20
    /// The clear run at each bar's outer end, and where it's whole, in from that end.
    static let fadeFrom: CGFloat = 0.30
    static let fadeTo: CGFloat = 0.50
    /// The words' place, down from the upper bar's middle: very nearly on the seam.
    static let wordsDrop: CGFloat = 0.45
    /// The words' cap height against a bar's.
    static let wordsHeight: CGFloat = 0.42
    /// The streaks' thickness against a bar's.
    static let streakThickness: CGFloat = 0.06
    /// How far each bar settles past centre, into the other's side: what makes it a Z.
    static let overshoot: CGFloat = 0.24
    /// In, held for the words, and out; the words' spring, a beat after the bars set off.
    static let arrival: Double = 0.30
    static let hold: Double = 1.2
    static let departure: Double = 0.30
    static let textDelay: Double = 0.15
    static let textResponse: Double = 0.35
    static let textBounce: Double = 0.50
    static var pop: Animation { .spring(response: textResponse, dampingFraction: textBounce).delay(textDelay) }

    struct Bar {
        let width: CGFloat
        let height: CGFloat
    }

    static func bar(across screen: CGSize) -> Bar {
        let height = barHeight * screen.height
        return Bar(width: height * (barAspect + length), height: height)
    }

    /// One bar's fill: the face at nothing at its outer end, whole toward its inner one.
    static func taper(towards slat: ZCardSlat) -> LinearGradient {
        let from = min(fadeFrom, fadeTo), to = max(fadeFrom, fadeTo)
        let stops = [
            Gradient.Stop(color: face.opacity(0), location: 0),
            Gradient.Stop(color: face.opacity(0), location: from),
            Gradient.Stop(color: face, location: to),
            Gradient.Stop(color: face, location: 1),
        ]
        return LinearGradient(gradient: Gradient(stops: stops),
                              startPoint: slat == .upper ? .leading : .trailing,
                              endPoint: slat == .upper ? .trailing : .leading)
    }
}

/// Seen from the side: streaks running past inside the thing they're behind, all one way, in
/// one colour, each with a wider, fainter pass under it that blooms. CardCourt's `SideStreaks`.
struct SideStreaks: View {
    var ink: Color
    var thickness: CGFloat = 3
    var intensity: Double = 0.72

    static let count = 40
    static let bloom: CGFloat = 2.6
    static let bloomGain: Double = 0.35
    static let lengthShare: CGFloat = 0.18
    static let speedShare: CGFloat = 3.4
    static let faintest: Double = 0.15
    static let shortest: Double = 0.18
    static let slowest: Double = 0.35

    /// A fixed number in 0..<1 for this streak and this question: scattered, the same every time.
    static func scatter(_ index: Int, _ question: Int) -> Double {
        let n = sin(Double(index) * 12.9898 + Double(question) * 78.233) * 43758.5453
        return n - n.rounded(.down)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard intensity > 0 else { return }
                context.blendMode = .plusLighter
                let now = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<SideStreaks.count {
                    let length = size.width * SideStreaks.lengthShare * (SideStreaks.shortest + SideStreaks.scatter(index, 2))
                    let speed = size.width * SideStreaks.speedShare * (SideStreaks.slowest + SideStreaks.scatter(index, 3))
                    let run = size.width + length
                    let travelled = (now * speed + Double(index) * 97).truncatingRemainder(dividingBy: run)
                    let x = travelled - length
                    let y = SideStreaks.scatter(index, 1) * size.height
                    let streak = CGRect(x: x, y: y - thickness / 2, width: length, height: thickness)
                    let glow = intensity * (SideStreaks.faintest + SideStreaks.scatter(index, 4))
                    let bloom = streak.insetBy(dx: 0, dy: -thickness * (SideStreaks.bloom - 1) / 2)
                    context.fill(Capsule().path(in: bloom), with: .color(ink.opacity(glow * SideStreaks.bloomGain)))
                    context.fill(Capsule().path(in: streak), with: .color(ink.opacity(glow)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A leaning rectangle: both bars are one, and the lean is what makes them read as a single
/// diagonal when they cross.
struct Parallelogram: Shape {
    var lean: CGFloat

    func path(in rect: CGRect) -> Path {
        let shift = rect.height * lean
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + shift, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - shift, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
