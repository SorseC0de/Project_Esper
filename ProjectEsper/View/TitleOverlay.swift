import EsperSim
import GameKit
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
    /// BALL OUT called: its Z card across the screen, once a call, gone when it's crossed.
    @Published var ballOutCall: UUID?
    /// The stage preview's name over its big panel, once it's in.
    @Published var previewTitle: String?
    /// The ground under the screen is the palette's black rather than the royal blue: the
    /// Greateraid pick and wait.
    @Published var blackGround = false
    /// The pause's: a third-black wash under a thin dark material over the match.
    @Published var pauseGround = false
    /// The stage select's: the warped grid on black, as the title's.
    @Published var gridGround = false
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
        scene.onLoading = { [weak self] progress in
            guard let self else { return }
            let slots = progress.map { Int($0 * Double(FlowState.loadingSlotCount)) }
            if slots != self.loadingSlots { self.loadingSlots = slots }
        }
        SoundBoard.shared.prepare()
        // An invite accepted from outside the game opens the multiplayer screen on the joining.
        net.onInviteAccepted = { [weak self] in self?.multiplayerOpen = true }
        // Signed in with the ZONES matches waiting on it: the list.
        net.onSignedIn = { [weak self] in
            guard let self, self.multiplayerOpen, self.zonesOnlinePicked else { return }
            self.net.loadTurnMatches()
        }
        // A ZONES turn tapped in Game Center's notification: its turn opens, from the title.
        net.onTurnTapped = { [weak self] match in
            guard let self, self.showsTitle, !self.customizeOpen, self.net.isLocalTurn(match) else { return }
            UserDefaults.standard.set(Int(GameMode.zones.rawValue), forKey: GameScene.onlineModeKey)
            self.multiplayerOpen = true
            self.openZonesTurn(match)
        }
    }

    // MARK: Loading

    /// The loading bar's lit slots, what's loading's progress over its sixteen, or nil with
    /// nothing loading. A transition that holds for loading keeps its curtain down, the bar on
    /// it, until it's nil; the stage preview shows the bar over its page while it isn't.
    @Published var loadingSlots: Int? {
        didSet {
            guard loadingSlots == nil, let lift = heldLift else { return }
            heldLift = nil
            lift()
        }
    }
    static let loadingSlotCount = FuturisticMeter.slots.count
    private var heldLift: (() -> Void)?
    /// Where the in-match pause icon is, in the view's points: the pause menu's resume button's place.
    @Published var pauseRect = CGRect.zero
    /// The stage select can go back: offline before the series' first stage, to the customize
    /// screen; online, out of the match.
    @Published var stageSelectBack = false
    /// A curtain's down waiting on loading; the stage preview's up.
    @Published var curtainHeld = false
    @Published var previewing = false
    /// The longest a curtain waits on loading before going up regardless.
    static let loadingHoldLimit = 15.0

    /// `lift` now, or once nothing's loading.
    private func whenLoaded(_ lift: @escaping () -> Void) {
        guard loadingSlots != nil else { return lift() }
        curtainHeld = true
        heldLift = { [weak self] in
            self?.curtainHeld = false
            lift()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + FlowState.loadingHoldLimit) { [weak self] in
            guard let self, let held = self.heldLift else { return }
            self.heldLift = nil
            held()
        }
    }

    // MARK: The curtain

    /// The curtain between screens (`ScreenTransition`): down over everything, the change made
    /// at full cover, then up again. One at a time; a change asked for mid-way goes after the
    /// one running.
    @Published var curtain = 0.0
    @Published var curtainStyle = ScreenTransition.fade
    private var curtainBusy = false
    private var curtainQueue: [(ScreenTransition, Bool, () -> Void)] = []

    func transition(_ style: ScreenTransition = .fade, holdsForLoading: Bool = false, _ change: @escaping () -> Void) {
        guard !curtainBusy else {
            curtainQueue.append((style, holdsForLoading, change))
            return
        }
        curtainBusy = true
        curtainStyle = style
        withAnimation(.easeIn(duration: style.downSeconds)) { curtain = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + style.downSeconds + 0.05) { [weak self] in
            guard let self else { return }
            change()
            // Held down over anything the change set loading, the bar filling on it, if it's to be.
            let lift = { [weak self] in
                guard let self else { return }
                withAnimation(.easeOut(duration: style.upSeconds)) { self.curtain = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + style.upSeconds) { [weak self] in
                    guard let self else { return }
                    self.curtainBusy = false
                    if !self.curtainQueue.isEmpty {
                        let next = self.curtainQueue.removeFirst()
                        self.transition(next.0, holdsForLoading: next.1, next.2)
                    }
                }
            }
            if holdsForLoading { self.whenLoaded(lift) } else { lift() }
        }
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

    // MARK: The customize screen

    /// The customize screen, between the title and the stage select: each side's cursor and
    /// picks, and the mode it starts.
    @Published var customizeOpen = false
    /// ZONES' screen over play, while a game's on.
    @Published var zonesHud: ZonesHud?
    @Published var customizeCursors: [CustomizeSpot] = [.skin, .skin]
    @Published var customizations = [PlayerCustomization.saved(0), PlayerCustomization.saved(1)]
    var customizeMode = GameMode.rounds
    /// Online: both sides on the screen at once, this phone editing only its own side
    /// (`customizeLocal`), the other's picks arriving as they're made.
    @Published var customizeOnline = false
    /// ZONES online: this phone's side only, the other's look as their last turn sent it.
    @Published var customizeTurnBased = false
    var customizeLocal = 0
    /// Each side's READY, and the moment both were, when the launch animation starts.
    @Published var customizeReady = [false, false]
    @Published var customizeLaunch: Date?
    /// Online: the launch animation's played through; the series can start.
    var customizeLaunched = false

    // MARK: The multiplayer screen

    /// The game's own multiplayer screen, over the title: play now, invite a friend, and
    /// the wait for either, on the same cursor as the title.
    @Published var multiplayerOpen = false
    enum MultiplayerPage { case menu, friends }
    @Published var multiplayerPage = MultiplayerPage.menu
    @Published var multiplayerCursor = 0

    enum MultiplayerItem: Hashable {
        case mode(GameMode), playNow, inviteFriend, friend(String), cancel, back
        /// A ZONES match of this player's, by Game Center's ID.
        case turnMatch(String)
    }
    /// The modes multiplayer offers: ROUNDS and 47 live over Game Center, ZONES turn by turn.
    static let onlineModes: [GameMode] = [.rounds, .fortySeven, .zones]
    /// ZONES is the mode asked for: the screen lists this player's matches.
    var zonesOnlinePicked: Bool { GameScene.savedOnlineMode == .zones }

    /// What the screen offers, top to bottom: the wait's cancel while matching, else the
    /// page's choices.
    var multiplayerItems: [MultiplayerItem] {
        switch net.state {
        case .finding, .connecting: return [.cancel]
        default: break
        }
        switch multiplayerPage {
        case .menu:
            let matches: [MultiplayerItem] = zonesOnlinePicked ? net.turnMatches.map { .turnMatch($0.matchID) } : []
            return FlowState.onlineModes.map { .mode($0) } + [.playNow, .inviteFriend] + matches + [.back]
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
        // On PLAY NOW, past the modes.
        multiplayerCursor = FlowState.onlineModes.count
        net.signIn()
        if zonesOnlinePicked { net.loadTurnMatches() }
    }

    /// A ZONES match of this player's to play: its turn into the scene, then the customize
    /// screen for this side, START taking the turn up.
    func openZonesTurn(_ match: GKTurnBasedMatch) {
        let local = net.localIndex(in: match)
        let opened = scene.beginZonesTurn(data: net.openTurn(match), localIndex: local)
        if let problem = opened.problem {
            net.turnNote = problem
            net.dropCurrentTurn()
            return
        }
        transition { [weak self] in
            guard let self else { return }
            self.multiplayerOpen = false
            self.openCustomize(.zones, local: local, turnBased: true, other: opened.other)
        }
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
        case .mode(let mode):
            UserDefaults.standard.set(Int(mode.rawValue), forKey: GameScene.onlineModeKey)
            SoundBoard.shared.play(SoundBoard.navigate)
            if mode == .zones { net.loadTurnMatches() }
            objectWillChange.send()
        case .playNow:
            SoundBoard.shared.play(SoundBoard.confirm)
            if zonesOnlinePicked {
                net.newTurnMatch(with: nil) { [weak self] match in if let match { self?.openZonesTurn(match) } }
                return
            }
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
            if zonesOnlinePicked {
                multiplayerPage = .menu
                net.newTurnMatch(with: friend) { [weak self] match in if let match { self?.openZonesTurn(match) } }
                return
            }
            net.invite(friend)
            multiplayerCursor = 0
        case .turnMatch(let id):
            // On its turn, played; over, taken off the list; theirs, nothing to do yet.
            guard let match = net.turnMatches.first(where: { $0.matchID == id }) else { return }
            if match.status == .ended {
                SoundBoard.shared.play(.menuBack)
                net.quitTurnMatch(match)
            } else if net.isLocalTurn(match) {
                SoundBoard.shared.play(SoundBoard.confirm)
                openZonesTurn(match)
            } else {
                SoundBoard.shared.play(SoundBoard.navigate)
            }
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
        case .bestOfSeven, .fortySeven, .zones:
            guard !busy else { return }
            SoundBoard.shared.play(SoundBoard.confirm)
            let mode: GameMode = item == .bestOfSeven ? .rounds : item == .fortySeven ? .fortySeven : .zones
            transition { [weak self] in self?.openCustomize(mode) }
        case .vsCPU, .vsHuman:
            guard !busy else { return }
            defaults.set(item == .vsCPU, forKey: GameScene.vsCPUKey)
            SoundBoard.shared.play(SoundBoard.navigate)
        case .multiplayer:
            guard !busy else { return }
            SoundBoard.shared.play(SoundBoard.confirm)
            transition { [weak self] in self?.openMultiplayer() }
        case .tuning:
            tuningOpen.toggle()
        case .titleFont:
            // A/B: the lettering and the small switches in Bigdex or the rounded face.
            TitleText.bigdex.toggle()
            SoundBoard.shared.play(SoundBoard.navigate)
            objectWillChange.send()
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
    case bestOfSeven, fortySeven, zones, vsCPU, vsHuman, multiplayer
    case tuning
    /// The A/B of the title's lettering: the rounded face or Bigdex.
    case titleFont
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
        [.bestOfSeven, .fortySeven, .zones],
        [.vsCPU, .vsHuman],
        [.multiplayer],
    ] + (DebugUI.enabled ? debugRows : [])

    /// The colour grids' tabs and swatches and the UI and FONT switches, in a debug build.
    static let debugRows: [[TitleItem]] = [
        UIColourPicks.Grid.allCases.flatMap { grid in UIColourPicks.Tone.allCases.map { TitleItem.toneTab(grid, $0) } },
    ] + stride(from: 0, to: EsperPalette.swatches.count, by: swatchesPerRow).map { start in
        // The grids side by side, bottom left.
        UIColourPicks.Grid.allCases.flatMap { grid in (start..<start + swatchesPerRow).map { TitleItem.swatch(grid, $0) } }
    } + [
        [.tuning, .titleFont],
    ]
}

/// The title screen, in `Futuristic_UI.svg`'s pieces on the customize screen's ground: the gear in frame 1 in the
/// upper right; the name over rule4; ROUNDS, 47 and ZONES in frames 7, 9 and 6; VS CPU and
/// VS HUMAN between rule5s with rule6 between them; MULTIPLAYER in box4, which opens the
/// multiplayer screen, with Game Center's word under it. What the cursor's on is gold and a
/// tenth bigger.
struct TitleOverlay: View {
    @ObservedObject var flow: FlowState
    @ObservedObject var net: GameCenter
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
            MenuGround(glows: false)
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    Button { flow.activate(.settings) } label: {
                        FuturisticFrame(name: "1", lit: flow.titleCursor == .settings, scale: TitleOverlay.settingsScale * scale(.buttons)) { colour in
                            Image(uiImage: UIImage(named: "ui_icon_settings") ?? UIImage())
                                .renderingMode(.template)
                                .resizable()
                                .interpolation(.high)
                                .foregroundStyle(colour)
                                .frame(width: 30 * TitleOverlay.settingsScale * scale(.buttons), height: 31 * TitleOverlay.settingsScale * scale(.buttons))
                        }
                    }
                    .buttonStyle(.plain)
                    .noSystemFocus()
                    .padding(.top, 14)
                    .padding(.trailing, 18)
                }
                .overlay(alignment: .bottomLeading) {
                    if DebugUI.enabled { colourGrids }
                }
                .overlay(alignment: .bottomTrailing) {
                    if DebugUI.enabled { frameSliders }
                }
            VStack(spacing: 14 * scale(.buttons)) {
                VStack(spacing: 6 * scale(.buttons)) {
                    if DebugUI.enabled {
                        Image(uiImage: UIImage(named: "variaball_logo") ?? UIImage())
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: TitleOverlay.logoHeight * scale(.titles))
                    } else {
                        Text("PROJECT ESPER")
                            .font(Futuristic.font(size: 52 * scale(.titles)))
                            .foregroundStyle(Futuristic.line)
                    }
                    // Two, the left one mirrored, meeting in the middle as one.
                    FuturisticPiece(image: Futuristic.mirroredPair("rule4"), scale: scale(.buttons))
                }
                // ROUNDS in ZONES' frame turned round, 47 in ring5, between arrow2s pointing out.
                HStack(spacing: 18 * scale(.buttons)) {
                    FuturisticPiece(name: "arrow2", scale: scale(.buttons)).scaleEffect(x: -1)
                    framed("ROUNDS", in: "6", mirrored: true, item: .bestOfSeven, drop: roundsFrameDrop, frameScale: roundsFrameScale)
                    framed("47", in: "ring5", item: .fortySeven, drop: fortySevenFrameDrop, frameScale: fortySevenFrameScale)
                    framed("ZONES", in: "6", item: .zones, drop: zonesFrameDrop, frameScale: zonesFrameScale)
                    FuturisticPiece(name: "arrow2", scale: scale(.buttons))
                }
                HStack(spacing: 12 * scale(.buttons)) {
                    rule("rule5", width: TitleOverlay.endRuleWidth).scaleEffect(x: -1, y: -1)
                    plain("VS CPU", picked: vsCPU, item: .vsCPU)
                    rule("rule6", width: TitleOverlay.middleRuleWidth)
                    plain("VS HUMAN", picked: !vsCPU, item: .vsHuman)
                    rule("rule5", width: TitleOverlay.endRuleWidth)
                }
                VStack(spacing: 6) {
                    framed("MULTIPLAYER", in: "box4", item: .multiplayer, textSize: TitleOverlay.multiplayerTextSize,
                           icon: "futuristic_icon_multiplayer")
                        .opacity(busy ? 0.5 : 1)
                    if let caption = net.state.caption {
                        Text(caption)
                            .font(Futuristic.font(size: 12 * scale(.text)))
                            .foregroundStyle(Futuristic.line.opacity(0.8))
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { net.signIn() }
    }

    /// The Variaball logo standing in for the name in a debug build.
    static let logoHeight: CGFloat = 64

    /// The settings gear and its frame against the other pieces.
    static let settingsScale: CGFloat = 0.5

    /// The mode buttons' drop, and their frames' size, the lettering keeping its own; from the
    /// debug sliders, these defaults as tuned.
    /// ROUNDS starts where ZONES is, in the same frame.
    @AppStorage("titleRoundsFrameDrop.2") private var roundsFrameDrop = -20.0
    @AppStorage("titleRoundsFrameScale.2") private var roundsFrameScale = 0.8
    @AppStorage("titleFortySevenFrameDrop.2") private var fortySevenFrameDrop = 0.0
    @AppStorage("titleFortySevenFrameScale.2") private var fortySevenFrameScale = 1.0
    @AppStorage("titleZonesFrameDrop") private var zonesFrameDrop = -20.0
    @AppStorage("titleZonesFrameScale") private var zonesFrameScale = 0.8

    /// The opponent row's rules, by their width in points.
    static let endRuleWidth: CGFloat = 110
    static let middleRuleWidth: CGFloat = 120

    /// MULTIPLAYER's lettering, a little smaller than the modes', under its icon.
    static let multiplayerTextSize: CGFloat = 20
    static let iconHeight: CGFloat = 26

    /// A lettered button in one of the vector's frames, an icon over the lettering if it has one.
    private func framed(_ text: String, in frame: String, mirrored: Bool = false, item: TitleItem, drop: Double = 0, frameScale: Double = 1,
                        textSize: CGFloat = 24, icon: String? = nil) -> some View {
        Button { flow.activate(item) } label: {
            FuturisticFrame(name: frame, lit: flow.titleCursor == item, scale: scale(.buttons), frameScale: frameScale, mirrored: mirrored) { colour in
                VStack(spacing: 4 * scale(.buttons)) {
                    if let icon {
                        Image(uiImage: UIImage(named: icon) ?? UIImage())
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .colorMultiply(colour)
                            .frame(height: TitleOverlay.iconHeight * scale(.buttons))
                    }
                    Text(text)
                        .font(Futuristic.font(size: textSize * scale(.text)))
                        .foregroundStyle(colour)
                        .fixedSize()
                }
            }
        }
        .buttonStyle(.plain)
        .offset(y: drop)
        .disabled(busy)
        .noSystemFocus()
    }

    /// One of the opponent row's words: white when it's the one picked, dim otherwise.
    private func plain(_ text: String, picked: Bool, item: TitleItem) -> some View {
        let lit = flow.titleCursor == item
        return Button { flow.activate(item) } label: {
            Text(text)
                .font(Futuristic.font(size: 18 * scale(.text)))
                .foregroundStyle(lit ? Futuristic.lit : Futuristic.line.opacity(picked ? 1 : TitleOverlay.unpickedOpacity))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .scaleEffect(lit ? Futuristic.litGrowth : 1)
        .noSystemFocus()
    }

    static let unpickedOpacity = 0.4

    /// A rule at a width, its height as the vector has it.
    private func rule(_ name: String, width: CGFloat) -> some View {
        let image = Futuristic.image(name)
        let width = width * scale(.buttons)
        return Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .colorMultiply(Futuristic.line)
            .frame(width: width, height: width * image.size.height / max(image.size.width, 1))
    }

    /// The mode frames' sliders, bottom right: each frame's drop in points and its size.
    @ViewBuilder
    private var frameSliders: some View {
        #if os(iOS)
        VStack(alignment: .trailing, spacing: 4) {
            frameSlider("ROUNDS Y", $roundsFrameDrop, -30...30)
            frameSlider("ROUNDS SCALE", $roundsFrameScale, 0.5...1.5)
            frameSlider("47 Y", $fortySevenFrameDrop, -30...30)
            frameSlider("47 SCALE", $fortySevenFrameScale, 0.5...1.5)
            frameSlider("ZONES Y", $zonesFrameDrop, -30...30)
            frameSlider("ZONES SCALE", $zonesFrameScale, 0.5...1.5)
        }
        .padding(8)
        .background(.black.opacity(0.6))
        .padding(.bottom, 20)
        .padding(.trailing, 24)
        #endif
    }

    #if os(iOS)
    private func frameSlider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 6) {
            pickerLabel("\(label) \(String(format: range.upperBound > 2 ? "%.0f" : "%.2f", value.wrappedValue))")
            SwiftUI.Slider(value: value, in: range, step: range.upperBound > 2 ? 1 : 0.01)
                .frame(width: 140)
        }
    }
    #endif

    /// Under the cursor, the other screens' plates grow this much.
    static let cursorGrowth: CGFloat = 1.08

    /// A debug corner switch: its word over rule8, white when it's on, dim otherwise, gold under the cursor.
    private func debugSwitch(_ text: String, picked: Bool, item: TitleItem) -> some View {
        let lit = flow.titleCursor == item
        let colour = lit ? Futuristic.lit : Futuristic.line.opacity(picked ? 1 : TitleOverlay.unpickedOpacity)
        return Button { flow.activate(item) } label: {
            VStack(spacing: 3) {
                Text(text)
                    .font(Futuristic.font(size: 14 * scale(.text)))
                    .foregroundStyle(colour)
                    .fixedSize()
                rule("rule8", width: TitleOverlay.debugRuleWidth)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(lit ? Futuristic.litGrowth : 1)
        .noSystemFocus()
    }

    static let debugRuleWidth: CGFloat = 80

    /// The UI's colour grids and the UI and FONT switches, bottom left: for working on the game.
    private var colourGrids: some View {
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
            HStack(spacing: 16) {
                debugSwitch("UI", picked: flow.tuningOpen, item: .tuning)
                debugSwitch(TitleText.bigdex ? "FONT B" : "FONT A", picked: TitleText.bigdex, item: .titleFont)
            }
        }
        .padding(.bottom, 20)
        .padding(.leading, 24)
    }

    private func pickerLabel(_ text: String) -> some View {
        Text(text)
            .font(TitleText.switchFont(size: 10))
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 0, x: 1, y: 1)
    }

    /// Which of a grid's three tones it picks: gold under the cursor, plum when it's the grid's.
    private func toneTab(_ grid: UIColourPicks.Grid, _ tone: UIColourPicks.Tone) -> some View {
        let piece = flow.titleCursor == .toneTab(grid, tone) ? UIPiece.buttonGold : (flow.tone(for: grid) == tone ? UIPiece.buttonPlum : UIPiece.buttonBlack)
        return Button { flow.activate(.toneTab(grid, tone)) } label: {
            Text(tone.label)
                .font(TitleText.switchFont(size: 9))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(piece.image(corners: 0.5))
        }
        .buttonStyle(.plain)
        .noSystemFocus()
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
