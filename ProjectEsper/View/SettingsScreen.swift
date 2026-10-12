import SwiftUI

/// The settings, over the title or the pause: full screen on the screens' ground, each row's
/// name and its choices, the picked one plum; BACK at the bottom. The cursor is on a row: left
/// and right change it, up and down move between rows; a tap picks a choice outright.
struct SettingsScreen: View {
    @ObservedObject var flow: FlowState
    @ObservedObject private var tuning = UITuning.shared
    private func scale(_ part: UIPart) -> CGFloat { tuning.scale(.title, part) }

    var body: some View {
        ZStack {
            // The stage select's ground, the grid on black, taken so a tap off the choices doesn't
            // reach the pause under it.
            MenuGround(glows: false).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            GeometryReader { geometry in
                // Each row as tall as fits the screen, its title in frame 6 turned round and its
                // choices as words, the titles stacked with no room between.
                let rows = GameSettings.Row.allCases
                let titleImage = Futuristic.image("6")
                let rowHeight = SettingsScreen.boxShare * min(SettingsScreen.rowHeightMost * scale(.buttons),
                                    (geometry.size.height * SettingsScreen.rowsShare - 2 * SettingsScreen.titleHeight * scale(.titles)) / CGFloat(rows.count))
                let titleScale = rowHeight / (titleImage.size.height * titleImage.scale * Futuristic.pointsPerPixel)
                VStack(spacing: 10 * scale(.buttons)) {
                    FloText("SETTINGS", height: SettingsScreen.titleHeight * scale(.titles))
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            rowView(row, index: index, rowHeight: rowHeight, titleScale: titleScale)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    /// SETTINGS lettered as FLO is, as STAGE SELECT is, its cap height in points.
    static let titleHeight: CGFloat = 15
    /// The tallest a row is, in points, and the share of the screen's height the rows and title fill.
    static let rowHeightMost: CGFloat = 48
    static let rowsShare: CGFloat = 0.9

    private func rowView(_ row: GameSettings.Row, index: Int, rowHeight: CGFloat, titleScale: CGFloat) -> some View {
        let onRow = flow.settingsCursor == index
        // Read so the row redraws when a choice changes.
        _ = flow.settingsVersion
        return HStack(spacing: 10 * scale(.buttons)) {
            // Frame 6 turned round, every row's.
            FuturisticFrame(name: "6", lit: onRow, scale: titleScale, mirrored: true) { colour in
                Text(row.title)
                    .font(Futuristic.font(size: rowHeight * SettingsScreen.titleTextShare))
                    .foregroundStyle(colour)
                    .fixedSize()
            }
            .scaleEffect(onRow ? 1 / Futuristic.litGrowth : 1)
            // The choices as words, rule8 under the picked one, sliding to a new pick.
            HStack(spacing: 14 * scale(.buttons)) {
                ForEach(Array(row.options.enumerated()), id: \.offset) { option, label in
                    if row == .wordStyle, Onomatopoeia.Style.allCases.indices.contains(option) {
                        styleChoice(Onomatopoeia.Style.allCases[option], letter: option, picked: row.picked == option, cursor: onRow,
                                    height: rowHeight * SettingsScreen.optionTextShare * SettingsScreen.styleCapShare, row: index) {
                            flow.pickSetting(row: index, option: option)
                        }
                    } else {
                        choice(label, picked: row.picked == option, cursor: onRow, textSize: rowHeight * SettingsScreen.optionTextShare, row: index) {
                            flow.pickSetting(row: index, option: option)
                        }
                    }
                }
            }
            .animation(SettingsScreen.slide, value: row.picked)
        }
        .frame(height: rowHeight)
    }

    /// Every row, its frame and all, a touch smaller than fits.
    static let boxShare: CGFloat = 0.88
    /// The lettering against a row's height: a title's, a choice's.
    static let titleTextShare: CGFloat = 0.3
    static let optionTextShare: CGFloat = 0.32
    /// rule8 under the picked choice: its width against the word's, and its slide to a new pick.
    static let ruleShare: CGFloat = 1.3
    static let slide = Animation.spring(response: 0.3, dampingFraction: 0.8)
    @Namespace private var rules

    /// SFX STYLE's choices as STYLE A, B and C, each lettered as its sound words are, in its own
    /// face, white over light blue (blue's first), outlined as they are; the picked one whole with
    /// rule8 under it, the rest dim.
    static let styleCapShare: CGFloat = 0.75
    private func styleChoice(_ style: Onomatopoeia.Style, letter: Int, picked: Bool, cursor: Bool, height: CGFloat, row: Int,
                             action: @escaping () -> Void) -> some View {
        let face: Onomatopoeia.Lettering = switch style {
        case .cherry: .englishCherry
        case .daruma: .englishDarumadrop
        case .dela: .englishDela
        }
        let line = PixelPalette.colours[Onomatopoeia.lineIndex]
        let word = Onomatopoeia.picture("STYLE " + String(UnicodeScalar(UInt8(65 + letter))), face: face,
                                        colours: Onomatopoeia.Colours(upper: 0xFFFFFF, lower: EsperPalette.blue.highlight, lineUpper: line, lineLower: line),
                                        growsLeft: false, height: height)
        let ruleColour = cursor && picked ? Futuristic.lit : Futuristic.line
        return Button(action: action) {
            Image(uiImage: word.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: word.height)
                .opacity(picked ? 1 : TitleOverlay.unpickedOpacity)
                .overlay(alignment: .bottom) {
                    if picked {
                        GeometryReader { shown in
                            FuturisticPiece(name: "rule8", colour: ruleColour,
                                            stretched: CGSize(width: shown.size.width * 0.9, height: max(height * 0.25, 2)))
                                .frame(width: shown.size.width, alignment: .center)
                                .offset(y: shown.size.height * 0.85)
                        }
                        .matchedGeometryEffect(id: "rule\(row)", in: rules)
                    }
                }
        }
        .buttonStyle(.plain)
        .noSystemFocus()
    }

    /// A choice as a word: the one picked in the menus' blue with rule8 under it, gold on the
    /// cursor's row; the rest dim.
    private func choice(_ text: String, picked: Bool, cursor: Bool, textSize: CGFloat, row: Int, action: @escaping () -> Void) -> some View {
        let colour = picked ? (cursor ? Futuristic.lit : Futuristic.line) : Futuristic.line.opacity(TitleOverlay.unpickedOpacity)
        return Button(action: action) {
            Text(text)
                .font(Futuristic.font(size: textSize))
                .foregroundStyle(colour)
                .fixedSize()
                // The capitals on the row's middle, not the line's.
                .offset(y: -Futuristic.capDrop(size: textSize))
                .overlay(alignment: .bottom) {
                    if picked {
                        GeometryReader { word in
                            FuturisticPiece(name: "rule8", colour: colour == Futuristic.lit ? Futuristic.lit : Futuristic.line,
                                            stretched: CGSize(width: word.size.width * SettingsScreen.ruleShare, height: max(textSize * 0.2, 2)))
                                .frame(width: word.size.width, alignment: .center)
                                .offset(y: word.size.height + textSize * 0.12)
                        }
                        .matchedGeometryEffect(id: "rule\(row)", in: rules)
                    }
                }
        }
        .buttonStyle(.plain)
        .noSystemFocus()
    }
}
