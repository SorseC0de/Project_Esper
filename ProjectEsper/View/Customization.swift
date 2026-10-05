import EsperSim
import simd
import SwiftUI

/// A side's picks on the customize screen, kept between rounds and launches: the energy
/// colour and what the player wears.
struct PlayerCustomization: Codable, Equatable {
    var energy: EnergyColour
    var dressing = Dressing()

    var glow: RGB { energy.glow }
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

    /// Both sides as they play: when the two pick the same colour, the second gives way to the opposite.
    static func clashed(_ sides: [PlayerCustomization]) -> [PlayerCustomization] {
        var sides = sides
        if sides.count > 1, sides[1].energy == sides[0].energy { sides[1].energy = sides[0].energy.opposite }
        return sides
    }

    static var sides: [PlayerCustomization] { clashed([saved(0), saved(1)]) }
}

/// Where a side's cursor can stand on the customize screen. The inner arm and leg boxes, beside
/// the middle, are the front limbs'; the outer ones, past the halo, the back's.
enum CustomizeSpot: CaseIterable {
    /// The skin and the hood are pickers: across steps their colours.
    case skin, arms, legs, hood, start, back, outerArms, outerLegs
}

extension FlowState {
    /// Over the title, before the stage select of a series in `mode`, both cursors on START.
    func openCustomize(_ mode: GameMode) {
        customizeMode = mode
        customizations = [PlayerCustomization.saved(0), PlayerCustomization.saved(1)]
        customizeCursors = [.start, .start]
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

    /// A side's cursor moved by its stick. Up and down the inner column (skin, arms, legs, the
    /// hood, START, RETURN) or the outer arms and legs; out from the inner arms and legs to the
    /// outer, in to START. Across on the skin or the hood steps its colour.
    func moveCustomize(_ player: Int, across: Int, down: Int) {
        let spot = customizeCursors[player]
        // Toward the middle: right for the first side, left for the second.
        let inward = player == 0 ? across : -across
        var next: CustomizeSpot?
        if across != 0 {
            switch spot {
            case .skin, .hood:
                step(player, spot, by: across)
                return
            case .arms: next = inward > 0 ? .start : .outerArms
            case .legs: next = inward > 0 ? .start : .outerLegs
            case .outerArms: next = inward > 0 ? .arms : nil
            case .outerLegs: next = inward > 0 ? .legs : nil
            case .start: next = inward < 0 ? .hood : nil
            case .back: next = nil
            }
        } else if down != 0 {
            let column: [CustomizeSpot] = [.skin, .arms, .legs, .hood, .start, .back]
            switch spot {
            case .outerArms: next = down > 0 ? .outerLegs : .skin
            case .outerLegs: next = down > 0 ? .hood : .outerArms
            default:
                let at = column.firstIndex(of: spot) ?? 0
                next = column[min(max(at + down, 0), column.count - 1)]
            }
        }
        guard let next, next != spot else { return }
        customizeCursors[player] = next
        SoundBoard.shared.play(SoundBoard.navigate)
    }

    /// A spot picked by a side's jump, or tapped: a box ticked or unticked, a picker stepped on.
    func activateCustomize(_ player: Int, _ spot: CustomizeSpot) {
        customizeCursors[player] = spot
        switch spot {
        case .skin, .hood: step(player, spot, by: 1)
        case .arms: update(player) { $0.dressing.frontSleeve.toggle() }
        case .outerArms: update(player) { $0.dressing.backSleeve.toggle() }
        case .legs: update(player) { $0.dressing.frontBoot.toggle() }
        case .outerLegs: update(player) { $0.dressing.backBoot.toggle() }
        case .start: startFromCustomize()
        case .back: closeCustomize()
        }
    }

    /// A picker's column tapped: the skin's tone or the hood's colour outright.
    func pickCustomize(_ player: Int, _ spot: CustomizeSpot, column: Int) {
        customizeCursors[player] = spot
        update(player) { pick in
            if spot == .skin { pick.dressing.skinTone = column } else { pick.energy = EnergyColour.wheel[column] }
        }
    }

    private func step(_ player: Int, _ spot: CustomizeSpot, by step: Int) {
        update(player) { pick in
            func round(_ at: Int, _ count: Int) -> Int { (at + step % count + count) % count }
            if spot == .skin {
                pick.dressing.skinTone = round(pick.dressing.skinTone, HumanLook.skinTones.count)
            } else {
                let wheel = EnergyColour.wheel
                pick.energy = wheel[round(wheel.firstIndex(of: pick.energy) ?? 0, wheel.count)]
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
/// the side's energy colour; skin, arms and legs boxes beside it, arms and legs past it, the
/// hood under them; the skin's or the hood's colours in the display below while one is chosen.
/// CUSTOMIZE and the mode over the middle, START on it, its rings turning; RETURN at the
/// bottom. Each side's cursor lights its box's line in its colour. Energy glows.
struct CustomizeScreen: View {
    @ObservedObject var flow: FlowState
    @Environment(\.displayScale) private var displayScale
    /// The tuning sliders: the projector's and the player's height, in art pixels up, and the
    /// art pixels each is drawn at, in quarters.
    @AppStorage("esper.customize.projectorY") private var projectorY = 0.0
    @AppStorage("esper.customize.projectorScale") private var projectorScale = 0.5
    @AppStorage("esper.customize.playerY") private var playerY = 0.0
    @AppStorage("esper.customize.playerScale") private var playerScale = 3.0
    @AppStorage("esper.customize.tuningShown") private var tuningShown = true

    init(flow: FlowState) {
        self.flow = flow
        _ = Onomatopoeia.registered
    }

    /// An art pixel as a share of the screen's width, before the sliders' scales.
    static let artPixelShare: CGFloat = 0.168 / 64
    /// The ring's middle down the halo's layer.
    static let ringShare: CGFloat = 0.9
    /// The halo's beam, clear at its top, whole this far down.
    static let haloFadeEnd: CGFloat = 0.75
    /// The projector's lens, the row the player stands on, and the player's feet, in art pixels.
    static let lensRow: CGFloat = 18
    static let feetRow: CGFloat = 40
    /// The rings round START, in degrees a second.
    static let spinSpeeds: (ccw: Double, cw: Double) = (24, 36)
    /// A picker's colour: its share of each column, over the accent.
    static let swatchShare: CGFloat = 0.7
    /// The small boxes' line, blue's second (the cyan); the hood's, purple's first as the vector's cyan went.
    static let smallBoxLine: RGB = EsperPalette.blue.light
    static let hoodLine: RGB = EsperPalette.purple.highlight

    var body: some View {
        GeometryReader { geometry in
            let size = CustomizeScreen.fitted(geometry.size)
            ZStack(alignment: .topLeading) {
                layer("customize_ground", size)
                heading(size)
                ForEach(0..<2, id: \.self) { player in side(player, size) }
                middle(size)
                returnButton(size)
                tuning(size)
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

    /// A layer's place, or, `mirroredAbout` an x, its mirror image's.
    private func rect(_ name: String, _ size: CGSize, mirroredAbout axis: CGFloat? = nil) -> CGRect {
        let share = CustomizeLayout.frames[name] ?? .zero
        var frame = CGRect(x: share.minX * size.width, y: share.minY * size.height, width: share.width * size.width, height: share.height * size.height)
        if let axis { frame.origin.x = 2 * axis - frame.maxX }
        return frame
    }

    private func picture(_ name: String) -> Image { Image(uiImage: UIImage(named: name) ?? UIImage()) }

    private func layer(_ name: String, _ size: CGSize) -> some View {
        let frame = rect(name, size)
        return picture(name).resizable().frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
    }

    /// Screen points for `pixels` art pixels, a whole number of the screen's own.
    private func artPixel(_ size: CGSize, times pixels: CGFloat) -> CGFloat {
        max((size.width * CustomizeScreen.artPixelShare * pixels * displayScale).rounded(), 1) / displayScale
    }

    private func title(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.custom("Bigdex", size: size))
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 0, x: 1, y: 2)
            .fixedSize()
    }

    /// Lettered as FLO is when it's lit, in Bigdex: gold's first over the cyan, outlined in plum
    /// and purple. `height` is its cap height.
    private func litTitle(_ text: String, height: CGFloat) -> some View {
        let word = Onomatopoeia.picture(text, face: .englishDex, colours: FloTuning.colours, growsLeft: true, height: height)
        return Image(uiImage: word.image).resizable().aspectRatio(contentMode: .fit).frame(height: word.height)
    }

    private func subtitle(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black, radius: 0, x: 1, y: 1)
    }

    /// CUSTOMIZE on the heading's plate, and the series' mode large under it.
    @ViewBuilder
    private func heading(_ size: CGSize) -> some View {
        litTitle("CUSTOMIZE", height: size.height * 0.025)
            .position(x: size.width / 2, y: size.height * 0.078)
        title(flow.customizeMode == .rounds ? "BEST OF 7" : "47", size: size.height * 0.08)
            .position(x: size.width / 2, y: size.height * 0.19)
    }

    // MARK: A side

    @ViewBuilder
    private func side(_ player: Int, _ size: CGSize) -> some View {
        let tag = "customize_p\(player + 1)_"
        let pick = flow.shownCustomizations[player]
        let glow = pick.glow
        let cursor = flow.customizeCursors[player]
        let halo = rect(tag + "halo", size)
        let ring = CGPoint(x: halo.midX, y: halo.minY + halo.height * CustomizeScreen.ringShare)
        let base = size.width * CustomizeScreen.artPixelShare
        let projectorPixel = artPixel(size, times: projectorScale)
        let playerPixel = artPixel(size, times: playerScale)
        let projectorAt = CGPoint(x: ring.x, y: ring.y - projectorY * base)
        // The first side's front limbs are its right; the second, facing the other way, its left.
        let front = player == 0 ? "R" : "L", back = player == 0 ? "L" : "R"

        // The beam fading out to nothing at its top.
        picture(tag + "halo").resizable()
            .colorMultiply(Color(rgb: glow))
            .frame(width: halo.width, height: halo.height)
            .energyGlow(radius: halo.width * 0.02)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: CustomizeScreen.haloFadeEnd)],
                                 startPoint: .top, endPoint: .bottom))
            .position(x: halo.midX, y: halo.midY)
        if let projector = CustomizeArt.projector(glow), let lit = CustomizeArt.projectorEnergy(glow) {
            ZStack {
                Image(uiImage: projector).resizable().interpolation(.none)
                Image(uiImage: lit).resizable().interpolation(.none)
                    .blur(radius: projectorPixel * 3)
                    .blendMode(.plusLighter)
                    .opacity(CustomizeArt.glowStrength)
            }
            .frame(width: 64 * projectorPixel, height: 64 * projectorPixel)
            .position(projectorAt)
        }
        if let portrait = flow.scene.customizePortrait(player: player) {
            // Standing on the lens, the second side facing the first.
            let lens = projectorAt.y + (CustomizeScreen.lensRow - 32) * projectorPixel
            let side = (48 + 2 * CustomizeFigure.margin) * playerPixel
            CustomizeFigure(portrait: portrait, look: pick.look, pixel: playerPixel, mirrored: player == 1)
                .frame(width: side, height: side)
                .allowsHitTesting(false)
                .position(x: ring.x, y: lens - (CustomizeScreen.feetRow - 24) * playerPixel - playerY * base)
        }

        box(player, .skin, tag + "skin", label: "SKIN", size: size, glow: glow, cursor: cursor) { frame in
            VStack(spacing: 0) {
                Color(rgb: PixelPalette.colours[pick.dressing.tone.front])
                Color(rgb: PixelPalette.colours[pick.dressing.tone.back])
            }
            .frame(width: frame.width * 0.5, height: frame.height * 0.5)
            .clipShape(RoundedRectangle(cornerRadius: frame.width * 0.08))
        }
        box(player, .arms, tag + "arms", label: "\(front) ARM", size: size, glow: glow, cursor: cursor) { tick(pick.dressing.frontSleeve, $0) }
        box(player, .legs, tag + "legs", label: "\(front) LEG", size: size, glow: glow, cursor: cursor) { tick(pick.dressing.frontBoot, $0) }
        box(player, .outerArms, tag + "arms", mirroredAbout: halo.midX, label: "\(back) ARM", size: size, glow: glow, cursor: cursor) {
            tick(pick.dressing.backSleeve, $0)
        }
        box(player, .outerLegs, tag + "legs", mirroredAbout: halo.midX, label: "\(back) LEG", size: size, glow: glow, cursor: cursor) {
            tick(pick.dressing.backBoot, $0)
        }
        box(player, .hood, tag + "hood", label: "H.O.O.D", size: size, glow: glow, cursor: cursor) { frame in
            if let hood = flow.scene.customizeHood(player: player) {
                Image(uiImage: UIImage(cgImage: hood)).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                    .frame(width: frame.width * 0.7, height: frame.height * 0.7)
                    .scaleEffect(x: player == 0 ? 1 : -1)
            }
        }
        if cursor == .skin || cursor == .hood {
            picker(player, tag + "display", size: size, spot: cursor, pick: pick)
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
    }

    /// A box's tick: empty, or a check.
    @ViewBuilder
    private func tick(_ on: Bool, _ frame: CGRect) -> some View {
        if on {
            Image(systemName: "checkmark")
                .font(.system(size: frame.height * 0.5, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 0, x: 1, y: 2)
        }
    }

    /// One of a side's boxes: its fill, what's in it, its line, and its label under it. Under
    /// its side's cursor the line thickens and lights in the side's colour, glowing.
    @ViewBuilder
    private func box(_ player: Int, _ spot: CustomizeSpot, _ name: String, mirroredAbout axis: CGFloat? = nil, label: String,
                     size: CGSize, glow: RGB, cursor: CustomizeSpot, @ViewBuilder content: (CGRect) -> some View) -> some View {
        let flip: CGFloat = axis == nil ? 1 : -1
        let fill = rect(name, size, mirroredAbout: axis)
        let line = rect(name + "_line", size, mirroredAbout: axis)
        let lit = cursor == spot
        picture(name).resizable().scaleEffect(x: flip)
            .frame(width: fill.width, height: fill.height)
            .position(x: fill.midX, y: fill.midY)
        content(fill)
            .position(x: fill.midX, y: fill.midY)
        if lit {
            let thick = rect(name + "_lit", size, mirroredAbout: axis)
            picture(name + "_lit").resizable().scaleEffect(x: flip)
                .colorMultiply(Color(rgb: glow))
                .frame(width: thick.width, height: thick.height)
                .energyGlow(radius: thick.width * 0.06)
                .position(x: thick.midX, y: thick.midY)
        } else {
            picture(name + "_line").resizable().scaleEffect(x: flip)
                .colorMultiply(Color(rgb: spot == .hood ? CustomizeScreen.hoodLine : CustomizeScreen.smallBoxLine))
                .frame(width: line.width, height: line.height)
                .position(x: line.midX, y: line.midY)
        }
        title(label, size: line.height * 0.4)
            .position(x: line.midX, y: line.maxY + line.height * 0.26)
        Color.clear
            .frame(width: line.width, height: line.height)
            .contentShape(Rectangle())
            .onTapGesture { flow.activateCustomize(player, spot) }
            .position(x: line.midX, y: line.midY)
    }

    /// The skin's or the hood's colours in the side's display, while one is chosen: a column a
    /// colour, leaning, the colour over an accent corner to corner (a skin's back tone, a
    /// colour's shade down its ramp); the picked column lined in white. The display's bar in
    /// the side's colour, glowing.
    @ViewBuilder
    private func picker(_ player: Int, _ name: String, size: CGSize, spot: CustomizeSpot, pick: PlayerCustomization) -> some View {
        let frame = rect(name, size)
        let bar = rect(name + "_bar", size)
        let columns: [(top: RGB, accent: RGB)] = spot == .skin
            ? HumanLook.skinTones.map { (PixelPalette.colours[$0.front], PixelPalette.colours[$0.back]) }
            : EnergyColour.wheel.map { ($0.glow, $0.rampDown) }
        let picked = spot == .skin ? pick.dressing.skinTone : (EnergyColour.wheel.firstIndex(of: flow.customizations[player].energy) ?? 0)
        let inner = CGSize(width: frame.width * 0.84, height: frame.height * 0.6)
        let split = CustomizeScreen.swatchShare
        picture(name).resizable()
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        picture(name + "_bar").resizable()
            .colorMultiply(Color(rgb: pick.glow))
            .frame(width: bar.width, height: bar.height)
            .energyGlow(radius: bar.height * 0.5)
            .position(x: bar.midX, y: bar.midY)
        HStack(spacing: inner.width / CGFloat(columns.count) * 0.12) {
            ForEach(columns.indices, id: \.self) { index in
                ZStack {
                    LeaningBand(from: 0, to: split).fill(Color(rgb: columns[index].top))
                    LeaningBand(from: split, to: 1).fill(Color(rgb: columns[index].accent))
                    LeaningBand(from: 0, to: 1).stroke(.white, lineWidth: index == picked ? 2.5 : 0)
                }
                .scaleEffect(index == picked ? 1.12 : 1)
                .contentShape(Rectangle())
                .onTapGesture { flow.pickCustomize(player, spot, column: index) }
            }
        }
        .frame(width: inner.width, height: inner.height)
        .position(x: frame.midX, y: frame.midY - frame.height * 0.08)
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
                litTitle("START", height: size.height * 0.035)
                    .position(x: start.midX, y: start.midY)
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

    // MARK: Tuning

    /// The projector's and the player's sliders, low in the middle: their height in art pixels
    /// up, and their scale in quarters. Kept between launches.
    private func tuning(_ size: CGSize) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            tuningButton(tuningShown ? "HIDE" : "TUNE") { tuningShown.toggle() }
            if tuningShown {
                tuningRow("PROJ Y", value: $projectorY, step: 1, range: -64...64, format: "%.0f")
                tuningRow("PROJ SCALE", value: $projectorScale, step: 0.25, range: 0.25...8, format: "×%.2f")
                tuningRow("PLAYER Y", value: $playerY, step: 1, range: -64...64, format: "%.0f")
                tuningRow("PLAYER SCALE", value: $playerScale, step: 0.25, range: 0.25...8, format: "×%.2f")
            }
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundStyle(.white)
        .padding(6)
        .background(Color.black.opacity(tuningShown ? 0.5 : 0), in: RoundedRectangle(cornerRadius: 6))
        .position(x: size.width / 2, y: size.height * 0.79)
    }

    private func tuningRow(_ name: String, value: Binding<Double>, step: Double, range: ClosedRange<Double>, format: String) -> some View {
        HStack(spacing: 4) {
            Text(name).frame(width: 84, alignment: .leading)
            tuningButton("−") { value.wrappedValue = max(value.wrappedValue - step, range.lowerBound) }
            Text(String(format: format, value.wrappedValue)).monospacedDigit().frame(width: 44)
            tuningButton("+") { value.wrappedValue = min(value.wrappedValue + step, range.upperBound) }
        }
    }

    private func tuningButton(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .noSystemFocus()
    }
}

extension View {
    /// Energy's bloom: a blurred copy laid over it, added and dimmed, as the glow does in play.
    func energyGlow(radius: CGFloat) -> some View {
        overlay(blur(radius: radius).blendMode(.plusLighter).opacity(CustomizeArt.glowStrength))
    }
}

/// A band across a column leaning right, a fifth of its width over its height, from `from` to
/// `to` of the way down: bands of one column meet corner to corner.
struct LeaningBand: Shape {
    var from: CGFloat
    var to: CGFloat
    var lean: CGFloat = 0.2

    func path(in rect: CGRect) -> Path {
        let shift = rect.width * lean
        // The left edge at a share of the way down; the right a column's width less the lean along.
        func left(_ down: CGFloat) -> CGFloat { rect.minX + shift * (1 - down) }
        let width = rect.width - shift
        var path = Path()
        path.move(to: CGPoint(x: left(from), y: rect.minY + rect.height * from))
        path.addLine(to: CGPoint(x: left(from) + width, y: rect.minY + rect.height * from))
        path.addLine(to: CGPoint(x: left(to) + width, y: rect.minY + rect.height * to))
        path.addLine(to: CGPoint(x: left(to), y: rect.minY + rect.height * to))
        path.closeSubpath()
        return path
    }
}

/// A side's player on the customize screen, drawn a frame at a time: the figure, its strings
/// floating off the hood as FloState's do, one back and the shorter forward, and the cubes off
/// its head and shoes, as in play; what's energy glowing. In art pixels, `margin` round the figure's 48 for the strings and cubes.
struct CustomizeFigure: View {
    let portrait: SpriteLibrary.Portrait
    let look: Look
    /// Screen points an art pixel.
    let pixel: CGFloat
    let mirrored: Bool
    @State private var motion = CustomizeFigureMotion()

    static let margin: CGFloat = 24

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                motion.advance(to: timeline.date.timeIntervalSinceReferenceDate, portrait: portrait, look: look)
                var context = context
                if mirrored {
                    context.translateBy(x: size.width, y: 0)
                    context.scaleBy(x: -1, y: 1)
                }
                let margin = CustomizeFigure.margin
                /// An art point, y up from the figure's bottom left, on the canvas.
                func spot(_ point: CGPoint) -> CGPoint {
                    CGPoint(x: (margin + point.x) * pixel, y: (margin + 48 - point.y) * pixel)
                }
                for cube in motion.cubes where cube.behind { draw(cube, in: context, at: spot(cube.position)) }
                let figure = Image(decorative: portrait.image, scale: 1).interpolation(.none)
                context.draw(figure, in: CGRect(x: margin * pixel, y: margin * pixel, width: 48 * pixel, height: 48 * pixel))
                let plain = Color(rgb: look.energyTone(luminance: SpriteLibrary.hoodLevel))
                let accent = Color(rgb: look.energyTone(luminance: GameScene.stringAccentLuminance * SpriteLibrary.hoodLevel))
                for string in motion.strings {
                    let at = spot(string.point)
                    context.fill(Path(CGRect(x: at.x - pixel / 2, y: at.y - pixel / 2, width: pixel, height: pixel)), with: .color(string.accent ? accent : plain))
                }
                for cube in motion.cubes where !cube.behind { draw(cube, in: context, at: spot(cube.position)) }
                // The glow: what's energy again, blurred and added.
                var glowing = context
                glowing.blendMode = .plusLighter
                glowing.opacity = CustomizeArt.glowStrength
                glowing.drawLayer { layer in
                    layer.addFilter(.blur(radius: pixel * CustomizeArt.glowPixels))
                    layer.draw(Image(decorative: portrait.glowing, scale: 1).interpolation(.none),
                               in: CGRect(x: margin * pixel, y: margin * pixel, width: 48 * pixel, height: 48 * pixel))
                    for string in motion.strings {
                        let at = spot(string.point)
                        layer.fill(Path(CGRect(x: at.x - pixel / 2, y: at.y - pixel / 2, width: pixel, height: pixel)), with: .color(string.accent ? accent : plain))
                    }
                    for cube in motion.cubes { draw(cube, in: layer, at: spot(cube.position)) }
                }
            }
        }
    }

    /// A cube as the Metal layer shades one: its faces toward us, each its colour lit toward
    /// white where it faces the light, never dark.
    private func draw(_ cube: CustomizeFigureMotion.Cube, in context: GraphicsContext, at centre: CGPoint) {
        let share = cube.age / cube.life
        let side = Float(cube.size * pixel * (share < 0.45 ? 1 : (share < 0.75 ? 0.66 : 0.33)))
        let alpha = share < 0.85 ? 0.9 : 0.9 * (1 - share) / 0.15
        let light = simd_normalize(SIMD3<Float>(-0.4, 0.7, 0.6))
        let base = SIMD3<Float>(Float((cube.colour >> 16) & 0xFF), Float((cube.colour >> 8) & 0xFF), Float(cube.colour & 0xFF)) / 255
        let axes: [SIMD3<Float>] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        var faces: [(depth: Float, corners: [CGPoint], colour: Color)] = []
        for axis in axes {
            for sign: Float in [1, -1] {
                let normal = cube.orientation.act(axis * sign)
                guard normal.z > 0 else { continue }
                let others = axes.filter { $0 != axis }.map { cube.orientation.act($0) * side / 2 }
                let middle = normal * side / 2
                let corners = [middle - others[0] - others[1], middle + others[0] - others[1],
                               middle + others[0] + others[1], middle - others[0] + others[1]]
                    .map { CGPoint(x: centre.x + CGFloat($0.x), y: centre.y - CGFloat($0.y)) }
                let lit = max(simd_dot(normal, light), 0)
                let mixed = simd_mix(base * (0.85 + 0.15 * lit), SIMD3<Float>(repeating: 1), SIMD3<Float>(repeating: 0.35 * lit * lit))
                faces.append((normal.z, corners, Color(red: Double(mixed.x), green: Double(mixed.y), blue: Double(mixed.z)).opacity(alpha)))
            }
        }
        for face in faces.sorted(by: { $0.depth < $1.depth }) {
            var path = Path()
            path.addLines(face.corners)
            path.closeSubpath()
            context.fill(path, with: .color(face.colour))
        }
    }
}

/// The customize figure's strings and cubes, stepped at the game's 60 a second.
final class CustomizeFigureMotion {
    struct Cube {
        var position: CGPoint
        var velocity: CGVector
        var age = 0.0
        var life: Double
        var orientation: simd_quatf
        var spin: SIMD3<Float>
        var size: CGFloat
        var colour: RGB
        var behind: Bool
    }

    private let stringMotion = HoodStrings.Motion()
    private(set) var strings: [(point: CGPoint, accent: Bool)] = []
    private(set) var cubes: [Cube] = []
    private var credit: [BodyPart: Double] = [:]
    private var last: Double?
    private var owed = 0.0

    /// The head's cubes a second, the shoes' each; the game's at no FLO.
    static let headCubeRate = 24.0
    static let shoeCubeRate = Double(ParticleLook.legCubeRate)

    func advance(to time: Double, portrait: SpriteLibrary.Portrait, look: Look) {
        let step = 1.0 / 60
        owed += last.map { min(time - $0, 0.1) } ?? step
        last = time
        while owed >= step {
            owed -= step
            tick(time: time, step: step, portrait: portrait, look: look)
        }
    }

    private func tick(time: Double, step: Double, portrait: SpriteLibrary.Portrait, look: Look) {
        // The strings off the hood's own anchors, wherever the hood went on the figure, floating
        // as FloState's do: one back, the shorter forward.
        let anchors = HoodStrings.anchorPixels.map { pixel in
            CGPoint(x: pixel.x + 0.5 + portrait.hoodOffset.x, y: 48 - (pixel.y + 0.5 + portrait.hoodOffset.y))
        }
        strings = stringMotion.step(anchors: anchors, style: HoodStrings.floState, facing: 1, scale: 1, time: time)

        // Cubes off the head's crown and the shoes, as a human's are in play.
        let wind = sin(time * 2 * .pi * ParticleLook.swayPerSecond) * Double(ParticleLook.flowSpeed)
        let sources: [(part: BodyPart, rate: Double, size: Float, spread: Float, lift: CGFloat)] = [
            (.head, CustomizeFigureMotion.headCubeRate, ParticleLook.cubeSize, ParticleLook.cubeSpread, GameScene.crownLift),
            (.frontFoot, CustomizeFigureMotion.shoeCubeRate, ParticleLook.legCubeSize, ParticleLook.legCubeSpread, 0),
            (.backFoot, CustomizeFigureMotion.shoeCubeRate, ParticleLook.legCubeSize, ParticleLook.legCubeSpread, 0),
        ]
        for source in sources {
            guard let centre = portrait.centres[source.part] else { continue }
            credit[source.part, default: 0] += source.rate * step
            while credit[source.part, default: 0] >= 1 {
                credit[source.part, default: 0] -= 1
                let spread = CGFloat(source.spread)
                let angle = Double.pi / 2 + Double.random(in: -Double.pi / 28...Double.pi / 28)
                let speed = 24 + Double.random(in: -2...2)
                let axis = simd_normalize(SIMD3<Float>.random(in: -1...1) + SIMD3<Float>(0, 0, 0.001))
                cubes.append(Cube(position: CGPoint(x: centre.x + .random(in: -spread...spread),
                                                    y: 48 - centre.y + source.lift + .random(in: -spread / 2...spread / 2)),
                                  velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                                  life: Double(ParticleLook.cubeTrail) / speed + .random(in: -0.05...0.05),
                                  orientation: simd_quatf(angle: .random(in: 0..<(2 * .pi)), axis: axis),
                                  spin: SIMD3<Float>.random(in: -ParticleLook.cubeSpin...ParticleLook.cubeSpin),
                                  // The head's in the energy's colour; the shoes' in theirs.
                                  size: CGFloat(source.size), colour: source.part == .head ? look.glow : (look.colours[source.part] ?? look.glow),
                                  behind: source.part.isBack))
            }
        }
        cubes = cubes.compactMap { cube in
            var cube = cube
            cube.age += step
            guard cube.age < cube.life else { return nil }
            let rate = simd_length(cube.spin)
            if rate > 0 { cube.orientation = simd_normalize(simd_quatf(angle: rate * Float(step), axis: cube.spin / rate) * cube.orientation) }
            cube.velocity.dx += wind * step
            cube.velocity.dy += 10 * step
            cube.position = CGPoint(x: cube.position.x + cube.velocity.dx * step, y: cube.position.y + cube.velocity.dy * step)
            return cube
        }
    }
}

/// The customize screen's pixel art.
@MainActor
enum CustomizeArt {
    private static var projectors: [RGB: UIImage] = [:]
    private static var projectorEnergies: [RGB: UIImage] = [:]
    /// The glow's copy, added over what glows at this strength; the figure's blurred this many art pixels.
    static let glowStrength = 0.6
    static let glowPixels: CGFloat = 2.5

    /// The projector's white alone, in an energy colour: what of it glows.
    static func projectorEnergy(_ glow: RGB) -> UIImage? {
        if let made = projectorEnergies[glow] { return made }
        guard let image = recoloured(glow, keepingOnlyWhite: true) else { return nil }
        projectorEnergies[glow] = image
        return image
    }

    /// `Holo-Projector_v2`, its white in an energy colour.
    static func projector(_ glow: RGB) -> UIImage? {
        if let made = projectors[glow] { return made }
        guard let image = recoloured(glow, keepingOnlyWhite: false) else { return nil }
        projectors[glow] = image
        return image
    }

    private static func recoloured(_ glow: RGB, keepingOnlyWhite: Bool) -> UIImage? {
        guard let source = UIImage(named: "HoloProjector")?.cgImage else { return nil }
        let width = source.width, height = source.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for pixel in 0..<(width * height) {
            let index = pixel * 4
            let white = pixels[index + 3] == 255 && pixels[index] == 255 && pixels[index + 1] == 255 && pixels[index + 2] == 255
            if white {
                pixels[index] = UInt8((glow >> 16) & 0xFF)
                pixels[index + 1] = UInt8((glow >> 8) & 0xFF)
                pixels[index + 2] = UInt8(glow & 0xFF)
            } else if keepingOnlyWhite {
                for channel in 0..<4 { pixels[index + channel] = 0 }
            }
        }
        return context.makeImage().map { UIImage(cgImage: $0) }
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
