import EsperSim
import SwiftUI

/// The game and what its scene tells the SwiftUI layer: whether the title is up, whether
/// a screen wants the royal blue ground under it, and what to do when the title's buttons
/// are pressed.
@MainActor
final class FlowState: ObservableObject {
    let scene = GameScene()
    let net = GameCenter()
    @Published var showsTitle = true
    @Published var veiled = false
    /// The ground under the screen is the palette's black rather than the royal blue: the
    /// Greateraid pick and wait.
    @Published var blackGround = false
    /// The win screen's own ground.
    @Published var winGround = false
    /// The UI tuning panel is open.
    @Published var tuningOpen = false
    var startSeries: ((GameMode) -> Void)?
    /// The title's cursor, the game's own on every platform: a pad moves it and A picks,
    /// and a tap picks straight away and moves it there.
    @Published var titleCursor = TitleItem.bestOfSeven
    /// Which tone each grid picks.
    @Published var tones: [UIColourPicks.Grid: UIColourPicks.Tone] = [:]
    func tone(for grid: UIColourPicks.Grid) -> UIColourPicks.Tone { tones[grid] ?? .main }

    init() {
        scene.flowState = self
        SoundBoard.shared.prepare()
        // An invite accepted from outside the game opens the multiplayer screen on the joining.
        net.onInviteAccepted = { [weak self] in self?.multiplayerOpen = true }
    }

    // MARK: The settings

    /// The settings screen, over the title or the pause; its cursor's row (the last past the
    /// rows is BACK), and a count bumped when a choice changes, so the screen redraws.
    @Published var settingsOpen = false
    @Published var settingsCursor = 0
    @Published var settingsVersion = 0

    func openSettings() {
        settingsOpen = true
        settingsCursor = 0
    }

    func closeSettings() {
        SoundBoard.shared.play(.menuBack)
        settingsOpen = false
    }

    /// Up or down a row, BACK under the last.
    func moveSettingsCursor(_ step: Int) {
        let next = min(max(settingsCursor + step, 0), GameSettings.Row.allCases.count)
        guard next != settingsCursor else { return }
        settingsCursor = next
        SoundBoard.shared.play(SoundBoard.navigate)
    }

    /// The cursor's row on to its next choice, or back, round the ends.
    func stepSetting(_ step: Int) {
        let rows = GameSettings.Row.allCases
        guard rows.indices.contains(settingsCursor) else { return }
        let row = rows[settingsCursor]
        pickSetting(row: settingsCursor, option: (row.picked + step + row.options.count) % row.options.count)
    }

    /// A choice picked, by a tap or the pad.
    func pickSetting(row index: Int, option: Int) {
        let rows = GameSettings.Row.allCases
        guard rows.indices.contains(index) else { return }
        settingsCursor = index
        rows[index].picked = option
        settingsVersion += 1
        SoundBoard.shared.play(SoundBoard.navigate)
    }

    // MARK: The multiplayer screen

    /// The game's own multiplayer screen, over the title: play now, invite a friend, and
    /// the wait for either, on the same cursor as the title.
    @Published var multiplayerOpen = false
    enum MultiplayerPage { case menu, friends }
    @Published var multiplayerPage = MultiplayerPage.menu
    @Published var multiplayerCursor = 0

    enum MultiplayerItem: Hashable {
        case playNow, inviteFriend, friend(String), cancel, back
    }

    /// What the screen offers, top to bottom: the wait's cancel while matching, else the
    /// page's choices.
    var multiplayerItems: [MultiplayerItem] {
        switch net.state {
        case .finding, .connecting: return [.cancel]
        default: break
        }
        switch multiplayerPage {
        case .menu: return [.playNow, .inviteFriend, .back]
        case .friends: return net.friends.map { .friend($0.gamePlayerID) } + [.back]
        }
    }

    var multiplayerSelection: MultiplayerItem? {
        let items = multiplayerItems
        return items.indices.contains(multiplayerCursor) ? items[multiplayerCursor] : items.last
    }

    func openMultiplayer() {
        multiplayerOpen = true
        multiplayerPage = .menu
        multiplayerCursor = 0
        net.signIn()
    }

    func moveMultiplayerCursor(_ step: Int) {
        let count = multiplayerItems.count
        guard count > 0 else { return }
        let next = min(max(multiplayerCursor + step, 0), count - 1)
        guard next != multiplayerCursor else { return }
        multiplayerCursor = next
        SoundBoard.shared.play(SoundBoard.navigate)
    }

    func activate(_ item: MultiplayerItem) {
        if let index = multiplayerItems.firstIndex(of: item) { multiplayerCursor = index }
        switch item {
        case .playNow:
            SoundBoard.shared.play(SoundBoard.confirm)
            net.playNow()
            multiplayerCursor = 0
        case .inviteFriend:
            SoundBoard.shared.play(SoundBoard.confirm)
            multiplayerPage = .friends
            multiplayerCursor = 0
            net.loadFriends()
        case .friend(let id):
            guard let friend = net.friends.first(where: { $0.gamePlayerID == id }) else { return }
            SoundBoard.shared.play(SoundBoard.confirm)
            net.invite(friend)
            multiplayerCursor = 0
        case .cancel, .back:
            multiplayerBack()
        }
    }

    /// Back: a search or invite cancelled, the friends list back to the menu, the menu shut.
    func multiplayerBack() {
        SoundBoard.shared.play(.menuBack)
        switch net.state {
        case .finding:
            net.cancelFinding()
            multiplayerCursor = 0
            return
        default:
            break
        }
        if multiplayerPage == .friends {
            multiplayerPage = .menu
            multiplayerCursor = 1
        } else {
            multiplayerOpen = false
        }
    }

    /// The cursor a row up or down, to the item nearest across, or along its row.
    func moveTitleCursor(across: Int, down: Int) {
        let rows = TitleItem.rows
        guard let row = rows.firstIndex(where: { $0.contains(titleCursor) }), let column = rows[row].firstIndex(of: titleCursor) else {
            titleCursor = .bestOfSeven
            return
        }
        var next = titleCursor
        if across != 0 {
            next = rows[row][min(max(column + across, 0), rows[row].count - 1)]
        } else if down != 0 {
            let target = min(max(row + down, 0), rows.count - 1)
            // The same share of the way along the row.
            let share = rows[row].count > 1 ? Double(column) / Double(rows[row].count - 1) : 0.5
            next = rows[target][Int((share * Double(rows[target].count - 1)).rounded())]
        }
        guard next != titleCursor else { return }
        titleCursor = next
        SoundBoard.shared.play(SoundBoard.navigate)
    }

    /// What picking an item does, from the pad or a tap.
    func activate(_ item: TitleItem) {
        titleCursor = item
        let busy: Bool
        switch net.state {
        case .signingIn, .finding, .connecting, .connected: busy = true
        default: busy = false
        }
        let defaults = UserDefaults.standard
        switch item {
        case .bestOfSeven, .fortySeven:
            guard !busy else { return }
            SoundBoard.shared.play(SoundBoard.confirm)
            startSeries?(item == .bestOfSeven ? .rounds : .fortySeven)
        case .vsCPU, .vsHuman:
            guard !busy else { return }
            defaults.set(item == .vsCPU, forKey: GameScene.vsCPUKey)
            SoundBoard.shared.play(SoundBoard.navigate)
        case .multiplayer:
            guard !busy else { return }
            SoundBoard.shared.play(SoundBoard.confirm)
            openMultiplayer()
        case .onlineRounds, .onlineFortySeven:
            guard !busy else { return }
            defaults.set(Int((item == .onlineRounds ? GameMode.rounds : .fortySeven).rawValue), forKey: GameScene.onlineModeKey)
            SoundBoard.shared.play(SoundBoard.navigate)
        case .colour(let colour):
            defaults.set(colour.rawValue, forKey: EnergyColour.storageKey)
            SoundBoard.shared.play(SoundBoard.navigate)
            scene.applySavedColours()
        case .tuning:
            tuningOpen.toggle()
        case .settings:
            SoundBoard.shared.play(SoundBoard.confirm)
            openSettings()
        case .toneTab(let grid, let tone):
            tones[grid] = tone
            SoundBoard.shared.play(SoundBoard.navigate)
        case .swatch(let grid, let index):
            // Picking the one picked takes the pack's own tone back.
            UIColourPicks.toggle(grid, tone(for: grid), index)
            SoundBoard.shared.play(SoundBoard.navigate)
            UITuning.shared.touch()
            scene.refreshPreview()
        }
    }
}

/// Everything on the title the cursor can land on, row by row as they're laid out.
enum TitleItem: Hashable {
    case bestOfSeven, fortySeven, vsCPU, vsHuman, multiplayer, onlineRounds, onlineFortySeven
    case colour(EnergyColour)
    case tuning
    /// The gear in the upper right corner, opening the settings.
    case settings
    /// A swatch on one of the grids, by its index in `EsperPalette.swatches`, and the tabs
    /// that say which tone each grid picks.
    case swatch(UIColourPicks.Grid, Int)
    case toneTab(UIColourPicks.Grid, UIColourPicks.Tone)

    /// The grids' swatches a row: two ramps of four.
    static let swatchesPerRow = 8

    static let rows: [[TitleItem]] = [
        [.settings],
        [.bestOfSeven, .fortySeven],
        [.vsCPU, .vsHuman],
        [.multiplayer],
        [.onlineRounds, .onlineFortySeven],
        UIColourPicks.Grid.allCases.flatMap { grid in UIColourPicks.Tone.allCases.map { TitleItem.toneTab(grid, $0) } },
    ] + stride(from: 0, to: EsperPalette.swatches.count, by: swatchesPerRow).map { start in
        // The grids side by side, bottom left.
        UIColourPicks.Grid.allCases.flatMap { grid in (start..<start + swatchesPerRow).map { TitleItem.swatch(grid, $0) } }
    } + [
        [.tuning] + EnergyColour.allCases.map { .colour($0) },
    ]
}

/// The title screen, on the royal blue ground with the court just showing through, in the
/// dobo UI pack's pieces: the name; BEST OF 7 and 47 against the computer on royal blue
/// plates, with the VS CPU / VS HUMAN switch under them; MULTIPLAYER on gold, which opens
/// Game Center's matchmaker, with the mode it asks for under it and Game Center's word
/// under that; and the energy colours on a black plate in the upper right corner.
struct TitleOverlay: View {
    @ObservedObject var flow: FlowState
    @ObservedObject var net: GameCenter
    /// This phone's energy colour, kept between launches.
    @AppStorage(EnergyColour.storageKey) private var colour = EnergyColour.orange.rawValue
    /// The mode multiplayer asks for; the host's is played.
    @AppStorage(GameScene.onlineModeKey) private var onlineMode = Int(GameMode.rounds.rawValue)
    /// Offline, whether the computer plays player 2 or a second pad does.
    @AppStorage(GameScene.vsCPUKey) private var vsCPU = true
    @ObservedObject private var tuning = UITuning.shared
    private func scale(_ part: UIPart) -> CGFloat { tuning.scale(.title, part) }

    private var busy: Bool {
        switch net.state {
        case .signingIn, .finding, .connecting, .connected: true
        default: false
        }
    }

    var body: some View {
        ZStack {
            Color(rgb: UIColourPicks.ground)
                .ignoresSafeArea()
                // The energy colours in the bottom right corner, the UI tuning in the bottom left.
                .overlay(alignment: .bottomTrailing) {
                    // Hard in the corner, clear of the buttons in the middle.
                    colourPicker
                    .padding(.bottom, 12)
                    .padding(.trailing, 8)
                }
                // The settings' gear in the upper right corner.
                .overlay(alignment: .topTrailing) {
                    SettingsGear(lit: flow.titleCursor == .settings) { flow.activate(.settings) }
                        .padding(.top, 14)
                        .padding(.trailing, 18)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(UIColourPicks.Grid.allCases, id: \.self) { grid in
                                VStack(alignment: .leading, spacing: 4) {
                                    pickerLabel(grid.label)
                                    HStack(spacing: 4) {
                                        ForEach(UIColourPicks.Tone.allCases, id: \.self) { tone in toneTab(grid, tone) }
                                    }
                                    SwatchGrid(flow: flow, grid: grid)
                                }
                            }
                        }
                        small("UI", picked: flow.tuningOpen, item: .tuning)
                    }
                        .padding(.bottom, 20)
                        .padding(.leading, 24)
                }
            VStack(spacing: 22 * scale(.buttons)) {
                Image(uiImage: TitleText.image("PROJECT ESPER", size: 56 * scale(.titles)))
                HStack(spacing: 24 * scale(.buttons)) {
                    plated("BEST OF 7", piece: .buttonBlue, width: 170, item: .bestOfSeven)
                    plated("47", piece: .buttonBlue, width: 170, item: .fortySeven)
                }
                HStack(spacing: 10) {
                    small("VS CPU", picked: vsCPU, item: .vsCPU)
                    small("VS HUMAN", picked: !vsCPU, item: .vsHuman)
                }
                VStack(spacing: 10) {
                    plated("MULTIPLAYER", piece: .buttonPlum, width: 240, item: .multiplayer)
                    .opacity(busy ? 0.5 : 1)
                    HStack(spacing: 10) {
                        ForEach(GameMode.allCases, id: \.self) { mode in
                            small(mode == .rounds ? "BEST OF 7" : "47", picked: onlineMode == Int(mode.rawValue),
                                  item: mode == .rounds ? .onlineRounds : .onlineFortySeven)
                        }
                    }
                    if let caption = net.state.caption {
                        Text(caption)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { net.signIn() }
    }

    /// A lettered button on one of the pack's plates, at the title's tuned sizes; under the
    /// cursor, on the gold plate and a little bigger, as the screens' cursor is.
    private func plated(_ text: String, piece: UIPiece, width: CGFloat, item: TitleItem) -> some View {
        let piece = flow.titleCursor == item ? UIPiece.buttonGold : piece
        return Button { flow.activate(item) } label: {
            let rise = tuning.textRise
            let shift = TitleText.dropShift(size: 26 * scale(.text)) * rise
            // On the gold plate, the lettering's lower half goes light blue.
            Image(uiImage: TitleText.image(text, size: 26 * scale(.text), lit: flow.titleCursor == item))
                // Centred on the plate's face, the drop taken off (SwiftUI's y runs down).
                .offset(x: -shift, y: -(piece.faceRise * scale(.buttons) * rise + shift))
                .frame(width: width * scale(.buttons), height: 54 * scale(.buttons))
                .background(piece.image(corners: scale(.buttons)))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .scaleEffect(flow.titleCursor == item ? TitleOverlay.cursorGrowth : 1)
        .noSystemFocus()
    }

    /// Under the cursor, a plate grows this much.
    static let cursorGrowth: CGFloat = 1.08

    /// A small switch: plum when it's the one picked, black otherwise, gold under the cursor.
    private func small(_ text: String, picked: Bool, item: TitleItem) -> some View {
        let piece = flow.titleCursor == item ? UIPiece.buttonGold : (picked ? UIPiece.buttonPlum : UIPiece.buttonBlack)
        return Button { flow.activate(item) } label: {
            Text(text)
                .font(.system(size: 12 * scale(.text), weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                .offset(y: -UIPiece.buttonPlum.faceRise * scale(.buttons) * tuning.textRise)
                .frame(minWidth: 96 * scale(.buttons), minHeight: 30 * scale(.buttons))
                .padding(.horizontal, 8)
                .background(piece.image(corners: scale(.buttons)))
        }
        .buttonStyle(.plain)
        .disabled(busy && item != .tuning)
        .scaleEffect(flow.titleCursor == item ? TitleOverlay.cursorGrowth : 1)
        .noSystemFocus()
    }

    private func pickerLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 0, x: 1, y: 1)
    }

    /// Which of a grid's three tones it picks: gold under the cursor, plum when it's the grid's.
    private func toneTab(_ grid: UIColourPicks.Grid, _ tone: UIColourPicks.Tone) -> some View {
        let piece = flow.titleCursor == .toneTab(grid, tone) ? UIPiece.buttonGold : (flow.tone(for: grid) == tone ? UIPiece.buttonPlum : UIPiece.buttonBlack)
        return Button { flow.activate(.toneTab(grid, tone)) } label: {
            Text(tone.label)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(piece.image(corners: 0.5))
        }
        .buttonStyle(.plain)
        .noSystemFocus()
    }

    /// The energy colours as a row of circles on a black plate, the picked one ringed.
    private var colourPicker: some View {
        HStack(spacing: 10) {
            ForEach(EnergyColour.allCases, id: \.self) { choice in
                Button { flow.activate(.colour(choice)) } label: {
                    Circle()
                        .fill(Color(rgb: choice.glow))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(.white, lineWidth: choice.rawValue == colour ? 3 : 0).padding(-4))
                        // Under the cursor, a gold ring outside the pick's.
                        .overlay(Circle().stroke(Color(rgb: EsperPalette.gold.body), lineWidth: flow.titleCursor == .colour(choice) ? 3 : 0).padding(-8))
                }
                .buttonStyle(.plain)
                .scaleEffect(flow.titleCursor == .colour(choice) ? 1.15 : 1)
                .noSystemFocus()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(UIPiece.buttonBlack.image)
    }
}

extension View {
    /// Off the TV's focus engine: the game's own cursor is the only one, on every platform.
    @ViewBuilder
    func noSystemFocus() -> some View {
        #if os(tvOS)
        self.focusable(false)
        #else
        self
        #endif
    }
}

extension Color {
    init(rgb: RGB) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}
