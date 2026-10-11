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
                // Each row as tall as fits the screen, its title in frame 11 and its choices each
                // in frame 5, the titles stacked with no room between.
                let rows = GameSettings.Row.allCases
                let titleImage = Futuristic.image("11")
                let rowHeight = min(SettingsScreen.rowHeightMost * scale(.buttons),
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
        // Frame 11, every other row frame 10 upside down, stretched to 11's size so the stack lines up.
        let eleven = Futuristic.image("11")
        let titleSize = CGSize(width: eleven.size.width * eleven.scale * Futuristic.pointsPerPixel * titleScale,
                               height: eleven.size.height * eleven.scale * Futuristic.pointsPerPixel * titleScale)
        let alternate = index % 2 == 1
        return HStack(spacing: 10 * scale(.buttons)) {
            FuturisticFrame(name: alternate ? "10" : "11", lit: onRow, upsideDown: alternate, stretched: titleSize) { colour in
                Text(row.title)
                    .font(Futuristic.font(size: rowHeight * SettingsScreen.titleTextShare))
                    .foregroundStyle(colour)
                    .fixedSize()
            }
            .scaleEffect(onRow ? 1 / Futuristic.litGrowth : 1)
            // The choices as words, rule8 under the picked one, sliding to a new pick.
            HStack(spacing: 14 * scale(.buttons)) {
                ForEach(Array(row.options.enumerated()), id: \.offset) { option, label in
                    choice(label, picked: row.picked == option, cursor: onRow, textSize: rowHeight * SettingsScreen.optionTextShare, row: index) {
                        flow.pickSetting(row: index, option: option)
                    }
                }
            }
            .animation(SettingsScreen.slide, value: row.picked)
        }
        .frame(height: rowHeight)
    }

    /// The lettering against a row's height: a title's, a choice's.
    static let titleTextShare: CGFloat = 0.3
    static let optionTextShare: CGFloat = 0.32
    /// rule8 under the picked choice: its width against the word's, and its slide to a new pick.
    static let ruleShare: CGFloat = 1.3
    static let slide = Animation.spring(response: 0.3, dampingFraction: 0.8)
    @Namespace private var rules

    /// A choice as a word: the one picked in the menus' blue with rule8 under it, gold on the
    /// cursor's row; the rest dim.
    private func choice(_ text: String, picked: Bool, cursor: Bool, textSize: CGFloat, row: Int, action: @escaping () -> Void) -> some View {
        let colour = picked ? (cursor ? Futuristic.lit : Futuristic.line) : Futuristic.line.opacity(TitleOverlay.unpickedOpacity)
        return Button(action: action) {
            Text(text)
                .font(Futuristic.font(size: textSize))
                .foregroundStyle(colour)
                .fixedSize()
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
