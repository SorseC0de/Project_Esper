import SwiftUI

/// The settings, over the title or the pause: full screen on the screens' ground. Its categories
/// side by side, each frame 6 without its tail; one opened slides aside, its rows fan down under it,
/// indented, and a mask drawn back to the right shows their tails and choices; tapped again, it all
/// goes back the way it came. A row's picked choice is plum. PLAYER VISIBILITY draws the players
/// again: the loading bar up, everything dim and waiting till it's done.
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
                let size = geometry.size
                // Each row as tall as fits the most a category has under the categories' row, its title
                // in frame 6 turned round, the rows stacked with no room between.
                let most = GameSettings.Category.allCases.map { GameSettings.Row.rows(in: $0).count }.max() ?? 1
                let titleImage = Futuristic.image("6")
                let rowHeight = SettingsScreen.boxShare * min(SettingsScreen.rowHeightMost * scale(.buttons),
                                    (size.height * SettingsScreen.rowsShare - 2 * SettingsScreen.titleHeight * scale(.titles)) / CGFloat(most + 1))
                let titleScale = rowHeight / (titleImage.size.height * titleImage.scale * Futuristic.pointsPerPixel)
                let frameWidth = titleImage.size.width * titleImage.scale * Futuristic.pointsPerPixel * titleScale
                let boxWidth = frameWidth * (1 - Futuristic.sixTailSplit)
                let titleY = size.height * SettingsScreen.titleYShare
                let barY = titleY + SettingsScreen.titleHeight * scale(.titles) + rowHeight * SettingsScreen.barDropRows
                let rowsLeft = size.width * SettingsScreen.rowsLeftShare
                let indent = boxWidth * SettingsScreen.indentShare
                ZStack {
                    FloText("SETTINGS", height: SettingsScreen.titleHeight * scale(.titles))
                        .position(x: size.width / 2, y: titleY)
                    // The open category's rows, under its button.
                    ForEach(Array(flow.settingsRows.enumerated()), id: \.offset) { index, row in
                        let left = rowsLeft + indent
                        let rowY = barY + CGFloat(index + 1) * rowHeight
                        let fanned = flow.settingsFanned
                        let count = flow.settingsRows.count
                        rowView(row, index: index, rowHeight: rowHeight, titleScale: titleScale)
                            .frame(width: size.width - left, height: rowHeight, alignment: .leading)
                            // Only the box till the mask draws back to the right over the tail and choices.
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: flow.settingsRevealed ? size.width : boxWidth)
                                    .animation(.easeOut(duration: FlowState.settingsRevealSeconds), value: flow.settingsRevealed)
                            }
                            .offset(x: fanned ? 0 : -indent, y: fanned ? 0 : barY - rowY)
                            .opacity(fanned ? 1 : 0)
                            .animation(.spring(response: FlowState.settingsFanSeconds, dampingFraction: 0.85)
                                .delay(FlowState.settingsFanStagger * Double(fanned ? index : count - 1 - index)), value: fanned)
                            .position(x: left + (size.width - left) / 2, y: rowY)
                    }
                    // The categories side by side; the open one aside, the others gone.
                    ForEach(GameSettings.Category.allCases, id: \.rawValue) { category in
                        let across = size.width / 2 + CGFloat(category.rawValue - 1) * (boxWidth + SettingsScreen.categoryGap * scale(.buttons))
                        let open = flow.settingsCategory == category
                        let aside = open && flow.settingsAside
                        let hidden = flow.settingsCategory != nil && !open && flow.settingsAside
                        let empty = GameSettings.Row.rows(in: category).isEmpty
                        let lit = flow.settingsCategory == nil ? flow.settingsCategoryCursor == category.rawValue : open && flow.settingsCursor == -1
                        Button {
                            if open { flow.closeSettingsCategory() } else { flow.openSettingsCategory(category) }
                        } label: {
                            FuturisticFrame(name: "6tailless", lit: lit, scale: titleScale, mirrored: true, image: Futuristic.taillessSix) { colour in
                                Text(category.title)
                                    .font(Futuristic.font(size: rowHeight * SettingsScreen.titleTextShare))
                                    .foregroundStyle(colour)
                                    .fixedSize()
                            }
                        }
                        .buttonStyle(.plain)
                        .noSystemFocus()
                        .opacity(hidden ? 0 : empty ? TitleOverlay.unpickedOpacity : 1)
                        .position(x: aside ? rowsLeft + boxWidth / 2 : across, y: barY)
                        .animation(.easeInOut(duration: FlowState.settingsAsideSeconds), value: flow.settingsAside)
                    }
                }
                .opacity(flow.settingsReloading ? SettingsScreen.reloadingDim : 1)
                .allowsHitTesting(!flow.settingsLocked)
                .animation(.easeOut(duration: 0.2), value: flow.settingsReloading)
                // The players being drawn again: the loading bar, full for the last of it, the GPU's.
                if flow.settingsReloading {
                    LoadingBar(litSlots: flow.loadingSlots ?? FlowState.loadingSlotCount)
                        .position(x: size.width / 2, y: size.height * SettingsScreen.barYShare)
                        .transition(.opacity)
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    /// SETTINGS lettered as FLO is, as STAGE SELECT is, its cap height in points.
    static let titleHeight: CGFloat = 15
    /// The tallest a row is, in points, and the share of the screen's height the rows and title fill.
    static let rowHeightMost: CGFloat = 48
    static let rowsShare: CGFloat = 0.9
    /// Where things go: the title down the screen, the categories this many rows under it, the open
    /// category's column in from the left and its rows in from its button, a share of the box;
    /// the categories' gap; the loading bar down the screen; and how dim it all is meanwhile.
    static let titleYShare: CGFloat = 0.08
    static let barDropRows: CGFloat = 0.9
    static let rowsLeftShare: CGFloat = 0.08
    static let indentShare: CGFloat = 0.15
    static let categoryGap: CGFloat = 14
    static let barYShare: CGFloat = 0.92
    static let reloadingDim = 0.4

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
            // The choices as words, rule8 under the picked one, sliding to a new pick.
            HStack(spacing: 14 * scale(.buttons)) {
                ForEach(Array(row.options.enumerated()), id: \.offset) { option, label in
                    if row == .wordStyle, Onomatopoeia.Style.lettered.indices.contains(option) {
                        styleChoice(Onomatopoeia.Style.lettered[option], letter: option, picked: row.picked == option, cursor: onRow,
                                    height: rowHeight * SettingsScreen.optionTextShare * SettingsScreen.styleCapShare, row: index) {
                            flow.pickSetting(row: index, option: option)
                        }
                    } else if row == .wordLanguage, let language = Onomatopoeia.Language(rawValue: option) {
                        languageChoice(language, picked: row.picked == option, cursor: onRow, height: rowHeight * SettingsScreen.flagShare, row: index) {
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
            // A new line for the players draws them all again.
            if row == .playerVisibility {
                Text("Game will need to reload visuals")
                    .font(.system(size: rowHeight * SettingsScreen.warningTextShare).italic())
                    .foregroundStyle(Futuristic.line.opacity(SettingsScreen.warningOpacity))
                    .fixedSize()
            }
        }
        .frame(height: rowHeight)
    }
    /// PLAYER VISIBILITY's warning against a row's height, and how strong.
    static let warningTextShare: CGFloat = 0.16
    static let warningOpacity = 0.7

    /// Every row, its frame and all, a touch smaller than fits.
    static let boxShare: CGFloat = 0.88
    /// The lettering against a row's height: a title's, a choice's.
    static let titleTextShare: CGFloat = 0.3
    static let optionTextShare: CGFloat = 0.32
    /// rule8 under the picked choice: its width against the word's, and its slide to a new pick.
    static let ruleShare: CGFloat = 1.3
    static let slide = Animation.spring(response: 0.3, dampingFraction: 0.8)
    @Namespace private var rules

    /// SFX LANGUAGE's choices as their flags (`language_eng`, `_jap`, `_spa`), against the row's height.
    static let flagShare: CGFloat = 0.5
    private func languageChoice(_ language: Onomatopoeia.Language, picked: Bool, cursor: Bool, height: CGFloat, row: Int,
                                action: @escaping () -> Void) -> some View {
        let name = ["language_eng", "language_jap", "language_spa"][language.rawValue]
        return Button(action: action) {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
                .opacity(picked ? 1 : TitleOverlay.unpickedOpacity)
                .overlay(alignment: .bottom) {
                    if picked {
                        GeometryReader { shown in
                            FuturisticPiece(name: "rule8", colour: cursor ? Futuristic.lit : Futuristic.line,
                                            stretched: CGSize(width: shown.size.width * 0.9, height: max(height * 0.15, 2)))
                                .frame(width: shown.size.width, alignment: .center)
                                .offset(y: shown.size.height * 1.05)
                        }
                        .matchedGeometryEffect(id: "rule\(row)", in: rules)
                    }
                }
        }
        .buttonStyle(.plain)
        .noSystemFocus()
    }

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
        let word = Onomatopoeia.picture("STYLE " + String(UnicodeScalar(UInt8(65 + letter))), face: face,
                                        colours: Onomatopoeia.Colours(upper: 0xFFFFFF, lower: EsperPalette.blue.highlight, lineUpper: Onomatopoeia.lineUpper, lineLower: Onomatopoeia.lineLower),
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
