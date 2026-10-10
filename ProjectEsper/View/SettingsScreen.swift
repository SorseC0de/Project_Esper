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
                let titleImage = Futuristic.image("11"), optionImage = Futuristic.image("5")
                let rowHeight = min(SettingsScreen.rowHeightMost * scale(.buttons),
                                    (geometry.size.height * SettingsScreen.rowsShare - 2 * SettingsScreen.titleHeight * scale(.titles)) / CGFloat(rows.count))
                let titleScale = rowHeight / (titleImage.size.height * titleImage.scale * Futuristic.pointsPerPixel)
                let optionScale = rowHeight * SettingsScreen.optionShare / (optionImage.size.height * optionImage.scale * Futuristic.pointsPerPixel)
                VStack(spacing: 10 * scale(.buttons)) {
                    FloText("SETTINGS", height: SettingsScreen.titleHeight * scale(.titles))
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            rowView(row, index: index, rowHeight: rowHeight, titleScale: titleScale, optionScale: optionScale)
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
    /// A choice's frame against its row's height.
    static let optionShare: CGFloat = 0.8

    private func rowView(_ row: GameSettings.Row, index: Int, rowHeight: CGFloat, titleScale: CGFloat, optionScale: CGFloat) -> some View {
        let onRow = flow.settingsCursor == index
        // Read so the row redraws when a choice changes.
        _ = flow.settingsVersion
        return HStack(spacing: 4 * scale(.buttons)) {
            FuturisticFrame(name: "11", lit: onRow, scale: titleScale) { colour in
                Text(row.title)
                    .font(Futuristic.font(size: rowHeight * SettingsScreen.titleTextShare))
                    .foregroundStyle(colour)
                    .fixedSize()
            }
            .scaleEffect(onRow ? 1 / Futuristic.litGrowth : 1)
            ForEach(Array(row.options.enumerated()), id: \.offset) { option, label in
                choice(label, picked: row.picked == option, cursor: onRow, scale: optionScale, textSize: rowHeight * SettingsScreen.optionTextShare) {
                    flow.pickSetting(row: index, option: option)
                }
            }
        }
        .frame(height: rowHeight)
    }

    /// The lettering against a row's height: a title's, a choice's.
    static let titleTextShare: CGFloat = 0.3
    static let optionTextShare: CGFloat = 0.28

    /// A choice in frame 5: the one picked in the menus' blue, gold and a tenth bigger on the
    /// cursor's row; the rest dim.
    private func choice(_ text: String, picked: Bool, cursor: Bool, scale frameScale: CGFloat, textSize: CGFloat,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            FuturisticFrame(name: "5", lit: picked && cursor, scale: frameScale) { colour in
                Text(text)
                    .font(Futuristic.font(size: textSize))
                    .foregroundStyle(colour)
                    .fixedSize()
            }
            .opacity(picked ? 1 : TitleOverlay.unpickedOpacity)
        }
        .buttonStyle(.plain)
        .noSystemFocus()
    }
}
