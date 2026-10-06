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
enum CustomizeSpot: Hashable {
    case skin, arms, legs, hood, start, back, outerArms, outerLegs
    /// On a column of the skin's or the hood's picker, in the display.
    case skinPicker(Int), hoodPicker(Int)

    /// The box whose picker this is, or which is its own.
    var owner: CustomizeSpot {
        switch self {
        case .skinPicker: .skin
        case .hoodPicker: .hood
        default: self
        }
    }
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
    /// hood, START, RETURN, and from the skin up round to START) or the outer arms and legs; out
    /// from the inner arms and legs to the outer, in to START; out from the skin or the hood into
    /// its picker, at the picked colour. In a picker, across along the colours (past the inner
    /// end back to its box) and up back to its box.
    func moveCustomize(_ player: Int, across: Int, down: Int) {
        let spot = customizeCursors[player]
        // Toward the middle: right for the first side, left for the second.
        let inward = player == 0 ? across : -across
        var next: CustomizeSpot?
        if across != 0 {
            switch spot {
            case .skin, .hood: next = inward > 0 ? .start : enterPicker(player, spot)
            case .arms: next = inward > 0 ? .start : .outerArms
            case .legs: next = inward > 0 ? .start : .outerLegs
            case .outerArms: next = inward > 0 ? .arms : nil
            case .outerLegs: next = inward > 0 ? .legs : nil
            case .start: next = inward < 0 ? .hood : nil
            case .back: next = nil
            case .skinPicker(let column), .hoodPicker(let column):
                let count = spot.owner == .skin ? HumanLook.skinTones.count : EnergyColour.wheel.count
                let moved = column + across
                if (0..<count).contains(moved) {
                    next = spot.owner == .skin ? .skinPicker(moved) : .hoodPicker(moved)
                } else if inward > 0 {
                    next = spot.owner
                }
            }
        } else if down != 0 {
            let column: [CustomizeSpot] = [.skin, .arms, .legs, .hood, .start, .back]
            switch spot {
            case .outerArms: next = down > 0 ? .outerLegs : .skin
            case .outerLegs: next = down > 0 ? .hood : .outerArms
            case .skin where down < 0: next = .start
            case .skinPicker, .hoodPicker: next = down < 0 ? spot.owner : nil
            default:
                let at = column.firstIndex(of: spot) ?? 0
                next = column[min(max(at + down, 0), column.count - 1)]
            }
        }
        guard let next, next != spot else { return }
        customizeCursors[player] = next
        SoundBoard.shared.play(SoundBoard.navigate)
    }

    /// Into a box's picker, on the colour it has.
    private func enterPicker(_ player: Int, _ box: CustomizeSpot) -> CustomizeSpot {
        let pick = customizations[player]
        return box == .skin ? .skinPicker(pick.dressing.skinTone) : .hoodPicker(EnergyColour.wheel.firstIndex(of: pick.energy) ?? 0)
    }

    /// Out of a picker, back to its box: B there.
    func leaveCustomizePicker(_ player: Int) -> Bool {
        let spot = customizeCursors[player]
        guard spot.owner != spot else { return false }
        customizeCursors[player] = spot.owner
        SoundBoard.shared.play(.menuBack)
        return true
    }

    /// The displayed front limb's sleeve and boot: the second side is shown facing left, so its
    /// front is the dressing's back (front and back are as faced right).
    private func frontIsBack(_ player: Int) -> Bool { player == 1 }

    /// A spot picked by a side's jump, or tapped: a box ticked or unticked, a box's picker
    /// entered, a colour picked. The outer arm and leg boxes are the shown front limbs', the
    /// inner the back's.
    func activateCustomize(_ player: Int, _ spot: CustomizeSpot) {
        customizeCursors[player] = spot
        let flipped = frontIsBack(player)
        switch spot {
        case .skin, .hood:
            customizeCursors[player] = enterPicker(player, spot)
            SoundBoard.shared.play(SoundBoard.navigate)
        case .outerArms: update(player) { if flipped { $0.dressing.backSleeve.toggle() } else { $0.dressing.frontSleeve.toggle() } }
        case .arms: update(player) { if flipped { $0.dressing.frontSleeve.toggle() } else { $0.dressing.backSleeve.toggle() } }
        case .outerLegs: update(player) { if flipped { $0.dressing.backBoot.toggle() } else { $0.dressing.frontBoot.toggle() } }
        case .legs: update(player) { if flipped { $0.dressing.frontBoot.toggle() } else { $0.dressing.backBoot.toggle() } }
        case .skinPicker(let column): update(player) { $0.dressing.skinTone = column }
        case .hoodPicker(let column): update(player) { $0.energy = EnergyColour.wheel[column] }
        case .start: startFromCustomize()
        case .back: closeCustomize()
        }
    }

    /// Whether a side's arm or leg box is ticked, by the same reckoning.
    func customizeTicked(_ player: Int, _ spot: CustomizeSpot) -> Bool {
        let dressing = customizations[player].dressing
        let shownFront = spot == .outerArms || spot == .outerLegs
        let front = shownFront != frontIsBack(player)
        switch spot {
        case .arms, .outerArms: return front ? dressing.frontSleeve : dressing.backSleeve
        default: return front ? dressing.frontBoot : dressing.backBoot
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
    @AppStorage("esper.customize.tuningShown") private var tuningShown = true
    /// The hooded head on the figure: art pixels right and up, and its size in tenths.
    @AppStorage("esper.customize.headX") private var headX = 1.0
    @AppStorage("esper.customize.headY") private var headY = 1.0
    @AppStorage("esper.customize.headScale") private var headScale = 1.0
    /// The colour's name's middle over the player's middle, in art pixels.
    @AppStorage("esper.customize.nameY.2") private var nameY = 26.0
    /// The face of everything but START and the big H.O.O.D., one of the finalists (`CustomizeFont`).
    @AppStorage("esper.customize.font.2") private var fontPick = CustomizeFont.bmArmy.rawValue
    private var font: CustomizeFont { CustomizeFont(rawValue: fontPick).flatMap { CustomizeFont.finalists.contains($0) ? $0 : nil } ?? .bmArmy }
    /// The space between the side labels' letters, stacked one over the next, in points of the
    /// screen at 1080 high.
    @AppStorage("esper.customize.letterGap") private var letterGap = 0.0

    init(flow: FlowState) {
        self.flow = flow
        _ = Onomatopoeia.registered
    }

    /// An art pixel as a share of the screen's width; the projector is drawn at a quarter of it,
    /// 7 down from the ring, and the player at twice it, 6 up from the lens.
    static let artPixelShare: CGFloat = 0.168 / 64
    static let projectorScale: CGFloat = 0.25
    static let projectorY: CGFloat = -7
    static let playerScale: CGFloat = 2
    static let playerY: CGFloat = 6
    /// The ring's middle down the halo's layer.
    static let ringShare: CGFloat = 0.9
    /// The halo's beam, clear at its top, whole this far down.
    static let haloFadeEnd: CGFloat = 0.75
    /// The projector's lens, the row the player stands on, and the player's feet, in art pixels.
    static let lensRow: CGFloat = 18
    static let feetRow: CGFloat = 40
    /// The rings round START, in degrees a second.
    static let spinSpeeds: (ccw: Double, cw: Double) = (24, 36)
    /// A box's label's size, a share of the box's height: H.O.O.D.'s under it, and SKIN's,
    /// SLEEVE's and BRACER's, their letters stacked down its outer side.
    static let labelShare: CGFloat = 0.4
    static let sideLabelShare: CGFloat = 0.25
    /// The gap between a box and its side label, a share of the box's width.
    static let sideLabelGapShare: CGFloat = 0.08
    /// "MODEL" before the colour's name, and the widest the name may be, longer ones scaled down
    /// to it, as a share of the halo's width.
    static let nameMaxWidthShare: CGFloat = 0.35
    /// The lines from the arm and leg boxes to the player: as thick as the screen's own lines,
    /// their end dots as big as theirs, shares of the screen's height.
    static let connectorWidthShare: CGFloat = 0.0032
    static let connectorDotShare: CGFloat = 0.0041
    /// The words under H.O.O.D.'s letters, and MODEL, as a share of the screen's height.
    static let hoodWordShare: CGFloat = 0.018
    /// What H.O.O.D. stands for, a word a letter.
    static let hoodWords = ["Hyper-", "Osmotic", "Output", "Driver"]
    /// The space between CUSTOMIZE's letters, a share of each one's size.
    static let headingSpacing: CGFloat = 0.08
    /// The ground: the vector's gradient (in the menus' colours), out to the screen's edges, and
    /// its grid, a cell 0.0139 of the 16:9's width, bowed out so the cells grow toward the corners.
    static let groundStops: [Gradient.Stop] = [.init(color: Color(rgb: EsperPalette.purple.body), location: 0),
                                                .init(color: Color(rgb: EsperPalette.plum.light), location: 0.42),
                                                .init(color: Color(rgb: EsperPalette.black.shadow), location: 1)]
    /// Two glows over it, gold up and to the left, blue down and to the right, each a tenth of the
    /// width off the middle, at three quarters the ground's size and half seen.
    static let ground2Stops: [Gradient.Stop] = [.init(color: Color(rgb: EsperPalette.gold.body), location: 0),
                                                .init(color: Color(.clear), location: 1)]
    static let ground3Stops: [Gradient.Stop] = [.init(color: Color(rgb: EsperPalette.blue.body), location: 0),
                                                .init(color: Color(.clear), location: 1)]
    static let glowSizeShare: CGFloat = 0.75
    static let glowOpacity = 0.5
    static let groundRadiusShare: CGFloat = 0.42
    static let gridCellShare: CGFloat = 0.0139
    static let gridBow: CGFloat = 0.35
    static let gridOpacity = 0.4
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
            // The ground, to the screen's edges, taking the taps the screen doesn't.
            GeometryReader { geometry in
                ground(geometry.size)
            }
            .contentShape(Rectangle())
            .onTapGesture {}
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    /// The gradient and the bowed grid over the whole screen.
    private func ground(_ screen: CGSize) -> some View {
        let fitted = CustomizeScreen.fitted(screen)
        return ZStack {
            Color(rgb: EsperPalette.black.shadow)
            RadialGradient(stops: CustomizeScreen.groundStops, center: .center, startRadius: 0,
                           endRadius: fitted.width * CustomizeScreen.groundRadiusShare)
            RadialGradient(stops: CustomizeScreen.ground2Stops, center: .center, startRadius: 0,
                           endRadius: fitted.width * CustomizeScreen.groundRadiusShare * CustomizeScreen.glowSizeShare)
            .opacity(CustomizeScreen.glowOpacity)
            .offset(x: -(fitted.width * 0.2), y: -(fitted.width * 0.1))
            RadialGradient(stops: CustomizeScreen.ground3Stops, center: .center, startRadius: 0,
                           endRadius: fitted.width * CustomizeScreen.groundRadiusShare * CustomizeScreen.glowSizeShare)
            .opacity(CustomizeScreen.glowOpacity)
            .offset(x: fitted.width * 0.2, y: fitted.width * 0.1)
            Canvas { context, size in
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let reach = hypot(centre.x, centre.y)
                let cell = fitted.width * CustomizeScreen.gridCellShare
                // A point of the flat grid, pushed out from the middle the more the further it is.
                func bowed(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                    let out = 1 + CustomizeScreen.gridBow * (x * x + y * y) / (reach * reach)
                    return CGPoint(x: centre.x + x * out, y: centre.y + y * out)
                }
                var path = Path()
                let lines = Int((max(centre.x, centre.y) / cell).rounded(.up))
                let steps = 48
                for line in -lines...lines {
                    let at = CGFloat(line) * cell
                    for (index, step) in (0...steps).enumerated() {
                        let along = -reach + 2 * reach * CGFloat(step) / CGFloat(steps)
                        let across = bowed(at, along)
                        if index == 0 { path.move(to: across) } else { path.addLine(to: across) }
                    }
                    for (index, step) in (0...steps).enumerated() {
                        let along = -reach + 2 * reach * CGFloat(step) / CGFloat(steps)
                        let down = bowed(along, at)
                        if index == 0 { path.move(to: down) } else { path.addLine(to: down) }
                    }
                }
                context.stroke(path, with: .color(Color(rgb: EsperPalette.plum.light).opacity(CustomizeScreen.gridOpacity)), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
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

    /// In the chosen face, or `face`, sized so its capitals stand as Bigdex's would at `size`.
    private func title(_ text: String, size: CGFloat, face: CustomizeFont? = nil) -> some View {
        let face = face ?? font
        return Text(text)
            .font(.custom(face.fontName, size: face.size(size)))
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 0, x: 1, y: 2)
            .fixedSize()
    }

    /// Lettered as FLO is when it's lit: gold's first over the cyan, outlined in plum and purple,
    /// in the chosen face or in Bigdex (`ownFace` off). `height` is its cap height, whatever the face.
    private func litTitle(_ text: String, height: CGFloat, spacing: CGFloat = 0, ownFace: Bool = true, maxWidth: CGFloat? = nil) -> some View {
        let word = Onomatopoeia.picture(text, face: .englishDex, colours: FloTuning.colours, growsLeft: true, height: height, spacing: spacing,
                                        fontName: ownFace ? font.fontName : nil)
        // Wider than `maxWidth`, scaled down to it.
        let width = word.height * word.image.size.width / max(word.image.size.height, 1)
        let shrink = maxWidth.map { min($0 / max(width, 1), 1) } ?? 1
        return Image(uiImage: word.image).resizable().aspectRatio(contentMode: .fit).frame(height: word.height * shrink)
    }

    /// Bigdex as `title`, its lower half in `lower`.
    private func twoTone(_ text: String, size: CGFloat, lower: RGB) -> some View {
        title(text, size: size, face: .bigdex)
            .overlay {
                Text(text)
                    .font(.custom(CustomizeFont.bigdex.fontName, size: size))
                    .foregroundStyle(Color(rgb: lower))
                    .fixedSize()
                    .mask(VStack(spacing: 0) {
                        Color.clear
                        Color.black
                    })
            }
    }

    private func subtitle(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.custom(font.fontName, size: font.size(size)))
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black, radius: 0, x: 1, y: 1)
    }

    /// CUSTOMIZE on the heading's plate, and the series' mode large under it.
    @ViewBuilder
    private func heading(_ size: CGSize) -> some View {
        litTitle("CUSTOMIZE", height: size.height * 0.025, spacing: CustomizeScreen.headingSpacing)
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
        let projectorPixel = artPixel(size, times: CustomizeScreen.projectorScale)
        let playerPixel = artPixel(size, times: CustomizeScreen.playerScale)
        let projectorAt = CGPoint(x: ring.x, y: ring.y - CustomizeScreen.projectorY * base)
        // The first side's front limbs are its right; the second, facing the other way, its left.
        // The projector under the halo.
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
        // The beam fading out to nothing at its top.
        picture(tag + "halo").resizable()
            .colorMultiply(Color(rgb: glow))
            .frame(width: halo.width, height: halo.height)
            .energyGlow(radius: halo.width * 0.02)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: CustomizeScreen.haloFadeEnd)],
                                 startPoint: .top, endPoint: .bottom))
            .position(x: halo.midX, y: halo.midY)
        // Standing on the lens, the second side facing the first.
        let lens = projectorAt.y + (CustomizeScreen.lensRow - 32) * projectorPixel
        let figureMiddle = lens - (CustomizeScreen.feetRow - 24) * playerPixel - CustomizeScreen.playerY * base
        if let portrait = flow.scene.customizePortrait(player: player, headNudge: CGPoint(x: headX, y: headY), headScale: headScale) {
            let side = (48 + 2 * CustomizeFigure.margin) * playerPixel
            // The second side is shown turned round, its sleeves and boots swapped as drawn.
            CustomizeFigure(portrait: portrait, look: player == 1 ? pick.look.turnedRound : pick.look, pixel: playerPixel, mirrored: player == 1,
                            headNudge: CGPoint(x: headX, y: headY), headScale: headScale)
                .frame(width: side, height: side)
                .allowsHitTesting(false)
                .position(x: ring.x, y: figureMiddle)
            // From each arm and leg box to its limb on the player: the outer boxes the shown
            // front limbs', the inner the back's, as the boxes tick them. The bracers' leave the
            // box's side toward the player, level, then turn; the sleeves' its bottom, turning
            // first, then level.
            let limbs: [(spot: CustomizeSpot, layer: String, mirrored: Bool, part: BodyPart)] = [
                (.outerArms, tag + "arms_line", true, .frontArm), (.outerLegs, tag + "legs_line", true, .frontLeg),
                (.arms, tag + "arms_line", false, .backArm), (.legs, tag + "legs_line", false, .backLeg),
            ]
            ForEach(Array(limbs.enumerated()), id: \.offset) { _, limb in
                if let centre = portrait.centres[limb.part] {
                    let box = rect(limb.layer, size, mirroredAbout: limb.mirrored ? halo.midX : nil)
                    let across = (centre.x - 24) * playerPixel * (player == 1 ? -1 : 1)
                    let target = CGPoint(x: ring.x + across, y: figureMiddle + (centre.y - 24) * playerPixel)
                    let sleeve = limb.part == .frontArm || limb.part == .backArm
                    let start = sleeve ? CGPoint(x: box.midX, y: box.maxY) : CGPoint(x: box.midX < target.x ? box.maxX : box.minX, y: box.midY)
                    connector(from: start, to: target, turningFirst: sleeve, size: size, lit: cursor == limb.spot, glow: glow)
                }
            }
        }
        // The colour's name over the player, lettered as CUSTOMIZE is, a period between its letters,
        // While the hood's colours are being picked.
        if cursor.owner == .hood {
            // MODEL, as the words under H.O.O.D. are, centred against it.
            HStack(alignment: .center, spacing: size.height * 0.01) {
                subtitle("MODEL", size: size.height * CustomizeScreen.hoodWordShare)
                litTitle(pick.energy.name.uppercased().map(String.init).joined(separator: "."), height: size.height * 0.025,
                         spacing: CustomizeScreen.headingSpacing, maxWidth: halo.width * CustomizeScreen.nameMaxWidthShare)
            }
            .fixedSize()
            .position(x: ring.x, y: figureMiddle - nameY * playerPixel)
        }

        let side = CustomizeScreen.sideLabelShare
        box(player, .skin, tag + "skin", label: "SKIN", labelShare: side, labelBeside: ring.x, size: size, glow: glow, cursor: cursor) { frame in
            VStack(spacing: 0) {
                Color(rgb: PixelPalette.colours[pick.dressing.tone.front])
                Color(rgb: PixelPalette.colours[pick.dressing.tone.back])
            }
            .frame(width: frame.width * 0.5, height: frame.height * 0.5)
            .clipShape(RoundedRectangle(cornerRadius: frame.width * 0.08))
        }
        box(player, .arms, tag + "arms", label: "SLEEVE", labelShare: side, labelBeside: ring.x, size: size, glow: glow, cursor: cursor) {
            tick(flow.customizeTicked(player, .arms), $0)
        }
        box(player, .legs, tag + "legs", label: "BRACER", labelShare: side, labelBeside: ring.x, size: size, glow: glow, cursor: cursor) {
            tick(flow.customizeTicked(player, .legs), $0)
        }
        box(player, .outerArms, tag + "arms", mirroredAbout: halo.midX, label: "SLEEVE", labelShare: side, labelBeside: ring.x, size: size, glow: glow, cursor: cursor) {
            tick(flow.customizeTicked(player, .outerArms), $0)
        }
        box(player, .outerLegs, tag + "legs", mirroredAbout: halo.midX, label: "BRACER", labelShare: side, labelBeside: ring.x, size: size, glow: glow, cursor: cursor) {
            tick(flow.customizeTicked(player, .outerLegs), $0)
        }
        box(player, .hood, tag + "hood", label: "H.O.O.D", size: size, glow: glow, cursor: cursor) { frame in
            if let hood = flow.scene.customizeHood(player: player) {
                Image(uiImage: UIImage(cgImage: hood)).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                    .frame(width: frame.width * 0.7, height: frame.height * 0.7)
                    .scaleEffect(x: player == 0 ? 1 : -1)
            }
        }
        if cursor.owner == .skin || cursor.owner == .hood {
            picker(player, tag + "display", size: size, cursor: cursor, pick: pick, glow: glow)
        }
        if cursor.owner == .hood {
            // What the H.O.O.D. is, over the player: each word of it under its letter.
            HStack(alignment: .top, spacing: size.height * 0.012) {
                ForEach(Array(CustomizeScreen.hoodWords.enumerated()), id: \.offset) { index, word in
                    VStack(spacing: size.height * 0.004) {
                        twoTone(String(word.prefix(1)) + (index < CustomizeScreen.hoodWords.count - 1 ? "." : ""), size: size.height * 0.08,
                                lower: pick.look.bright)
                        subtitle(word, size: size.height * CustomizeScreen.hoodWordShare)
                    }
                    .fixedSize()
                }
            }
            .position(x: ring.x, y: halo.minY - size.height * 0.04)
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

    /// A line from a box to its spot on the player, as the screen's top and bottom lines run:
    /// level out of the box, then turning 45 degrees down or up onto the spot, or `turningFirst`
    /// the other way about, a dot there. In
    /// the small boxes' cyan, or lit in the side's colour, glowing, with the box.
    @ViewBuilder
    private func connector(from start: CGPoint, to target: CGPoint, turningFirst: Bool, size: CGSize, lit: Bool, glow: RGB) -> some View {
        let across = target.x - start.x, down = target.y - start.y
        let slant = min(abs(across), abs(down))
        let sideways: CGFloat = across < 0 ? -1 : 1, downward: CGFloat = down < 0 ? -1 : 1
        // Level then 45 degrees, or 45 degrees then level.
        let points = turningFirst
            ? [start, CGPoint(x: start.x + slant * sideways, y: start.y + slant * downward), target]
            : [start, CGPoint(x: target.x - slant * sideways, y: start.y), CGPoint(x: target.x, y: start.y + slant * downward), target]
        let tip = target
        let colour = Color(rgb: lit ? glow : CustomizeScreen.smallBoxLine)
        let dot = size.height * CustomizeScreen.connectorDotShare
        ZStack {
            Path { path in
                path.addLines(points)
            }
            .stroke(colour, style: StrokeStyle(lineWidth: size.height * CustomizeScreen.connectorWidthShare, lineCap: .round, lineJoin: .round))
            Circle().fill(colour)
                .frame(width: dot * 2, height: dot * 2)
                .position(tip)
        }
        .frame(width: size.width, height: size.height)
        .energyGlow(radius: lit ? dot * 2 : 0)
        .allowsHitTesting(false)
        .position(x: size.width / 2, y: size.height / 2)
    }

    /// One of a side's boxes: its fill, what's in it, its line, and its label under it. Under
    /// its side's cursor the line thickens and lights in the side's colour, glowing.
    @ViewBuilder
    private func box(_ player: Int, _ spot: CustomizeSpot, _ name: String, mirroredAbout axis: CGFloat? = nil, label: String,
                     labelShare: CGFloat = CustomizeScreen.labelShare, labelBeside playerX: CGFloat? = nil,
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
        if let playerX {
            // Down the box's side away from the player, a letter a row, centred on it.
            let right = line.midX > playerX
            let gap = line.width * CustomizeScreen.sideLabelGapShare
            VStack(spacing: letterGap * size.height / 1080) {
                ForEach(Array(label.enumerated()), id: \.offset) { _, letter in title(String(letter), size: line.height * labelShare) }
            }
            .frame(width: 0, height: 0, alignment: right ? .leading : .trailing)
            .position(x: right ? line.maxX + gap : line.minX - gap, y: line.midY)
        } else {
            // Hung from just under the box.
            title(label, size: line.height * labelShare)
                .frame(width: line.width * 2, height: 1, alignment: .top)
                .position(x: line.midX, y: line.maxY + line.height * 0.06)
        }
        Color.clear
            .frame(width: line.width, height: line.height)
            .contentShape(Rectangle())
            .onTapGesture { flow.activateCustomize(player, spot) }
            .position(x: line.midX, y: line.midY)
    }

    /// The skin's or the hood's colours in the side's display, while one is chosen: a column a
    /// colour, leaning, the colour over an accent corner to corner (a skin's back tone, a
    /// colour's shade down its ramp); the picked column lined in white, the cursor's in the side's colour. The display's bar in
    /// the side's colour, glowing.
    @ViewBuilder
    private func picker(_ player: Int, _ name: String, size: CGSize, cursor: CustomizeSpot, pick: PlayerCustomization, glow: RGB) -> some View {
        let frame = rect(name, size)
        let bar = rect(name + "_bar", size)
        let skin = cursor.owner == .skin
        let hovered: Int? = switch cursor {
        case .skinPicker(let column), .hoodPicker(let column): column
        default: nil
        }
        let columns: [(top: RGB, accent: RGB)] = skin
            ? HumanLook.skinTones.map { (PixelPalette.colours[$0.front], PixelPalette.colours[$0.back]) }
            : EnergyColour.wheel.map { ($0.glow, $0.rampDown) }
        let picked = skin ? pick.dressing.skinTone : (EnergyColour.wheel.firstIndex(of: flow.customizations[player].energy) ?? 0)
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
                    // The cursor's column, in the side's colour, outside the pick's line.
                    LeaningBand(from: 0, to: 1).stroke(Color(rgb: glow), lineWidth: index == hovered ? 3 : 0).padding(-4)
                }
                .scaleEffect(index == hovered ? 1.15 : (index == picked ? 1.08 : 1))
                .contentShape(Rectangle())
                .onTapGesture { flow.activateCustomize(player, skin ? .skinPicker(index) : .hoodPicker(index)) }
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
                litTitle("START", height: size.height * 0.035, ownFace: false)
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
                HStack(spacing: 4) {
                    Text("FONT").frame(width: 84, alignment: .leading)
                    tuningButton("◀") { fontPick = CustomizeFont.finalist(after: font, by: -1).rawValue }
                    Text(font.label).frame(width: 140)
                    tuningButton("▶") { fontPick = CustomizeFont.finalist(after: font, by: 1).rawValue }
                }
                tuningRow("LETTER GAP", value: $letterGap, step: 1, range: -20...20, format: "%.0f")
                tuningRow("HEAD X", value: $headX, step: 1, range: -16...16, format: "%.0f")
                tuningRow("HEAD Y", value: $headY, step: 1, range: -16...16, format: "%.0f")
                tuningRow("HEAD SCALE", value: $headScale, step: 0.1, range: 0.5...2, format: "×%.1f")
                tuningRow("NAME Y", value: $nameY, step: 1, range: -64...64, format: "%.0f")
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

/// The customize screen's faces to try, everything on it but START and the big H.O.O.D.
/// lettered in the one picked, alphabetically. Each is sized so its capitals stand as tall as
/// Bigdex's would at the same size. Silom, an Apple system font, isn't bundled.
enum CustomizeFont: Int, CaseIterable {
    case bigdex, bmArmy, boardOfDirectors, kapel, upheaval

    /// The faces to choose between, alphabetically; Bigdex is START's and the big H.O.O.D.'s.
    static let finalists: [CustomizeFont] = [.bmArmy, .boardOfDirectors, .kapel, .upheaval]

    static func finalist(after face: CustomizeFont, by step: Int) -> CustomizeFont {
        let at = finalists.firstIndex(of: face) ?? 0
        return finalists[(at + step + finalists.count) % finalists.count]
    }

    var label: String {
        switch self {
        case .bigdex: "BIGDEX"
        case .bmArmy: "BM ARMY"
        case .boardOfDirectors: "BOARD OF DIRECTORS"
        case .kapel: "KAPEL"
        case .upheaval: "UPHEAVAL"
        }
    }

    var fontName: String {
        switch self {
        case .bigdex: "Bigdex"
        case .bmArmy: "BMarmyA12"
        case .boardOfDirectors: "BoardofDirectors-Heavy"
        case .kapel: "Kapel"
        case .upheaval: "UpheavalTT-BRK-"
        }
    }

    /// Its capitals' height for a point of size.
    private var capShare: CGFloat {
        _ = Onomatopoeia.registered
        return UIFont(name: fontName, size: 100).map { $0.capHeight / 100 } ?? 0.7
    }

    /// The point size whose capitals stand as Bigdex's do at `size`.
    func size(_ size: CGFloat) -> CGFloat { size * CustomizeFont.bigdex.capShare / capShare }
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
    /// The hooded head's place on the figure, put right on the sliders: art pixels right and up,
    /// and its size, about the head's middle.
    let headNudge: CGPoint
    let headScale: CGFloat
    @State private var motion = CustomizeFigureMotion()

    static let margin: CGFloat = 24

    /// Where the hooded head goes and how big: its canvas's top left on the figure's, in pixels
    /// from the top left, and its scale. About the figure's head's middle, which the hood's
    /// own sits on.
    static func hoodPlace(_ portrait: SpriteLibrary.Portrait, nudge: CGPoint, scale: CGFloat) -> (origin: CGPoint, scale: CGFloat) {
        SpriteLibrary.hoodPlace(head: portrait.centres[.head] ?? CGPoint(x: 24, y: 24), offset: portrait.hoodOffset, nudge: nudge, scale: scale)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                motion.advance(to: timeline.date.timeIntervalSinceReferenceDate, portrait: portrait, look: look, headNudge: headNudge, headScale: headScale)
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
                let figureRect = CGRect(x: margin * pixel, y: margin * pixel, width: 48 * pixel, height: 48 * pixel)
                context.draw(Image(decorative: portrait.image, scale: 1).interpolation(.none), in: figureRect)
                if let line = portrait.line {
                    context.drawLayer { layer in
                        layer.addFilter(.colorMultiply(Color(rgb: look.outline)))
                        layer.draw(Image(decorative: line, scale: 1).interpolation(.none), in: figureRect)
                    }
                }
                let place = CustomizeFigure.hoodPlace(portrait, nudge: headNudge, scale: headScale)
                let hoodRect = CGRect(x: (margin + place.origin.x) * pixel, y: (margin + place.origin.y) * pixel,
                                      width: 48 * place.scale * pixel, height: 48 * place.scale * pixel)
                if let hood = portrait.hood { context.draw(Image(decorative: hood, scale: 1).interpolation(.none), in: hoodRect) }
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
                    if let hood = portrait.hoodGlowing { layer.draw(Image(decorative: hood, scale: 1).interpolation(.none), in: hoodRect) }
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

    /// The strings floating one back and one forward as FloState's do, but a human's length, five.
    static let strings: HoodStrings.Style = {
        var style = HoodStrings.floState
        for index in style.strands.indices { style.strands[index].length = HoodStrings.hanging.strands[index].length }
        return style
    }()
    /// The head's cubes a second, each limb's; the game's at no FLO.
    static let headCubeRate = 24.0
    static let shoeCubeRate = Double(ParticleLook.legCubeRate)

    func advance(to time: Double, portrait: SpriteLibrary.Portrait, look: Look, headNudge: CGPoint, headScale: CGFloat) {
        let step = 1.0 / 60
        owed += last.map { min(time - $0, 0.1) } ?? step
        last = time
        while owed >= step {
            owed -= step
            tick(time: time, step: step, portrait: portrait, look: look, headNudge: headNudge, headScale: headScale)
        }
    }

    private func tick(time: Double, step: Double, portrait: SpriteLibrary.Portrait, look: Look, headNudge: CGPoint, headScale: CGFloat) {
        // The strings off the hood's own anchors, wherever the hood went on the figure and at its
        // size, floating one back and one forward.
        let place = CustomizeFigure.hoodPlace(portrait, nudge: headNudge, scale: headScale)
        let anchors = HoodStrings.anchorPixels.map { pixel in
            CGPoint(x: place.origin.x + (pixel.x + 0.5) * place.scale, y: 48 - (place.origin.y + (pixel.y + 0.5) * place.scale))
        }
        strings = stringMotion.step(anchors: anchors, style: CustomizeFigureMotion.strings, facing: 1, scale: 1, time: time)

        // Cubes off the head's crown, where the hood went, and off whatever of the limbs is
        // energy (`Dressing.cubeSources`), as a human's are in play.
        let wind = sin(time * 2 * .pi * ParticleLook.swayPerSecond) * Double(ParticleLook.flowSpeed)
        let head = portrait.centres[.head].map { CGPoint(x: $0.x + headNudge.x, y: $0.y - headNudge.y) }
        let limbs: [(part: BodyPart, rate: Double, size: Float, spread: Float, lift: CGFloat, at: CGPoint?)] = look.dressing.cubeSources.map { limb in
            (limb.part, CustomizeFigureMotion.shoeCubeRate, ParticleLook.legCubeSize, ParticleLook.legCubeSpread, 0,
             limb.fromTop ? portrait.tops[limb.part] : portrait.centres[limb.part])
        }
        let sources = [(BodyPart.head, CustomizeFigureMotion.headCubeRate, ParticleLook.cubeSize, ParticleLook.cubeSpread, GameScene.crownLift, head)] + limbs
        for source in sources {
            guard let centre = source.at else { continue }
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
                                  // The head's in the energy's colour; the limbs' in theirs.
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
