import EsperSim
import SwiftUI

/// A side's picks on the customize screen, kept between rounds and launches: the energy
/// colour, one of the wheel's or the shade down its ramp, and what the player wears.
struct PlayerCustomization: Codable, Equatable {
    var energy: EnergyColour
    /// The second row's: the shade down the colour's ramp.
    var deep = false
    var dressing = Dressing()

    var glow: RGB { deep ? energy.rampDown : energy.glow }
    var look: Look { Look.team(glow, body: Look.lightened(glow, EnergyColour.bodyLift), dressing: dressing) }

    private static func key(_ player: Int) -> String { "esper.customize.p\(player + 1)" }

    /// What a side last picked; before any, the title's colour for the first and teal for the second.
    static func saved(_ player: Int) -> PlayerCustomization {
        if let data = UserDefaults.standard.data(forKey: key(player)),
           let kept = try? JSONDecoder().decode(PlayerCustomization.self, from: data) { return kept }
        return PlayerCustomization(energy: player == 0 ? EnergyColour.saved : .teal)
    }

    func save(as player: Int) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key(player)) }
        // The first side's colour is this phone's: the title shows it and multiplayer sends it.
        if player == 0 { UserDefaults.standard.set(energy.rawValue, forKey: EnergyColour.storageKey) }
    }

    /// Both sides as they play: when the two glow the same, the second gives way to the opposite.
    static func clashed(_ sides: [PlayerCustomization]) -> [PlayerCustomization] {
        var sides = sides
        if sides.count > 1, sides[1].glow == sides[0].glow {
            sides[1].energy = sides[0].energy.opposite
            sides[1].deep = false
        }
        return sides
    }

    static var sides: [PlayerCustomization] { clashed([saved(0), saved(1)]) }
}

/// Where a side's cursor can stand on the customize screen.
enum CustomizeSpot: Hashable {
    case skin, arms, legs, hood
    /// The energy picker: row 0 the wheel's colours, row 1 each one's shade down.
    case swatch(row: Int, column: Int)
    case start, back

    /// Top to bottom down a side: the boxes, the hood, the picker's rows, RETURN. START sits
    /// level with the hood.
    var rung: Int {
        switch self {
        case .skin: 0
        case .arms: 1
        case .legs: 2
        case .hood, .start: 3
        case .swatch(let row, _): 4 + row
        case .back: 6
        }
    }
}

extension FlowState {
    /// Over the title, before the stage select of a series in `mode`.
    func openCustomize(_ mode: GameMode) {
        customizeMode = mode
        customizations = [PlayerCustomization.saved(0), PlayerCustomization.saved(1)]
        customizeColumns = customizations.map { EnergyColour.wheel.firstIndex(of: $0.energy) ?? 0 }
        customizeCursors = [.skin, .skin]
        customizeOpen = true
    }

    func closeCustomize() {
        SoundBoard.shared.play(.menuBack)
        customizeOpen = false
    }

    func startFromCustomize() {
        SoundBoard.shared.play(SoundBoard.confirm)
        customizeOpen = false
        startSeries?(customizeMode)
    }

    /// Both sides as they'll play, the clash settled.
    var shownCustomizations: [PlayerCustomization] { PlayerCustomization.clashed(customizations) }

    /// A side's cursor moved by its stick. Across, the skin, arms and legs boxes change their
    /// pick and the picker's rows their colour; the hood steps in to START and START back out.
    func moveCustomize(_ player: Int, across: Int, down: Int) {
        let spot = customizeCursors[player]
        // Toward the middle: right for the first side, left for the second.
        let inward = player == 0 ? across : -across
        var next = spot
        if across != 0 {
            switch spot {
            case .skin, .arms, .legs:
                cycle(player, spot, by: across)
                return
            case .hood where inward > 0: next = .start
            case .start where inward < 0: next = .hood
            case .swatch(let row, let column):
                next = .swatch(row: row, column: min(max(column + across, 0), EnergyColour.wheel.count - 1))
            default: break
            }
        } else if down != 0 {
            switch min(max(spot.rung + down, 0), CustomizeSpot.back.rung) {
            case 0: next = .skin
            case 1: next = .arms
            case 2: next = .legs
            case 3: next = .hood
            case 4: next = .swatch(row: 0, column: customizeColumns[player])
            case 5: next = .swatch(row: 1, column: customizeColumns[player])
            default: next = .back
            }
        }
        guard next != spot else { return }
        place(player, next)
        SoundBoard.shared.play(SoundBoard.navigate)
    }

    /// A spot picked by a side's jump, or tapped.
    func activateCustomize(_ player: Int, _ spot: CustomizeSpot) {
        place(player, spot)
        switch spot {
        case .skin, .arms, .legs: cycle(player, spot, by: 1)
        case .hood: SoundBoard.shared.play(SoundBoard.navigate)
        case .swatch(let row, let column):
            update(player) { pick in
                pick.energy = EnergyColour.wheel[column]
                pick.deep = row == 1
            }
        case .start: startFromCustomize()
        case .back: closeCustomize()
        }
    }

    private func place(_ player: Int, _ spot: CustomizeSpot) {
        customizeCursors[player] = spot
        if case .swatch(_, let column) = spot { customizeColumns[player] = column }
    }

    private func cycle(_ player: Int, _ spot: CustomizeSpot, by step: Int) {
        update(player) { pick in
            switch spot {
            case .skin:
                let tones = HumanLook.skinTones.count
                pick.dressing.skinTone = (pick.dressing.skinTone + step % tones + tones) % tones
            case .arms: pick.dressing.sleeves.toggle()
            case .legs: pick.dressing.pants.toggle()
            default: break
            }
        }
    }

    /// A pick changed: kept, and the players drawn in it at once.
    private func update(_ player: Int, _ change: (inout PlayerCustomization) -> Void) {
        change(&customizations[player])
        customizations[player].save(as: player)
        SoundBoard.shared.play(SoundBoard.navigate)
        scene.applySavedColours()
    }
}

/// The customize screen, between the title and the stage select, on `Customize_Screen.svg`'s
/// layers (`CustomizeLayout`): each side's player on a holo-projector in its halo, both in
/// the side's energy colour; the skin, arms and legs boxes beside it and the hood under them;
/// the energy picker in the display below. START in the middle, its rings turning; RETURN
/// at the bottom. Each side's cursor is ringed in its colour.
struct CustomizeScreen: View {
    @ObservedObject var flow: FlowState
    @Environment(\.displayScale) private var displayScale

    init(flow: FlowState) {
        self.flow = flow
        _ = Onomatopoeia.registered
    }

    /// The projector's width as a share of the screen's, about the halo's beam; the player is
    /// drawn at the same art pixel.
    static let projectorWidthShare: CGFloat = 0.168
    /// The ring's middle down the halo's layer.
    static let ringShare: CGFloat = 0.9
    /// The projector's lens, the row the player stands on, and the player's feet, in art pixels.
    static let lensRow: CGFloat = 18
    static let feetRow: CGFloat = 40
    /// The rings round START, in degrees a second.
    static let spinSpeeds: (ccw: Double, cw: Double) = (24, 36)

    var body: some View {
        GeometryReader { geometry in
            let size = CustomizeScreen.fitted(geometry.size)
            ZStack(alignment: .topLeading) {
                layer("customize_ground", size)
                heading(size)
                ForEach(0..<2, id: \.self) { player in side(player, size) }
                middle(size)
                returnButton(size)
            }
            .frame(width: size.width, height: size.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .background {
            // The ground's dark edge past the 16:9, taking the taps the screen doesn't.
            Color(rgb: EsperPalette.black.shadow)
                .contentShape(Rectangle())
                .onTapGesture {}
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    /// The vector's 16:9, as large as fits.
    static func fitted(_ space: CGSize) -> CGSize {
        let width = min(space.width, space.height * CustomizeLayout.aspect)
        return CGSize(width: width, height: width / CustomizeLayout.aspect)
    }

    private func rect(_ name: String, _ size: CGSize) -> CGRect {
        let share = CustomizeLayout.frames[name] ?? .zero
        return CGRect(x: share.minX * size.width, y: share.minY * size.height, width: share.width * size.width, height: share.height * size.height)
    }

    private func picture(_ name: String) -> Image { Image(uiImage: UIImage(named: name) ?? UIImage()) }

    private func layer(_ name: String, _ size: CGSize) -> some View {
        let frame = rect(name, size)
        return picture(name).resizable().frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
    }

    /// One art pixel on screen, a whole number of the screen's own.
    private func artPixel(_ size: CGSize) -> CGFloat {
        max((size.width * CustomizeScreen.projectorWidthShare / 64 * displayScale).rounded(.down), 1) / displayScale
    }

    private func title(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.custom("Bigdex", size: size))
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 0, x: 1, y: 2)
    }

    private func subtitle(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black, radius: 0, x: 1, y: 1)
    }

    private func heading(_ size: CGSize) -> some View {
        title("CUSTOMIZE", size: size.height * 0.05)
            .position(x: size.width / 2, y: size.height * 0.078)
    }

    // MARK: A side

    @ViewBuilder
    private func side(_ player: Int, _ size: CGSize) -> some View {
        let tag = "customize_p\(player + 1)_"
        let pick = flow.customizations[player]
        let glow = flow.shownCustomizations[player].glow
        let cursor = flow.customizeCursors[player]
        let halo = rect(tag + "halo", size)
        let pixel = artPixel(size)
        let ring = CGPoint(x: halo.midX, y: halo.minY + halo.height * CustomizeScreen.ringShare)

        picture(tag + "halo").resizable()
            .colorMultiply(Color(rgb: glow))
            .frame(width: halo.width, height: halo.height)
            .position(x: halo.midX, y: halo.midY)
        if let projector = CustomizeArt.projector(glow) {
            Image(uiImage: projector).resizable().interpolation(.none)
                .frame(width: 64 * pixel, height: 64 * pixel)
                .position(ring)
        }
        if let portrait = flow.scene.customizePortrait(player: player) {
            // Standing on the lens, the second side facing the first.
            Image(uiImage: UIImage(cgImage: portrait)).resizable().interpolation(.none)
                .frame(width: 48 * pixel, height: 48 * pixel)
                .scaleEffect(x: player == 0 ? 1 : -1)
                .position(x: ring.x, y: ring.y + (CustomizeScreen.lensRow - 32 - (CustomizeScreen.feetRow - 24)) * pixel)
        }

        box(player, .skin, tag + "skin", label: "SKIN", size: size, glow: glow, cursor: cursor) { frame in
            let tone = HumanLook.skinTones[pick.dressing.skinTone]
            VStack(spacing: 0) {
                Color(rgb: PixelPalette.colours[tone.front])
                Color(rgb: PixelPalette.colours[tone.back])
            }
            .frame(width: frame.width * 0.5, height: frame.height * 0.5)
            .clipShape(RoundedRectangle(cornerRadius: frame.width * 0.08))
        }
        box(player, .arms, tag + "arms", label: "ARMS", size: size, glow: glow, cursor: cursor) { frame in
            subtitle(pick.dressing.sleeves ? "SLEEVES" : "BARE", size: frame.height * 0.16)
        }
        box(player, .legs, tag + "legs", label: "LEGS", size: size, glow: glow, cursor: cursor) { frame in
            subtitle(pick.dressing.pants ? "PANTS" : "SHORTS", size: frame.height * 0.16)
        }
        box(player, .hood, tag + "hood", label: "", size: size, glow: glow, cursor: cursor) { frame in
            if let hood = flow.scene.customizeHood(player: player) {
                Image(uiImage: UIImage(cgImage: hood)).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                    .frame(width: frame.width * 0.7, height: frame.height * 0.7)
                    .scaleEffect(x: player == 0 ? 1 : -1)
            }
        }
        if cursor == .hood {
            // What the H.O.O.D. is, over the halo's outer corner.
            VStack(alignment: player == 0 ? .leading : .trailing, spacing: size.height * 0.004) {
                title("H.O.O.D.", size: size.height * 0.05)
                subtitle("Hyper-Osmotic Output Driver", size: size.height * 0.026)
            }
            .frame(width: halo.width, height: size.height * 0.13, alignment: player == 0 ? .bottomLeading : .bottomTrailing)
            .position(x: halo.midX, y: halo.minY - size.height * 0.065)
        }
        picker(player, tag + "display", size: size, pick: pick, glow: glow, cursor: cursor)
    }

    /// One of a side's boxes, its label over it, its pick in it; ringed in the side's colour
    /// under its cursor.
    private func box(_ player: Int, _ spot: CustomizeSpot, _ name: String, label: String, size: CGSize, glow: RGB,
                     cursor: CustomizeSpot, @ViewBuilder content: (CGRect) -> some View) -> some View {
        let frame = rect(name, size)
        let lit = cursor == spot
        return ZStack {
            picture(name).resizable()
            content(frame)
            if lit {
                RoundedRectangle(cornerRadius: frame.width * 0.16)
                    .stroke(Color(rgb: glow), lineWidth: max(frame.width * 0.05, 2))
                    .padding(-frame.width * 0.06)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .overlay(alignment: .top) {
            if !label.isEmpty {
                title(label, size: frame.height * 0.2)
                    .fixedSize()
                    .offset(y: -frame.height * 0.36)
            }
        }
        .scaleEffect(lit ? TitleOverlay.cursorGrowth : 1)
        .contentShape(Rectangle())
        .onTapGesture { flow.activateCustomize(player, spot) }
        .position(x: frame.midX, y: frame.midY)
    }

    /// The energy picker in the side's display: two rows of parallelograms, the wheel's
    /// colours over the shade down each one's ramp. The pick is lined in white, the cursor's
    /// swatch in the side's colour.
    private func picker(_ player: Int, _ name: String, size: CGSize, pick: PlayerCustomization, glow: RGB, cursor: CustomizeSpot) -> some View {
        let frame = rect(name, size)
        let columns = EnergyColour.wheel.count
        let inner = CGSize(width: frame.width * 0.84, height: frame.height * 0.62)
        let cell = CGSize(width: inner.width / CGFloat(columns), height: inner.height / 2)
        return ZStack {
            picture(name).resizable()
            VStack(spacing: cell.height * 0.14) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: cell.width * 0.12) {
                        ForEach(0..<columns, id: \.self) { column in
                            let colour = EnergyColour.wheel[column]
                            let picked = pick.energy == colour && pick.deep == (row == 1)
                            let lit = cursor == .swatch(row: row, column: column)
                            Parallelogram()
                                .fill(Color(rgb: row == 0 ? colour.glow : colour.rampDown))
                                .overlay(Parallelogram().stroke(.white, lineWidth: picked ? 2 : 0))
                                .overlay(Parallelogram().stroke(Color(rgb: glow), lineWidth: lit ? 3 : 0).padding(-4))
                                .scaleEffect(lit ? 1.15 : 1)
                                .contentShape(Rectangle())
                                .onTapGesture { flow.activateCustomize(player, .swatch(row: row, column: column)) }
                        }
                    }
                    .frame(height: cell.height * 0.86)
                }
            }
            .frame(width: inner.width, height: inner.height)
            .offset(y: -frame.height * 0.08)
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    // MARK: The middle

    private func middle(_ size: CGSize) -> some View {
        let start = rect("customize_start", size)
        let lit = flow.customizeCursors.contains(.start)
        return TimelineView(.animation) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                layer("customize_start", size)
                spinning("customize_spin_ccw", size, about: start, degrees: -seconds * CustomizeScreen.spinSpeeds.ccw)
                spinning("customize_spin_cw", size, about: start, degrees: seconds * CustomizeScreen.spinSpeeds.cw)
                title("START", size: size.height * 0.04)
                    .position(x: start.midX, y: start.maxY + size.height * 0.03)
            }
            .frame(width: size.width, height: size.height)
        }
        .brightness(lit ? 0.15 : 0)
        .scaleEffect(lit ? TitleOverlay.cursorGrowth : 1, anchor: UnitPoint(x: start.midX / size.width, y: start.midY / size.height))
        .contentShape(Rectangle().path(in: start))
        .onTapGesture { flow.activateCustomize(0, .start) }
    }

    /// A ring turned about START's middle.
    private func spinning(_ name: String, _ size: CGSize, about centre: CGRect, degrees: Double) -> some View {
        let frame = rect(name, size)
        let anchor = UnitPoint(x: (centre.midX - frame.minX) / frame.width, y: (centre.midY - frame.minY) / frame.height)
        return picture(name).resizable()
            .frame(width: frame.width, height: frame.height)
            .rotationEffect(.degrees(degrees.truncatingRemainder(dividingBy: 360)), anchor: anchor)
            .position(x: frame.midX, y: frame.midY)
    }

    private func returnButton(_ size: CGSize) -> some View {
        let frame = rect("customize_return", size)
        let lit = flow.customizeCursors.contains(.back)
        return picture("customize_return").resizable()
            .frame(width: frame.width, height: frame.height)
            .brightness(lit ? 0.2 : 0)
            .scaleEffect(lit ? TitleOverlay.cursorGrowth : 1)
            .contentShape(Rectangle())
            .onTapGesture { flow.activateCustomize(0, .back) }
            .position(x: frame.midX, y: frame.midY)
    }
}

/// A swatch's shape: leaning right, a fifth of its width.
struct Parallelogram: InsettableShape {
    var lean: CGFloat = 0.2
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: inset, dy: inset)
        let shift = box.width * lean
        var path = Path()
        path.move(to: CGPoint(x: box.minX + shift, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX - shift, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> Parallelogram {
        var shape = self
        shape.inset += amount
        return shape
    }
}

/// The customize screen's pixel art.
@MainActor
enum CustomizeArt {
    private static var projectors: [RGB: UIImage] = [:]

    /// `Holo-Projector_v2`, its white in an energy colour.
    static func projector(_ glow: RGB) -> UIImage? {
        if let made = projectors[glow] { return made }
        guard let source = UIImage(named: "HoloProjector")?.cgImage else { return nil }
        let width = source.width, height = source.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for pixel in 0..<(width * height) where pixels[pixel * 4 + 3] == 255
            && pixels[pixel * 4] == 255 && pixels[pixel * 4 + 1] == 255 && pixels[pixel * 4 + 2] == 255 {
            pixels[pixel * 4] = UInt8((glow >> 16) & 0xFF)
            pixels[pixel * 4 + 1] = UInt8((glow >> 8) & 0xFF)
            pixels[pixel * 4 + 2] = UInt8(glow & 0xFF)
        }
        guard let made = context.makeImage() else { return nil }
        let image = UIImage(cgImage: made)
        projectors[glow] = image
        return image
    }

    /// Cut to what's drawn.
    static func trimmed(_ image: CGImage) -> CGImage {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var left = width, top = height, right = -1, bottom = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 0 {
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard right >= 0 else { return image }
        return image.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)) ?? image
    }
}
