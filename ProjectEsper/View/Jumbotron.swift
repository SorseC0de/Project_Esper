import SwiftUI

/// The main menu's jumbotron, made of holographic light: the screens round a frustum, each a
/// trapezoid wider at the top, turning on `JumbotronScreens`; the pole they hang from, down to the
/// middle of the lower rung; and the lower rung, seen from below, its options round it turning on
/// their own (`LowerRung`). Laid out in a 680 by 383 design space, scaled to fit the screen.
struct JumbotronLayout {
    static let designSize = CGSize(width: 680, height: 383)
    static let centreX: CGFloat = 340
    /// The width the layout's fitted to: the assembly and its arrows, not the mock-up's whole frame,
    /// so a squarer screen (the iPad's) shows it larger; the wider ones fit to their height as before.
    static let fitWidth: CGFloat = 560

    /// The screens: the frustum's top and bottom, their heights, radii and how far the near side bows up.
    static let screensTopY: CGFloat = 44
    static let screensBottomY: CGFloat = 222
    static let screensTopRadius: CGFloat = 215
    static let screensBottomRadius: CGFloat = 140
    static let screensTopBow: CGFloat = 14
    static let screensBottomBow: CGFloat = 10
    /// Each screen's share of its slot round the frustum: the rest is the gap between neighbours.
    static let screenSpanShare = 0.84
    /// A screen's angle across with `count` round the ring: never wider than with three, so one or two (VTV's) don't wrap round it.
    static func screenSpan(count: Int) -> Double { 2 * .pi / Double(max(count, 3)) * screenSpanShare }
    /// A screen's content, laid out flat at this size before it's mapped onto its trapezoid.
    static let screenContentSize = CGSize(width: 160, height: 120)
    /// The screens turned away, seen faintly through the light.
    static let backScreenOpacity = 0.18
    /// The picture in front of each screen, upright: its size, its middle a share of the way down the
    /// screen, and how far out in front of it it floats.
    static let floatSize = CGSize(width: 96, height: 58)
    static let floatCentreShare: CGFloat = 0.7
    static let floatOut: CGFloat = 8
    /// A swap of the screens' sets: the going set flies out to this share more of its radius, turning
    /// this far round the spindle as it fades; the coming set flies in the same way round to rest.
    static let flightSpread: CGFloat = 0.5
    static let flightTurn = Double.pi / 2
    /// The flight's fade: opacity 1 - spread to this power, so the screens stay seen most of the way out.
    static let flightFadePower = 3.0
    /// Screens and pictures nearer side-on than this cosine aren't drawn.
    static let sideOnCos = 0.01

    /// The lower rung: its top and bottom, radius and bow, and the dark hole in its underside.
    static let rungTopY: CGFloat = 250
    static let rungBottomY: CGFloat = 272
    static let rungRadius: CGFloat = 92
    static let rungBow: CGFloat = 13
    static let rungHoleRadius: CGFloat = 72
    static let rungHoleBow: CGFloat = 8
    static let rungTextSize: CGFloat = 11
    /// The option round the back, seen faintly through the light.
    static let backOptionOpacity = 0.28

    /// The pole, from the top of the screen down to the lower rung's middle.
    static let poleHalfWidth: CGFloat = 18
    static let poleCapBow: CGFloat = 3

    /// THEME's picker under the lower rung: its middle's height and its display's width.
    static let themePickerY: CGFloat = 334
    static let themePickerWidth: CGFloat = 200

    /// The turning arrows: out from the screens' top corners, at the screens' middle height.
    static let arrowGap: CGFloat = 20
    static let arrowY: CGFloat = 133

    /// Every line's width, in design units; the faint far rim's thinner.
    static let lineWidth: CGFloat = 1
    static let faintLineWidth: CGFloat = 0.75
    /// The dark thin material's share: on its own it hides too much of what's behind.
    static let materialOpacity = 0.66

    static var line: Color { Futuristic.line }
    static var light: Color { Color(rgb: MenuTheme.lightRGB) }

    let size: CGSize
    let unit: CGFloat
    let origin: CGPoint
    /// The menus' color it was laid out in, so what's drawn from it is drawn again when THEME changes it.
    let theme = MenuTheme.colour

    init(size: CGSize) {
        self.size = size
        unit = min(size.width / JumbotronLayout.fitWidth, size.height / JumbotronLayout.designSize.height)
        origin = CGPoint(x: size.width / 2 - JumbotronLayout.centreX * unit,
                         y: (size.height - JumbotronLayout.designSize.height * unit) / 2)
    }

    /// A point in the design space, on the screen.
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * unit, y: origin.y + y * unit)
    }

    /// A point round a ring of the jumbotron at `angle` from the front, its near side bowed up.
    func ringPoint(angle: Double, radius: CGFloat, y: CGFloat, bow: CGFloat) -> CGPoint {
        point(JumbotronLayout.centreX + radius * sin(angle), y - bow * cos(angle))
    }

    /// The screen at `angle` from the front: its corners top left, top right, bottom right, bottom left;
    /// `spread` of the way out on a swap's flight, its rings wider by `flightSpread` at the most.
    func screenCorners(angle: Double, span: Double, spread: Double = 0) -> [CGPoint] {
        let left = angle - span / 2, right = angle + span / 2
        let reach = 1 + CGFloat(spread) * JumbotronLayout.flightSpread
        let topRadius = JumbotronLayout.screensTopRadius * reach, topBow = JumbotronLayout.screensTopBow * reach
        let bottomRadius = JumbotronLayout.screensBottomRadius * reach, bottomBow = JumbotronLayout.screensBottomBow * reach
        return [ringPoint(angle: left, radius: topRadius, y: JumbotronLayout.screensTopY, bow: topBow),
                ringPoint(angle: right, radius: topRadius, y: JumbotronLayout.screensTopY, bow: topBow),
                ringPoint(angle: right, radius: bottomRadius, y: JumbotronLayout.screensBottomY, bow: bottomBow),
                ringPoint(angle: left, radius: bottomRadius, y: JumbotronLayout.screensBottomY, bow: bottomBow)]
    }

    /// The picture in front of the screen at `angle`: upright, its sides straight up and down, turned
    /// with the screen round a ring just out from the frustum at the picture's height; `spread` out as its screen's.
    func pictureCorners(angle: Double, spread: Double = 0) -> [CGPoint] {
        let share = JumbotronLayout.floatCentreShare
        let reach = 1 + CGFloat(spread) * JumbotronLayout.flightSpread
        let middleY = JumbotronLayout.screensTopY + (JumbotronLayout.screensBottomY - JumbotronLayout.screensTopY) * share
        let bow = (JumbotronLayout.screensTopBow + (JumbotronLayout.screensBottomBow - JumbotronLayout.screensTopBow) * share) * reach
        let radius = (JumbotronLayout.screensTopRadius + (JumbotronLayout.screensBottomRadius - JumbotronLayout.screensTopRadius) * share
            + JumbotronLayout.floatOut) * reach
        let halfSpan = asin(min(JumbotronLayout.floatSize.width / 2 / radius, 1))
        let top = middleY - JumbotronLayout.floatSize.height / 2, bottom = middleY + JumbotronLayout.floatSize.height / 2
        let left = angle - halfSpan, right = angle + halfSpan
        return [ringPoint(angle: left, radius: radius, y: top, bow: bow), ringPoint(angle: right, radius: radius, y: top, bow: bow),
                ringPoint(angle: right, radius: radius, y: bottom, bow: bow), ringPoint(angle: left, radius: radius, y: bottom, bow: bow)]
    }

    /// The projection taking a flat `size` onto the four `corners` (top left, top right, bottom
    /// right, bottom left), so a screen's content is skewed with its trapezoid.
    static func mapping(_ size: CGSize, onto corners: [CGPoint]) -> ProjectionTransform {
        let (x0, y0) = (corners[0].x, corners[0].y), (x1, y1) = (corners[1].x, corners[1].y)
        let (x2, y2) = (corners[2].x, corners[2].y), (x3, y3) = (corners[3].x, corners[3].y)
        let dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2
        let sx = x0 - x1 + x2 - x3, sy = y0 - y1 + y2 - y3
        let determinant = dx1 * dy2 - dx2 * dy1
        let g = abs(determinant) < 0.0001 ? 0 : (sx * dy2 - dx2 * sy) / determinant
        let h = abs(determinant) < 0.0001 ? 0 : (dx1 * sy - sx * dy1) / determinant
        var transform = ProjectionTransform()
        transform.m11 = (x1 - x0 + g * x1) / size.width
        transform.m12 = (y1 - y0 + g * y1) / size.width
        transform.m13 = g / size.width
        transform.m21 = (x3 - x0 + h * x3) / size.height
        transform.m22 = (y3 - y0 + h * y3) / size.height
        transform.m23 = h / size.height
        transform.m31 = x0
        transform.m32 = y0
        transform.m33 = 1
        return transform
    }

    /// Whether `point` is inside the four `corners`, in order round them.
    static func contains(_ corners: [CGPoint], _ point: CGPoint) -> Bool {
        var inside = false
        var previous = corners[corners.count - 1]
        for corner in corners {
            if (corner.y > point.y) != (previous.y > point.y),
               point.x < (previous.x - corner.x) * (point.y - corner.y) / (previous.y - corner.y) + corner.x {
                inside.toggle()
            }
            previous = corner
        }
        return inside
    }
}

/// The screens round the frustum and the pole through them, in two sets (the main menu's and
/// PLAY's), each turned to its own turn (a screen's slot a step). Animatable, so a turn eases
/// through every angle with the depth order following it, and a swap flies the going set out round
/// the spindle, fading, and the coming set in after it the same way round, to rest.
struct JumbotronScreens<Screen: View, Picture: View>: View, Animatable {
    /// The first set's turn and the second's.
    var turns: AnimatablePair<Double, Double>
    /// The swaps so far: a whole number at rest, even showing the first set and odd the second; up
    /// a swap flies them one way round, down the other.
    var swaps: Double
    /// Each set's count of screens.
    let counts: [Int]
    let layout: JumbotronLayout
    /// A set's screen (the set, its place round it) at its size in points.
    @ViewBuilder let screen: (Int, Int, CGSize) -> Screen
    /// The picture in front of each screen, flat to the viewer, at its size in points.
    @ViewBuilder let picture: (Int, Int, CGSize) -> Picture

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(turns, swaps) }
        set {
            turns = newValue.first
            swaps = newValue.second
        }
    }

    /// Each screen's angle from the front at this turn, and turned on round the spindle with a swap's `flight`.
    static func angle(of index: Int, turn: Double, count: Int, flight: Double = 0) -> Double {
        (Double(index) - turn) * 2 * .pi / Double(count) - flight * JumbotronLayout.flightTurn
    }

    /// The set shown at `swaps`: the nearest whole swap's.
    static func shownSet(swaps: Double) -> Int {
        let whole = Int(swaps.rounded())
        return (whole % 2 + 2) % 2
    }

    /// How far through its flight the shown set is, -1 to 1: 0 at rest, past it flying out, short of it flying in.
    static func flight(swaps: Double) -> Double {
        2 * (swaps - swaps.rounded())
    }

    var body: some View {
        // Laid out a little larger than it's drawn at the front, so the lettering stays sharp.
        let contentSize = CGSize(width: JumbotronLayout.screenContentSize.width * layout.unit * 1.4,
                                 height: JumbotronLayout.screenContentSize.height * layout.unit * 1.4)
        let set = JumbotronScreens.shownSet(swaps: swaps)
        let count = counts[set]
        let turn = set == 0 ? turns.first : turns.second
        let flight = JumbotronScreens.flight(swaps: swaps)
        let spread = abs(flight)
        let span = JumbotronLayout.screenSpan(count: count)
        ZStack(alignment: .topLeading) {
            JumbotronPole(layout: layout)
                .zIndex(10)
            ForEach(0..<count, id: \.self) { index in
                let angle = JumbotronScreens.angle(of: index, turn: turn, count: count, flight: flight)
                let toward = cos(angle)
                let facing = toward > 0.05
                let opacity = (facing ? 1 : JumbotronLayout.backScreenOpacity) * (1 - pow(spread, JumbotronLayout.flightFadePower))
                // Side-on, its projection collapses to a line and SwiftUI draws it unprojected at the top left.
                if abs(toward) > JumbotronLayout.sideOnCos {
                    screen(set, index, contentSize)
                        .frame(width: contentSize.width, height: contentSize.height)
                        .projectionEffect(JumbotronLayout.mapping(contentSize, onto: layout.screenCorners(angle: angle, span: span, spread: spread)))
                        .opacity(opacity)
                        // The back ones behind the pole, the front ones over it, the nearest on top.
                        .zIndex(facing ? 20 + toward : toward)
                    // Its picture just out in front of it, turning with it but upright, not slanted with the trapezoid.
                    let pictureSize = CGSize(width: JumbotronLayout.floatSize.width * layout.unit * 1.4,
                                             height: JumbotronLayout.floatSize.height * layout.unit * 1.4)
                    picture(set, index, pictureSize)
                        .frame(width: pictureSize.width, height: pictureSize.height)
                        .projectionEffect(JumbotronLayout.mapping(pictureSize, onto: layout.pictureCorners(angle: angle, spread: spread)))
                        .opacity(opacity)
                        .zIndex((facing ? 20 + toward : toward) + 0.01)
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// The pole the jumbotron hangs from: a cylinder of light from the top of the screen to the lower
/// rung's middle, its end showing on the rung's underside.
struct JumbotronPole: View {
    let layout: JumbotronLayout

    var body: some View {
        Canvas { context, _ in
            let unit = layout.unit
            let left = layout.point(JumbotronLayout.centreX - JumbotronLayout.poleHalfWidth, 0).x
            let right = layout.point(JumbotronLayout.centreX + JumbotronLayout.poleHalfWidth, 0).x
            let bottom = layout.point(0, JumbotronLayout.rungBottomY).y
            context.fill(Path(CGRect(x: left, y: 0, width: right - left, height: bottom)), with: .color(JumbotronLayout.light.opacity(0.07)))
            // Its sheen, down the left of the middle.
            context.fill(Path(CGRect(x: left + 5 * unit, y: 0, width: 7 * unit, height: bottom)), with: .color(JumbotronLayout.line.opacity(0.12)))
            var edges = Path()
            edges.move(to: CGPoint(x: left, y: 0)); edges.addLine(to: CGPoint(x: left, y: bottom))
            edges.move(to: CGPoint(x: right, y: 0)); edges.addLine(to: CGPoint(x: right, y: bottom))
            context.stroke(edges, with: .color(JumbotronLayout.line.opacity(0.8)), lineWidth: JumbotronLayout.lineWidth * unit)
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }
}

/// The lower rung, seen from below: a band of light, its underside a ring round a dark hole with
/// the pole's end in the middle, and its options round it, turned to `turn` (an option's slot a step):
/// the front one full, the ones round the back faint and mirrored through the light.
struct LowerRung: View, Animatable {
    var turn: Double
    let labels: [String]
    /// The front option lit gold, with the rung under the cursor.
    let lit: Bool
    let layout: JumbotronLayout

    var animatableData: Double {
        get { turn }
        set { turn = newValue }
    }

    var body: some View {
        let unit = layout.unit
        ZStack(alignment: .topLeading) {
            // The band's front in the dark thin material, tinted with the light.
            RungBand(layout: layout).fill(.ultraThinMaterial).opacity(JumbotronLayout.materialOpacity)
            RungBand(layout: layout).fill(JumbotronLayout.light.opacity(0.08))
            Canvas { context, _ in
                let radius = JumbotronLayout.rungRadius * unit, bow = JumbotronLayout.rungBow * unit
                let top = layout.point(JumbotronLayout.centreX, JumbotronLayout.rungTopY)
                let bottom = layout.point(JumbotronLayout.centreX, JumbotronLayout.rungBottomY)
                let bottomRim = CGRect(x: bottom.x - radius, y: bottom.y - bow, width: 2 * radius, height: 2 * bow)
                // The top rim's near half bright, its far half faint through the light; the band's sides.
                var nearRim = Path()
                nearRim.addArc(center: top, radius: 1, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false,
                               transform: CGAffineTransform(translationX: top.x, y: top.y).scaledBy(x: radius, y: bow).translatedBy(x: -top.x, y: -top.y))
                nearRim.move(to: CGPoint(x: top.x - radius, y: top.y)); nearRim.addLine(to: CGPoint(x: bottom.x - radius, y: bottom.y))
                nearRim.move(to: CGPoint(x: top.x + radius, y: top.y)); nearRim.addLine(to: CGPoint(x: bottom.x + radius, y: bottom.y))
                context.stroke(nearRim, with: .color(JumbotronLayout.line.opacity(0.9)), lineWidth: JumbotronLayout.lineWidth * unit)
                var farRim = Path()
                farRim.addArc(center: top, radius: 1, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false,
                              transform: CGAffineTransform(translationX: top.x, y: top.y).scaledBy(x: radius, y: bow).translatedBy(x: -top.x, y: -top.y))
                context.stroke(farRim, with: .color(JumbotronLayout.line.opacity(0.25)), lineWidth: JumbotronLayout.faintLineWidth * unit)
                // The underside: the ring, and the hole and the pole's end in fills alone.
                context.fill(Path(ellipseIn: bottomRim), with: .color(JumbotronLayout.light.opacity(0.12)))
                context.stroke(Path(ellipseIn: bottomRim), with: .color(JumbotronLayout.line.opacity(0.9)), lineWidth: JumbotronLayout.lineWidth * unit)
                let holeRadius = JumbotronLayout.rungHoleRadius * unit, holeBow = JumbotronLayout.rungHoleBow * unit
                let hole = CGRect(x: bottom.x - holeRadius, y: bottom.y + unit - holeBow, width: 2 * holeRadius, height: 2 * holeBow)
                context.fill(Path(ellipseIn: hole), with: .color(Color(red: 4 / 255, green: 20 / 255, blue: 40 / 255).opacity(0.85)))
                let poleRadius = JumbotronLayout.poleHalfWidth * unit, capBow = JumbotronLayout.poleCapBow * unit
                let cap = CGRect(x: bottom.x - poleRadius, y: bottom.y + unit - capBow, width: 2 * poleRadius, height: 2 * capBow)
                context.fill(Path(ellipseIn: cap), with: .color(JumbotronLayout.light.opacity(0.25)))
            }
            .frame(width: layout.size.width, height: layout.size.height)
            ForEach(labels.indices, id: \.self) { index in
                let angle = (Double(index) - turn) * 2 * .pi / Double(max(labels.count, 1))
                let toward = cos(angle)
                let middleY = (JumbotronLayout.rungTopY + JumbotronLayout.rungBottomY) / 2
                Text(labels[index])
                    .font(Futuristic.font(size: JumbotronLayout.rungTextSize * unit))
                    .foregroundStyle(lit && toward > 0.5 ? Futuristic.lit : JumbotronLayout.line)
                    .fixedSize()
                    .scaleEffect(x: toward, y: 1)
                    .opacity(toward > 0 ? 1 : JumbotronLayout.backOptionOpacity)
                    .position(layout.ringPoint(angle: angle, radius: JumbotronLayout.rungRadius, y: middleY, bow: JumbotronLayout.rungBow))
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// The lower rung's front: over the top rim's near half, down its sides, and under the bottom rim's far half.
struct RungBand: Shape {
    let layout: JumbotronLayout

    func path(in rect: CGRect) -> Path {
        let unit = layout.unit
        let radius = JumbotronLayout.rungRadius * unit, bow = JumbotronLayout.rungBow * unit
        let top = layout.point(JumbotronLayout.centreX, JumbotronLayout.rungTopY)
        let bottom = layout.point(JumbotronLayout.centreX, JumbotronLayout.rungBottomY)
        var band = Path()
        band.addArc(center: top, radius: 1, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false,
                    transform: CGAffineTransform(translationX: top.x, y: top.y).scaledBy(x: radius, y: bow).translatedBy(x: -top.x, y: -top.y))
        band.addLine(to: CGPoint(x: bottom.x + radius, y: bottom.y))
        band.addArc(center: bottom, radius: 1, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false,
                    transform: CGAffineTransform(translationX: bottom.x, y: bottom.y).scaledBy(x: radius, y: bow).translatedBy(x: -bottom.x, y: -bottom.y))
        band.closeSubpath()
        return band
    }
}
