import simd
import SwiftUI

/// The V-Key's screen, over whatever asked for it: the grid room (`GridRoom`), key_cyber turned 45 degrees with
/// small cubes rising off it, both in the menus' blue; what it opens; UNLOCK at its price and
/// RESTORE in frame 8, the cursor's gold. Bought, it goes.
struct VKeyScreen: View {
    @ObservedObject var flow: FlowState
    @ObservedObject private var store = VKeyStore.shared
    @ObservedObject private var tuning = UITuning.shared
    private func scale(_ part: UIPart) -> CGFloat { tuning.scale(.title, part) }

    static let titleHeight: CGFloat = 20
    static let choiceScale: CGFloat = 0.8
    static let choiceTextSize: CGFloat = 12
    /// The key's length against the screen's height, and its turn clockwise.
    static let keyLengthShare: CGFloat = 0.6
    static let keyTilt = 45.0
    /// The cubes: how many a second leave the key, seconds each lasts, how far it rises in that time
    /// (a share of the key's length), its size in points, and how far across it wanders.
    static let cubesPerSecond = 14.0
    static let cubeLife = 1.8
    static let cubeRise: CGFloat = 0.45
    static let cubeSizes: ClosedRange<CGFloat> = 4...8
    static let cubeWander: CGFloat = 0.06

    var body: some View {
        GeometryReader { geometry in
            let keyLength = geometry.size.height * VKeyScreen.keyLengthShare
            ZStack {
                Color.black
                GridRoom()
                HStack(spacing: geometry.size.width * 0.06) {
                    key(length: keyLength)
                        .frame(width: keyLength, height: keyLength)
                    VStack(spacing: 12 * scale(.buttons)) {
                        FloText("V-KEY", height: VKeyScreen.titleHeight * scale(.titles))
                        Text("EVERY MODE, STAGE AND COLOR")
                            .font(Futuristic.font(size: 13 * scale(.text)))
                            .foregroundStyle(Futuristic.line)
                            .fixedSize()
                        framed(store.product.map { "UNLOCK  \($0.displayPrice)" } ?? "UNLOCK", button: 0)
                        framed("RESTORE PURCHASE", button: 1)
                        Text(store.busy ? "ONE MOMENT" : store.note ?? " ")
                            .font(Futuristic.font(size: 11 * scale(.text)))
                            .foregroundStyle(Futuristic.line.opacity(0.8))
                            .fixedSize()
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onChange(of: store.shownOwned) { _, owned in
            if owned { flow.vKeyBought() }
        }
    }

    /// The key turned, and the cubes rising off it: each cube's place along the key, its wander,
    /// size and spin drawn from its number, so the stream is the same however the screen is redrawn.
    private func key(length: CGFloat) -> some View {
        let image = Futuristic.image("icon_key_cyber")
        let width = length * image.size.width / max(image.size.height, 1)
        // The cubes' room: the key's square, and a key's length more above it for them to rise into,
        // over the key without moving it.
        return Image(uiImage: image)
            .resizable()
            .colorMultiply(Futuristic.line)
            .frame(width: width, height: length)
            .rotationEffect(.degrees(VKeyScreen.keyTilt))
            .shadow(color: Futuristic.line.opacity(0.6), radius: 8)
            .frame(width: length, height: length)
            .overlay {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let centre = CGPoint(x: size.width / 2, y: size.height - length / 2)
                        // Down the key, top to bottom, turned with it.
                        let angle = VKeyScreen.keyTilt * .pi / 180
                        let along = CGVector(dx: -sin(angle), dy: cos(angle))
                        let newest = Int(time * VKeyScreen.cubesPerSecond)
                        let count = Int(VKeyScreen.cubeLife * VKeyScreen.cubesPerSecond)
                        for number in (newest - count)...newest {
                            let born = Double(number) / VKeyScreen.cubesPerSecond
                            let age = time - born
                            guard age >= 0, age < VKeyScreen.cubeLife else { continue }
                            let place = (VKeyScreen.random(number, 1) - 0.5) * 0.9 * length
                            let rise = CGFloat(age / VKeyScreen.cubeLife) * VKeyScreen.cubeRise * length
                            let wander = (VKeyScreen.random(number, 2) - 0.5) * 2 * VKeyScreen.cubeWander * length * CGFloat(age / VKeyScreen.cubeLife)
                            let at = CGPoint(x: centre.x + along.dx * place + wander, y: centre.y + along.dy * place - rise)
                            let axis = simd_normalize(SIMD3<Float>(Float(VKeyScreen.random(number, 3)) - 0.5, Float(VKeyScreen.random(number, 4)) - 0.5, 0.5))
                            let spin = Float(age) * (1.5 + Float(VKeyScreen.random(number, 5)) * 2) + Float(VKeyScreen.random(number, 6)) * 6
                            let sizes = VKeyScreen.cubeSizes
                            let cube = CustomizeFigureMotion.Cube(position: at, velocity: .zero, age: age, life: VKeyScreen.cubeLife,
                                                                  orientation: simd_quatf(angle: spin, axis: axis), spin: .zero,
                                                                  size: sizes.lowerBound + VKeyScreen.random(number, 7) * (sizes.upperBound - sizes.lowerBound),
                                                                  colour: Futuristic.lineRGB, behind: false)
                            CustomizeFigure.drawCube(cube, in: context, at: at, pixel: scale(.buttons))
                        }
                    }
                }
                .frame(width: length, height: length * 2)
                .offset(y: -length / 2)
                .allowsHitTesting(false)
            }
    }

    /// 0 to 1 from a cube's number and which draw it is.
    private static func random(_ number: Int, _ draw: UInt64) -> CGFloat {
        var bits = UInt64(bitPattern: Int64(number)) &* 0x9E37_79B9_7F4A_7C15 ^ draw &* 0xBF58_476D_1CE4_E5B9
        bits ^= bits >> 31
        bits = bits &* 0x94D0_49BB_1331_11EB
        bits ^= bits >> 29
        return CGFloat(bits >> 11) / CGFloat(1 << 53)
    }

    /// A button in frame 8, the second turned round both ways, as the multiplayer screen's.
    private func framed(_ text: String, button: Int) -> some View {
        let lit = flow.vKeyCursor == button
        let turned = button % 2 == 1
        return Button { flow.activateVKey(button) } label: {
            FuturisticFrame(name: "8", lit: lit, scale: VKeyScreen.choiceScale * scale(.buttons), mirrored: turned, upsideDown: turned) { colour in
                Text(text)
                    .font(Futuristic.font(size: VKeyScreen.choiceTextSize * scale(.text)))
                    .foregroundStyle(colour)
                    .fixedSize()
            }
            .opacity(store.busy ? TitleOverlay.unpickedOpacity : 1)
        }
        .buttonStyle(.plain)
        .disabled(store.busy)
        .noSystemFocus()
    }
}
