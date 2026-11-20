import GameController
import SwiftUI

/// The title screen, before the main menu: the grid room on black, small rectangles flying out
/// of the horizon at the camera, the Variaball logo large over them, and the prompt breathing
/// under it. A tap, or any button on a pad, goes on to the main menu.
struct TitleScreen: View {
    @ObservedObject var flow: FlowState
    @State private var padConnected = TitleScreen.anyPadConnected

    static let logoWidthShare: CGFloat = 0.7
    static let logo = UIImage(named: "variaball_logo") ?? UIImage()
    static let logoHeightShare: CGFloat = 0.4
    static let promptGapShare: CGFloat = 0.05
    static let promptTextSize: CGFloat = 54
    /// Infinium Guardian, by its place in `Futuristic.typefaces`.
    static let promptFace = 1
    static let breathSeconds = 2.4
    static let breathLowestOpacity = 0.3

    static var anyPadConnected: Bool {
        GCController.controllers().contains { $0.extendedGamepad != nil }
    }

    private var prompt: String {
        #if os(tvOS)
        return "Press Any Button"
        #else
        return padConnected ? "Press Any Button" : "Tap Anywhere"
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Color.black
                GridRoom()
                FlyingRectangles()
                VStack(spacing: size.height * TitleScreen.promptGapShare) {
                    // Framed to the logo's own size, so nothing pads it from the prompt.
                    let logo = TitleScreen.logo
                    let logoAspect = logo.size.width / max(logo.size.height, 1)
                    let logoWidth = min(size.width * TitleScreen.logoWidthShare, size.height * TitleScreen.logoHeightShare * logoAspect)
                    Image(uiImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: logoWidth, height: logoWidth / logoAspect)
                    TimelineView(.animation) { timeline in
                        let phase = timeline.date.timeIntervalSinceReferenceDate / TitleScreen.breathSeconds * 2 * .pi
                        let breath = 0.5 - 0.5 * cos(phase)
                        Text(prompt)
                            .font(Futuristic.font(size: TitleScreen.promptTextSize, face: TitleScreen.promptFace))
                            .foregroundStyle(.white)
                            .fixedSize()
                            .opacity(TitleScreen.breathLowestOpacity + (1 - TitleScreen.breathLowestOpacity) * breath)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture { flow.leaveTitleScreen() }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in padConnected = TitleScreen.anyPadConnected }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in padConnected = TitleScreen.anyPadConnected }
    }
}

/// The inside of a box seen from its open end, in the menus' purple grid lines on black: the back
/// wall in the middle, the floor, ceiling and side walls running out to the screen's edges. The
/// title screen's and the V-Key screen's ground.
struct GridRoom: View {
    /// The back wall's width against the screen's.
    static let backWallShare: CGFloat = 0.5
    /// The room's depth, in back wall widths.
    static let depthShare: CGFloat = 0.75
    /// Grid cells across the back wall.
    static let backWallColumns = 12
    static let lineWidth: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let room = RoomProjection(size: size)
            let cell = room.cell
            var path = Path()
            func line(_ from: SIMD3<Double>, _ to: SIMD3<Double>) {
                path.move(to: room.project(from))
                path.addLine(to: room.project(to))
            }
            let near = room.nearDepth, far = room.farDepth, halfHeight = room.halfHeight
            let columns = Int((1 / cell).rounded(.down)), rows = Int((halfHeight / cell).rounded(.down))
            // Along the floor and ceiling, and up the back wall.
            for column in -columns...columns {
                let x = Double(column) * cell
                line([x, -halfHeight, near], [x, -halfHeight, far])
                line([x, halfHeight, near], [x, halfHeight, far])
                line([x, -halfHeight, far], [x, halfHeight, far])
            }
            // Along the side walls, and across the back wall.
            for row in -rows...rows {
                let y = Double(row) * cell
                line([-1, y, near], [-1, y, far])
                line([1, y, near], [1, y, far])
                line([-1, y, far], [1, y, far])
            }
            // The room's four corners, front to back.
            for x in [-1.0, 1.0] { for y in [-halfHeight, halfHeight] { line([x, y, near], [x, y, far]) } }
            // The rings round the room, a cell apart from the back wall forward.
            var depth = far
            while depth >= near {
                let corners = [SIMD3(-1, -halfHeight, depth), SIMD3(1, -halfHeight, depth), SIMD3(1, halfHeight, depth), SIMD3(-1, halfHeight, depth)]
                path.move(to: room.project(corners[3]))
                for corner in corners { path.addLine(to: room.project(corner)) }
                depth -= cell
            }
            context.stroke(path, with: .color(Color(rgb: EsperPalette.plum.light).opacity(CustomizeScreen.gridOpacity)), lineWidth: GridRoom.lineWidth)
        }
    }
}

/// The room's camera: the walls at x = ±1, the floor and ceiling at the screen's shape, the screen's
/// edges at `nearDepth` and the back wall at `farDepth`.
struct RoomProjection {
    let size: CGSize
    let halfHeight: Double
    let nearDepth: Double
    let farDepth: Double
    let focal: Double
    let cell: Double

    init(size: CGSize) {
        self.size = size
        halfHeight = Double(size.height / max(size.width, 1))
        let share = Double(GridRoom.backWallShare)
        nearDepth = 2 * Double(GridRoom.depthShare) * share / (1 - share)
        farDepth = nearDepth / share
        focal = nearDepth * Double(size.width) / 2
        cell = 2 / Double(GridRoom.backWallColumns)
    }

    func project(_ point: SIMD3<Double>) -> CGPoint {
        CGPoint(x: size.width / 2 + focal * point.x / point.z, y: size.height / 2 - focal * point.y / point.z)
    }

    /// Points across at `depth` for a length of one.
    func scale(at depth: Double) -> Double { focal / depth }
}

/// Small rectangles flying out of the horizon at the camera, wide, tall and square, half grey and
/// half the energy colours bar Diamond. Each one's place, shape, size and colour drawn from its
/// number, so the stream is the same however the screen is redrawn.
struct FlyingRectangles: View {
    static let perSecond = 24.0
    static let lifeSeconds = 8.0
    static let startDepth = 12.0
    /// How far out from the middle they start, against the room's walls.
    static let spread = 2.5
    static let endDepth = 0.5
    /// The shorter side, in room units (the room is 2 across).
    static let sizes: ClosedRange<Double> = 0.02...0.05
    /// The longer side of a wide or tall one against its shorter.
    static let stretch = 2.5
    /// The share of its life it takes to fade in out of the distance.
    static let fadeInShare = 0.15
    static let grey = Color(rgb: 0x424C6E)
    static let colours = EnergyColour.hued.map { Color(rgb: $0.glow) }

    private struct Flyer {
        let depth: Double
        let rect: CGRect
        let colour: Color
        let opacity: Double
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let room = RoomProjection(size: size)
                let time = timeline.date.timeIntervalSinceReferenceDate
                let newest = Int(time * FlyingRectangles.perSecond)
                let count = Int(FlyingRectangles.lifeSeconds * FlyingRectangles.perSecond)
                var flyers: [Flyer] = []
                for number in (newest - count)...newest {
                    let age = time - Double(number) / FlyingRectangles.perSecond
                    guard age >= 0, age < FlyingRectangles.lifeSeconds else { continue }
                    let progress = age / FlyingRectangles.lifeSeconds
                    let depth = FlyingRectangles.startDepth + (FlyingRectangles.endDepth - FlyingRectangles.startDepth) * progress
                    let x = (FlyingRectangles.random(number, 1) * 2 - 1) * FlyingRectangles.spread
                    let y = (FlyingRectangles.random(number, 2) * 2 - 1) * room.halfHeight * FlyingRectangles.spread
                    let sizes = FlyingRectangles.sizes
                    let short = sizes.lowerBound + FlyingRectangles.random(number, 3) * (sizes.upperBound - sizes.lowerBound)
                    let shape = Int(FlyingRectangles.random(number, 4) * 3)
                    let width = shape == 0 ? short * FlyingRectangles.stretch : short
                    let height = shape == 1 ? short * FlyingRectangles.stretch : short
                    let centre = room.project([x, y, depth])
                    let scale = room.scale(at: depth)
                    let rect = CGRect(x: centre.x - width * scale / 2, y: centre.y - height * scale / 2, width: width * scale, height: height * scale)
                    guard rect.intersects(CGRect(origin: .zero, size: size)) else { continue }
                    let colours = FlyingRectangles.colours
                    let colour = FlyingRectangles.random(number, 5) < 0.5
                        ? FlyingRectangles.grey
                        : colours[min(Int(FlyingRectangles.random(number, 6) * Double(colours.count)), colours.count - 1)]
                    flyers.append(Flyer(depth: depth, rect: rect, colour: colour, opacity: min(progress / FlyingRectangles.fadeInShare, 1)))
                }
                // The furthest first, so the nearer cover them.
                for flyer in flyers.sorted(by: { $0.depth > $1.depth }) {
                    context.fill(Path(flyer.rect), with: .color(flyer.colour.opacity(flyer.opacity)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// 0 to 1 from a rectangle's number and which draw it is.
    private static func random(_ number: Int, _ draw: UInt64) -> Double {
        var bits = UInt64(bitPattern: Int64(number)) &* 0x9E37_79B9_7F4A_7C15 ^ draw &* 0xBF58_476D_1CE4_E5B9
        bits ^= bits >> 31
        bits = bits &* 0x94D0_49BB_1331_11EB
        bits ^= bits >> 29
        return Double(bits >> 11) / Double(1 << 53)
    }
}
