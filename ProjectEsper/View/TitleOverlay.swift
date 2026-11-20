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
    /// The title screen, before the main menu, up from launch until a tap or a button.
    @Published var titleScreenUp = true
    private var leavingTitleScreen = false
    @Published var veiled = false
    /// BALL OUT called: its Z card across the screen, once a call, gone when it's crossed.
    @Published var ballOutCall: UUID?
    /// The stage preview's name over its big panel, once it's in.
    @Published var previewTitle: String?
    /// The ground under the screen is the palette's black rather than the royal blue: the
    /// Greateraid pick and wait.
    /// The pause's: a third-black wash under a thin dark material over the match.
    @Published var pauseGround = false
    /// The stage select's: the warped grid on black, as the title's.
    @Published var gridGround = false
    /// The win screen's winner and pose, for its stage under the HUD.
    @Published var winFigure: WinFigure?
    /// The UI tuning panel is open.
    @Published var tuningOpen = false
    var startSeries: ((GameMode) -> Void)?
    /// HOW TO PLAY: the Tutorial, straight from the title.
    var startTutorial: (() -> Void)?
    /// The title's cursor, the game's own on every platform: a pad moves it and A picks,
    /// and a tap picks straight away and moves it there.
    @Published var titleCursor = TitleItem.play
    /// The jumbotron's main menu screens' turn in steps, never wrapped, so every turn animates the
    /// way it went; and the swapped-in set's, put back to its first screen at the front each time it goes.
    @Published var screenTurn = 0
    @Published var subTurn = 0
    /// The jumbotron's sets of screens swapped so far, never wrapped: even shows the main menu's,
    /// odd the swapped-in set, `subRing`'s (`JumbotronScreens`).
    @Published var screenSwaps = 0
    /// A swap's flight under way: the screens take nothing till it's done.
    @Published var screensInFlight = false
    /// The set swapped in for the main menu's: PLAY's modes, or VTV's saved replays; each with BACK.
    enum SubRing { case play, vtv }
    @Published var subRing = SubRing.play
    /// VTV's saved replays, newest first, read as VTV opens.
    @Published var replays: [ReplaySummary] = []
    /// VTV's replays being read, before its screens swap in.
    private var replaysLoading = false
    /// A replay picked on VTV being read before it plays.
    private var replayOpening = false
    var subRingShown: Bool { screenSwaps % 2 != 0 }
    var subRingItems: [TitleItem] { subRing == .play ? TitleItem.playRing : replays.indices.map(TitleItem.replay) + [.back] }
    /// A set of screens by its place in `JumbotronScreens`: the main menu's first, then the swapped-in one.
    func screenSet(_ set: Int) -> [TitleItem] { set == 0 ? TitleItem.mainRing : subRingItems }
    /// The screens round the jumbotron now, and their turn.
    var screenRing: [TitleItem] { subRingShown ? subRingItems : TitleItem.mainRing }
    var shownTurn: Int { subRingShown ? subTurn : screenTurn }
    /// The screen at the front of the jumbotron.
    var frontScreen: TitleItem {
        let ring = screenRing, count = ring.count
        return ring[(shownTurn % count + count) % count]
    }
    /// The title's rows, the screens shown in theirs.
    var titleRows: [[TitleItem]] { TitleItem.rows(screens: screenRing) }
    /// The lower rung's turn in steps, as the screens'; and the option at its front.
    @Published var lowerTurn = 0
    var frontLower: TitleItem {
        let count = TitleItem.lowerRung.count
        return TitleItem.lowerRung[(lowerTurn % count + count) % count]
    }

    init() {
        scene.flowState = self
        scene.onLoading = { [weak self] progress in
            guard let self else { return }
            let slots = progress.map { Int($0 * Double(FlowState.loadingSlotCount)) }
            // Told after: a look's change starts a rebuild from inside a view's update.
            DispatchQueue.main.async { if slots != self.loadingSlots { self.loadingSlots = slots } }
        }
        SoundBoard.shared.prepare()
        watchLaunch()
        MemoryTrace.startSampling()
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
        liftAfterHoldLimit()
    }
    /// The held curtain up after `loadingHoldLimit` regardless; but never over the launch's warm-up,
    /// which nothing under it can be used without.
    private func liftAfterHoldLimit() {
        DispatchQueue.main.asyncAfter(deadline: .now() + FlowState.loadingHoldLimit) { [weak self] in
            guard let self, let held = self.heldLift else { return }
            if self.scene.warmingUp { return self.liftAfterHoldLimit() }
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

    /// The curtain stepped to `target` a display frame at a time, each step its own plain change:
    /// a SwiftUI animation of it could be dropped with the screen change made under it (NEW MATCH
    /// off the win screen), leaving the curtain drawn down, black and taking every touch, though
    /// its value was back at 0.
    private var curtainTimer: Timer?
    private func moveCurtain(to target: Double, over seconds: Double, easeIn: Bool, done: (() -> Void)? = nil) {
        curtainTimer?.invalidate()
        let from = curtain, start = CACurrentMediaTime()
        // On the main run loop, so on the main actor.
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                let share = seconds > 0 ? min((CACurrentMediaTime() - start) / seconds, 1) : 1
                let eased = easeIn ? share * share : 1 - (1 - share) * (1 - share)
                self.curtain = from + (target - from) * eased
                if share >= 1 {
                    timer.invalidate()
                    self.curtainTimer = nil
                    done?()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        curtainTimer = timer
    }

    func transition(_ style: ScreenTransition = .fade, holdsForLoading: Bool = false, _ change: @escaping () -> Void) {
        guard !curtainBusy else {
            LoadTrace.mark("curtain busy: queued")
            curtainQueue.append((style, holdsForLoading, change))
            return
        }
        curtainBusy = true
        curtainStyle = style
        // The change only once the curtain's all the way down and drawn so: a heavy one (a stage
        // built) made on a busy main thread before the curtain caught up held the old screen up,
        // frozen, with no loading bar.
        moveCurtain(to: 1, over: style.downSeconds, easeIn: true) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + FlowState.curtainDrawnSeconds) { self?.curtainDown(style, holdsForLoading: holdsForLoading, change) }
        }
    }
    /// A display frame or two for the curtain's full cover to be on the screen before the change.
    static let curtainDrawnSeconds = 0.05

    /// The curtain down: the change made under it, then up again, held for loading if it's to be.
    private func curtainDown(_ style: ScreenTransition, holdsForLoading: Bool, _ change: @escaping () -> Void) {
        change()
        // Held down over anything the change set loading, the bar filling on it, if it's to be.
        let lift = { [weak self] in
            guard let self else { return }
            self.moveCurtain(to: 0, over: style.upSeconds, easeIn: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + style.upSeconds) { [weak self] in
                guard let self else { return }
                self.curtainBusy = false
                if !self.curtainQueue.isEmpty {
                    let next = self.curtainQueue.removeFirst()
                    self.transition(next.0, holdsForLoading: next.1, next.2)
                }
            }
        }
        LoadTrace.mark(holdsForLoading ? "change made, curtain held for loading" : "change made, curtain lifting")
        if holdsForLoading { self.whenLoaded { LoadTrace.mark("loaded, curtain lifting"); lift() } } else { lift() }
    }

    // MARK: The launch

    /// The splash held over everything from launch (`LaunchCover`) until the launch's loading is done
    /// and the main thread has kept time under it a moment, so the title screen shows already moving.
    @Published var launchCovered = true
    /// Ticks in a row on time before the cover lifts, and the longest gap that's on time.
    static let launchSteadyTicks = 20
    static let launchSteadyGap = 0.05
    /// The longest the cover waits for steady ticks once loading's done.
    static let launchSettleLimit = 2.0
    private var launchTimer: Timer?
    private var launchLastTick = 0.0
    private var launchSteadyCount = 0
    private var launchLoadedAt: Double?

    private func watchLaunch() {
        launchLastTick = CACurrentMediaTime()
        // On the main run loop, so a held main thread shows as a late tick.
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                let now = CACurrentMediaTime()
                self.launchSteadyCount = now - self.launchLastTick < FlowState.launchSteadyGap ? self.launchSteadyCount + 1 : 0
                self.launchLastTick = now
                guard !self.scene.launchLoading else {
                    self.launchSteadyCount = 0
                    return
                }
                if self.launchLoadedAt == nil {
                    LoadTrace.mark("launch loaded, warming the menus")
                    self.prewarmMenus()
                    LoadTrace.mark("menus warm, waiting for steady frames")
                }
                let loadedAt = self.launchLoadedAt ?? CACurrentMediaTime()
                self.launchLoadedAt = loadedAt
                guard self.launchSteadyCount >= FlowState.launchSteadyTicks || now - loadedAt > FlowState.launchSettleLimit else { return }
                timer.invalidate()
                self.launchTimer = nil
                LoadTrace.mark("launch loaded, cover lifting")
                self.launchCovered = false
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        launchTimer = timer
    }

    /// What the customize screen's drink select would otherwise make on the main thread as it opens,
    /// made under the launch's splash: the bottles, and each side's figure on the bench, sitting and drinking.
    private func prewarmMenus() {
        let size = CustomizeScreen.fitted(UIScreen.main.bounds.size)
        DrinkPick.prewarm(drinks: sortedDrinks(0), in: size)
        for (player, pick) in shownCustomizations.enumerated() {
            _ = scene.customizeSeated(player: player, look: pick.look, sheet: "player_bench", frame: 0, warming: true)
            for frame in 0..<GameScene.drinkerFrameCount {
                _ = scene.customizeSeated(player: player, look: pick.look, sheet: "player_sit", frame: frame, warming: true)
                _ = scene.customizeSeated(player: player, look: pick.look, sheet: "player_drink", frame: frame, warming: true)
            }
        }
    }

    // MARK: The title screen

    /// On from the title screen to the main menu, under the curtain.
    func leaveTitleScreen() {
        guard titleScreenUp, !leavingTitleScreen, !launchCovered else { return }
        leavingTitleScreen = true
        SoundBoard.shared.play(SoundBoard.confirm)
        transition { [weak self] in
            self?.titleScreenUp = false
            self?.leavingTitleScreen = false
        }
    }

    // MARK: The V-Key

    /// The V-Key's screen, over whatever asked for it: a locked mode, stage or colour. The cursor
    /// on UNLOCK (0) or RESTORE (1).
    @Published var vKeyOpen = false
    @Published var vKeyCursor = 0
    static let vKeyButtons = 2

    func openVKey() {
        guard !vKeyOpen else { return }
        SoundBoard.shared.play(SoundBoard.confirm)
        VKeyStore.shared.note = nil
        vKeyCursor = 0
        vKeyOpen = true
    }

    func closeVKey() {
        guard vKeyOpen, !VKeyStore.shared.busy else { return }
        SoundBoard.shared.play(.menuBack)
        vKeyOpen = false
    }

    /// Bought: the screen goes, and a stage select that's up shows every stage open.
    func vKeyBought() {
        vKeyOpen = false
        scene.showVKeyBought()
        objectWillChange.send()
    }

    func moveVKeyCursor(_ step: Int) {
        let next = min(max(vKeyCursor + step, 0), FlowState.vKeyButtons - 1)
        guard next != vKeyCursor else { return }
        vKeyCursor = next
        SoundBoard.shared.play(SoundBoard.navigate)
    }

    func activateVKey(_ button: Int) {
        guard !VKeyStore.shared.busy else { return }
        vKeyCursor = button
        SoundBoard.shared.play(SoundBoard.confirm)
        if button == 0 { VKeyStore.shared.buy() } else { VKeyStore.shared.restore() }
    }

    // MARK: VTV

    /// VTV's screens in round the jumbotron: a screen a saved replay, newest first, and BACK; read first, then swapped in.
    func openVTV() {
        guard !subRingShown, !screensInFlight, !replaysLoading else { return }
        replaysLoading = true
        SoundBoard.shared.play(SoundBoard.confirm)
        ReplaySummary.load { [weak self] summaries in
            guard let self else { return }
            self.replaysLoading = false
            guard !self.subRingShown, !self.screensInFlight else { return }
            self.replays = summaries
            self.subRing = .vtv
            self.swapScreenSets(1)
        }
    }

    // MARK: THEME

    /// THEME's picker under the jumbotron, the hood picker's colors; and the pad's cursor along it,
    /// a place in `MenuTheme.choices`, picking as it moves.
    @Published var themePickerOpen = false
    @Published var themeCursor = 0

    func openThemePicker() {
        themeCursor = MenuTheme.choices.firstIndex(of: MenuTheme.colour) ?? 0
        withAnimation(.easeOut(duration: TitleOverlay.themePickerFadeSeconds)) { themePickerOpen = true }
    }

    /// Out of the picker, back to THEME.
    func closeThemePicker(sound: SoundBoard.Effect? = .menuBack) {
        guard themePickerOpen else { return }
        if let sound { SoundBoard.shared.play(sound) }
        withAnimation(.easeOut(duration: TitleOverlay.themePickerFadeSeconds)) { themePickerOpen = false }
    }

    /// The pad's cursor a step along the picker, the color under it picked.
    func moveThemeCursor(_ step: Int) {
        let next = min(max(themeCursor + step, 0), MenuTheme.choices.count - 1)
        guard next != themeCursor else { return }
        pickTheme(next)
    }

    /// The menus in the wheel's color at `column`, kept: everything up drawn again in it.
    func pickTheme(_ column: Int) {
        guard MenuTheme.choices.indices.contains(column) else { return }
        themeCursor = column
        guard MenuTheme.choices[column] != MenuTheme.colour else { return }
        MenuTheme.colour = MenuTheme.choices[column]
        SoundBoard.shared.play(SoundBoard.navigate)
        UITuning.shared.touch()
        objectWillChange.send()
    }

    // MARK: The settings

    /// The settings screen, over the title or the pause. Its categories side by side, the cursor on
    /// one; a category open, its button aside and its rows fanned down under it, the cursor on a row
    /// (-1 its button); and a count bumped when a choice changes, so the screen redraws.
    @Published var settingsOpen = false
    @Published var settingsCategoryCursor = 0
    @Published var settingsCategory: GameSettings.Category?
    @Published var settingsCursor = 0
    @Published var settingsVersion = 0
    /// A category opening, in three steps (its button aside, its rows fanned down, their tails and
    /// choices revealed), or closing back through them; input waits meanwhile.
    @Published var settingsAside = false
    @Published var settingsFanned = false
    @Published var settingsRevealed = false
    @Published var settingsAnimating = false
    /// The players drawn again for PLAYER VISIBILITY: the bar up, the buttons dim, input waits.
    @Published var settingsReloading = false
    var settingsLocked: Bool { settingsAnimating || settingsReloading }
    var settingsRows: [GameSettings.Row] { settingsCategory.map(GameSettings.Row.rows) ?? [] }
    /// The steps' lengths, and each row's fan behind the one above it.
    static let settingsAsideSeconds = 0.25
    static let settingsFanSeconds = 0.3
    static let settingsRevealSeconds = 0.3
    static let settingsFanStagger = 0.04

    func openSettings() {
        settingsOpen = true
        settingsCategory = nil
        settingsCategoryCursor = 0
        settingsCursor = 0
        settingsAside = false
        settingsFanned = false
        settingsRevealed = false
        settingsAnimating = false
    }

    /// Back: an open category shut; with none, the screen.
    func closeSettings() {
        guard !settingsLocked else { return }
        if settingsCategory != nil { return closeSettingsCategory() }
        SoundBoard.shared.play(.menuBack)
        settingsOpen = false
    }

    /// A category opened: aside, fanned, revealed, one after another. Other Stuff has nothing yet.
    func openSettingsCategory(_ category: GameSettings.Category) {
        guard !settingsLocked, settingsCategory == nil, !GameSettings.Row.rows(in: category).isEmpty else { return }
        SoundBoard.shared.play(SoundBoard.navigate)
        settingsCategory = category
        settingsCategoryCursor = category.rawValue
        settingsCursor = 0
        settingsAnimating = true
        settingsAside = true
        let fanned = FlowState.settingsAsideSeconds
        let fanEnd = fanned + FlowState.settingsFanSeconds + FlowState.settingsFanStagger * Double(settingsRows.count)
        DispatchQueue.main.asyncAfter(deadline: .now() + fanned) { [weak self] in self?.settingsFanned = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + fanEnd) { [weak self] in self?.settingsRevealed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + fanEnd + FlowState.settingsRevealSeconds) { [weak self] in self?.settingsAnimating = false }
    }

    /// The open category shut, back through its steps: hidden, folded up into its button, back in its place.
    func closeSettingsCategory() {
        guard !settingsLocked, settingsCategory != nil else { return }
        SoundBoard.shared.play(.menuBack)
        settingsAnimating = true
        settingsRevealed = false
        let folded = FlowState.settingsRevealSeconds
        let foldEnd = folded + FlowState.settingsFanSeconds + FlowState.settingsFanStagger * Double(settingsRows.count)
        DispatchQueue.main.asyncAfter(deadline: .now() + folded) { [weak self] in self?.settingsFanned = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + foldEnd) { [weak self] in self?.settingsAside = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + foldEnd + FlowState.settingsAsideSeconds) { [weak self] in
            guard let self else { return }
            self.settingsCategory = nil
            self.settingsAnimating = false
        }
    }

    /// Across the categories, with none open.
    func moveSettingsCategoryCursor(_ step: Int) {
        guard !settingsLocked, settingsCategory == nil else { return }
        let next = min(max(settingsCategoryCursor + step, 0), GameSettings.Category.allCases.count - 1)
        guard next != settingsCategoryCursor else { return }
        settingsCategoryCursor = next
        SoundBoard.shared.play(SoundBoard.navigate)
    }

    /// Up or down a row of the open category, up past the first onto its button; back is the corner arrow, or B.
    func moveSettingsCursor(_ step: Int) {
        guard !settingsLocked, settingsCategory != nil else { return }
        let next = min(max(settingsCursor + step, -1), settingsRows.count - 1)
        guard next != settingsCursor else { return }
        settingsCursor = next
        SoundBoard.shared.play(SoundBoard.navigate)
    }

    /// The cursor's row on to its next choice, or back, round the ends.
    func stepSetting(_ step: Int) {
        let rows = settingsRows
        guard !settingsLocked, rows.indices.contains(settingsCursor) else { return }
        let row = rows[settingsCursor]
        pickSetting(row: settingsCursor, option: (row.picked + step + row.options.count) % row.options.count)
    }

    /// A choice picked, by a tap or the pad. A new PLAYER VISIBILITY draws the players again,
    /// everything waiting till it's all made and on the GPU.
    func pickSetting(row index: Int, option: Int) {
        let rows = settingsRows
        guard !settingsLocked, rows.indices.contains(index) else { return }
        settingsCursor = index
        let changed = rows[index].picked != option
        rows[index].picked = option
        settingsVersion += 1
        SoundBoard.shared.play(SoundBoard.navigate)
        if rows[index] == .playerVisibility, changed {
            settingsReloading = true
            scene.reloadPlayerVisibility { [weak self] in self?.settingsReloading = false }
        }
    }

    // MARK: The customize screen

    /// The customize screen, between the title and the stage select: each side's cursor and
    /// picks, and the mode it starts.
    @Published var customizeOpen = false
    /// What's new for testers (`UpdatesView`), over everything until it's dismissed, once a set of
    /// notes; and the line the pad has scrolled it to.
    @Published var updatesOpen = UpdatesNotes.unseen
    @Published var updatesLine = 0
    /// The build whose notes are shown, its tab: 0 the newest (`UpdatesNotes.builds`).
    @Published var updatesBuild = 0
    var updatesLines: [UpdatesNotes.Line] { UpdatesNotes.builds.indices.contains(updatesBuild) ? UpdatesNotes.builds[updatesBuild].lines : [] }
    /// ZONES' screen over play, while a game's on.
    @Published var zonesHud: ZonesHud?
    @Published var customizeCursors: [CustomizeSpot] = [.skin, .skin]
    @Published var customizations = [PlayerCustomization.saved(0), PlayerCustomization.saved(1)]
    /// Against the computer, its drink tapped for it by hand on the bottles: kept as tapped.
    var computerDrinkByHand = false
    var customizeMode = GameMode.rounds
    /// Online: both sides on the screen at once, this phone editing only its own side
    /// (`customizeLocal`), the other's picks arriving as they're made.
    @Published var customizeOnline = false
    /// ZONES online: this phone's side only, the other's look as their last turn sent it.
    @Published var customizeTurnBased = false
    var customizeLocal = 0
    /// The side the first pad's cursor is on: its own, or against the computer on one pad, the computer's.
    @Published var customizePadSide = 0
    /// Each side's READY, and the moment both were, when the launch animation starts.
    @Published var customizeReady = [false, false]
    /// A mode that picks its drink before play (47): after START, each side's bottles (`DrinkPick`);
    /// each side's cursor on its bottles in the order shown (-1 its sort button) and that order.
    @Published var customizeDrinkPhase = false
    @Published var drinkCursors = [0, 0]
    /// Each side's dice rolling: the bottles raised in turn at random (`rollDrink`) before one stays picked.
    @Published var drinkRolling = [false, false]
    var drinkRolls: [Task<Void, Never>?] = [nil, nil]
    @Published var drinkSorts: [DrinkSort] = [.aToZ, .aToZ]
    var customizePicksDrink: Bool { customizeMode.picksDrinkAhead }
    @Published var customizeLaunch: Date?
    /// Both locked in on the bottles: drinking on the bench (`player_drink`) since then, before the launch.
    @Published var customizeDrinking: Date?
    /// When the figures are down in their corners on the bottles, seated.
    var customizeSeatedAt = Date.distantPast
    /// Locked in: drinking, or launched; nothing more is picked.
    var customizeLocked: Bool { customizeLaunch != nil || customizeDrinking != nil }
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
            return FlowState.onlineModes.map { .mode($0) } + [.playNow, .inviteFriend] + matches
        case .friends: return net.friends.map { .friend($0.gamePlayerID) }
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
        // Game Center's sign-in, first asked for here, not at launch.
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
            guard !GameMode.parked.contains(mode) else { return }
            guard VKey.opens(mode) else { return openVKey() }
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
            // Back on INVITE A FRIEND, past the modes and PLAY NOW.
            multiplayerCursor = FlowState.onlineModes.count + 1
        } else {
            multiplayerOpen = false
        }
    }

    /// The cursor a row up or down, to the item nearest across, or along its row.
    /// The updates screen up again from the title, at its top.
    func openUpdates() {
        scene.resetUpdatesIcons()
        updatesLine = 0
        updatesBuild = 0
        updatesOpen = true
    }

    /// The updates screen put away, its notes marked seen.
    func closeUpdates() {
        guard updatesOpen else { return }
        UserDefaults.standard.set(UpdatesNotes.id, forKey: UpdatesNotes.seenKey)
        SoundBoard.shared.play(SoundBoard.confirm)
        updatesOpen = false
    }

    /// The updates screen's list stepped a line by the pad.
    func scrollUpdates(_ by: Int) {
        updatesLine = min(max(updatesLine + by, 0), max(updatesLines.count - 1, 0))
    }

    /// Another build's notes, from its tab or the pad across them; shown from their top.
    func showUpdatesBuild(_ index: Int) {
        guard UpdatesNotes.builds.indices.contains(index), index != updatesBuild else { return }
        updatesBuild = index
        updatesLine = 0
        SoundBoard.shared.play(SoundBoard.navigate)
    }

    func moveTitleCursor(across: Int, down: Int) {
        let rows = titleRows
        guard let row = rows.firstIndex(where: { $0.contains(titleCursor) }), let column = rows[row].firstIndex(of: titleCursor) else {
            titleCursor = frontScreen
            return
        }
        if across != 0, TitleItem.isScreenRow(rows[row]) { return stepScreenRing(across) }
        if across != 0, TitleItem.isLowerRungRow(rows[row]) { return stepLowerRung(across) }
        var next = titleCursor
        if across != 0 {
            next = rows[row][min(max(column + across, 0), rows[row].count - 1)]
        } else if down != 0 {
            let target = min(max(row + down, 0), rows.count - 1)
            if TitleItem.isScreenRow(rows[target]) {
                next = frontScreen
            } else if TitleItem.isLowerRungRow(rows[target]) {
                next = frontLower
            } else {
                // The same share of the way along the row; from either ring, its middle.
                let ringRow = TitleItem.isScreenRow(rows[row]) || TitleItem.isLowerRungRow(rows[row])
                let share = ringRow || rows[row].count < 2 ? 0.5 : Double(column) / Double(rows[row].count - 1)
                next = rows[target][Int((share * Double(rows[target].count - 1)).rounded())]
            }
        }
        guard next != titleCursor else { return }
        titleCursor = next
        SoundBoard.shared.play(SoundBoard.navigate)
    }

    /// The lower rung turned a step, its next option to the front, the cursor with it.
    func stepLowerRung(_ way: Int) {
        closeThemePicker(sound: nil)
        withAnimation(TitleOverlay.ringTurn) { lowerTurn += way }
        titleCursor = frontLower
        SoundBoard.shared.play(SoundBoard.navigate)
    }

    /// The next open screen round the jumbotron brought to the front, the cursor with it.
    func stepScreenRing(_ way: Int) {
        let choices = screenRing
        guard !screensInFlight, !choices.isEmpty else { return }
        closeThemePicker(sound: nil)
        let from = choices.firstIndex(of: frontScreen) ?? 0
        let next = choices[((from + way) % choices.count + choices.count) % choices.count]
        titleCursor = next
        guard next != frontScreen else { return }
        turnScreenRing(to: next, way: way)
        SoundBoard.shared.play(SoundBoard.navigate)
    }

    /// The ring turned till `item` is at the front: `way`'s way round, or the short way without one.
    private func turnScreenRing(to item: TitleItem, way: Int = 0) {
        let ring = screenRing
        guard let target = ring.firstIndex(of: item), let front = ring.firstIndex(of: frontScreen) else { return }
        var steps = ((target - front) % ring.count + ring.count) % ring.count
        if way < 0, steps > 0 { steps -= ring.count } else if way == 0, steps * 2 > ring.count { steps -= ring.count }
        withAnimation(TitleOverlay.ringTurn) {
            if subRingShown { subTurn += steps } else { screenTurn += steps }
        }
    }

    /// The jumbotron's sets swapped, `way` 1 `subRing`'s in, -1 back out to the main menu's: the going set
    /// flies out round the spindle, fading, and the coming one in after it; the cursor on its front screen.
    private func swapScreenSets(_ way: Int) {
        guard !screensInFlight else { return }
        screensInFlight = true
        withAnimation(TitleOverlay.screenSwap) { screenSwaps += way }
        titleCursor = frontScreen
        DispatchQueue.main.asyncAfter(deadline: .now() + TitleOverlay.screenSwapSeconds) { [weak self] in
            guard let self else { return }
            self.screensInFlight = false
            // The swapped-in set back to its first screen at the front, out of sight, for next time.
            if !self.subRingShown { self.subTurn = 0 }
        }
    }

    /// PLAY's screens in round the jumbotron: the modes, and BACK.
    func openPlayRing() {
        guard !subRingShown, !screensInFlight, !replaysLoading else { return }
        SoundBoard.shared.play(SoundBoard.confirm)
        subRing = .play
        swapScreenSets(1)
    }

    /// Back out of PLAY's or VTV's screens to the main menu's, the one left at the front and the cursor on it.
    func leaveSubRing() {
        guard subRingShown, !screensInFlight else { return }
        SoundBoard.shared.play(.menuBack)
        swapScreenSets(-1)
    }

    /// What picking an item does, from the pad or a tap. A screen or a lower rung option off the
    /// front is turned to first.
    func activate(_ item: TitleItem) {
        if item != .theme { closeThemePicker(sound: nil) }
        // A screen not round the jumbotron now, or any while a swap's flying, takes nothing.
        if TitleItem.isScreen(item), !screenRing.contains(item) || screensInFlight { return }
        if screenRing.contains(item), item != frontScreen {
            titleCursor = item
            turnScreenRing(to: item)
            SoundBoard.shared.play(SoundBoard.navigate)
            return
        }
        if TitleItem.lowerRung.contains(item), item != frontLower {
            let count = TitleItem.lowerRung.count
            var steps = ((TitleItem.lowerRung.firstIndex(of: item) ?? 0) - (TitleItem.lowerRung.firstIndex(of: frontLower) ?? 0) + count) % count
            // The short way round.
            if steps * 2 > count { steps -= count }
            withAnimation(TitleOverlay.ringTurn) { lowerTurn += steps }
            titleCursor = item
            SoundBoard.shared.play(SoundBoard.navigate)
            return
        }
        titleCursor = item
        let busy: Bool
        switch net.state {
        // Signing in holds nothing up: it only starts from the multiplayer screen.
        case .finding, .connecting, .connected: busy = true
        default: busy = false
        }
        let defaults = UserDefaults.standard
        switch item {
        case .bestOfSeven, .fortySeven, .zones, .breakerBall:
            guard !busy, !(item == .zones && GameMode.parked.contains(.zones)) else { return }
            let mode: GameMode = switch item {
            case .bestOfSeven: .rounds
            case .fortySeven: .fortySeven
            case .breakerBall: .breakerBall
            default: .zones
            }
            guard VKey.opens(mode) else { return openVKey() }
            SoundBoard.shared.play(SoundBoard.confirm)
            transition { [weak self] in self?.openCustomize(mode) }
        case .play:
            guard !busy else { return }
            openPlayRing()
        case .back:
            leaveSubRing()
        case .vtv:
            openVTV()
        case .replay(let index):
            guard !busy, !replayOpening, replays.indices.contains(index) else { return }
            replayOpening = true
            SoundBoard.shared.play(SoundBoard.confirm)
            replays[index].read { [weak self] file in
                guard let self else { return }
                self.replayOpening = false
                guard let file else { return SoundBoard.shared.play(.menuBack) }
                self.transition(holdsForLoading: true) { [weak self] in self?.scene.watchReplay(file) }
            }
        case .multiplayer:
            guard !busy else { return }
            SoundBoard.shared.play(SoundBoard.confirm)
            transition { [weak self] in self?.openMultiplayer() }
        case .howToPlay:
            guard !busy else { return }
            SoundBoard.shared.play(SoundBoard.confirm)
            transition(holdsForLoading: true) { [weak self] in self?.startTutorial?() }
        case .updates:
            SoundBoard.shared.play(SoundBoard.confirm)
            openUpdates()
        case .theme:
            if themePickerOpen {
                closeThemePicker(sound: SoundBoard.confirm)
            } else {
                SoundBoard.shared.play(SoundBoard.confirm)
                openThemePicker()
            }
        case .tuning:
            tuningOpen.toggle()
        case .capture:
            defaults.set(!defaults.bool(forKey: GameScene.captureModeKey), forKey: GameScene.captureModeKey)
            SoundBoard.shared.play(SoundBoard.navigate)
        case .cpuVersusCPU:
            defaults.set(!defaults.bool(forKey: GameScene.cpuVersusCPUKey), forKey: GameScene.cpuVersusCPUKey)
            SoundBoard.shared.play(SoundBoard.navigate)
        case .vKeyLocked:
            VKeyStore.shared.debugToggleLocked()
            SoundBoard.shared.play(SoundBoard.navigate)
            objectWillChange.send()
        case .titleFont:
            // The menus' face on to the next, A to K round (`Futuristic.typefaces`), everything in it drawn again.
            Futuristic.typefacePick = (Futuristic.typefacePick + 1) % Futuristic.typefaces.count
            SoundBoard.shared.play(SoundBoard.navigate)
            UITuning.shared.touch()
            objectWillChange.send()
        case .settings:
            SoundBoard.shared.play(SoundBoard.confirm)
            openSettings()
        case .mute:
            GameSettings.muted.toggle()
            SoundBoard.shared.applyVolume()
            LoopedTrack.applySettings()
            SoundBoard.shared.play(SoundBoard.navigate)
            objectWillChange.send()
        }
    }
}

/// Everything on the title the cursor can land on, row by row as they're laid out.
enum TitleItem: Hashable {
    /// The main menu's screens: PLAY's own screens in, ONLINE, and VTV's replays in.
    case play, multiplayer, vtv
    /// VTV's screens: a saved replay each, by its place in `FlowState.replays`; BACK after them.
    case replay(Int)
    /// PLAY's screens: the modes, and BACK out to the main menu's. ZONES is parked off both.
    case bestOfSeven, fortySeven, zones, breakerBall, back
    /// The Tutorial, over the title.
    case howToPlay
    /// What's new for testers, opened again: CHANGELOG on the rung.
    case updates
    /// The menus' color, picked under the jumbotron (`MenuTheme`).
    case theme
    case tuning
    /// The menus' face, stepped on A to K.
    case titleFont
    /// Capture Mode on and off (`GameScene.captureModeKey`), CPU VS CPU (`GameScene.cpuVersusCPUKey`), and the
    /// V-Key taken away to see free to try (`VKey.debugLockedKey`).
    case capture, cpuVersusCPU, vKeyLocked
    /// The gear in the upper right corner, opening the settings; the speaker in the upper left, muting everything.
    case settings, mute

    /// The jumbotron's screens round it, in order: the main menu's, and PLAY's, its modes then BACK;
    /// new modes join PLAY's.
    static let mainRing: [TitleItem] = [.play, .multiplayer, .vtv]
    static let playRing: [TitleItem] = [.bestOfSeven, .fortySeven, .breakerBall, .back]
    static func isScreen(_ item: TitleItem) -> Bool {
        if case .replay = item { return true }
        return mainRing.contains(item) || playRing.contains(item)
    }
    static func isScreenRow(_ row: [TitleItem]) -> Bool { row.contains(where: isScreen) }
    /// The lower rung's options round it; more will join.
    static let lowerRung: [TitleItem] = [.updates, .howToPlay, .theme]
    static func isLowerRungRow(_ row: [TitleItem]) -> Bool { row.contains { lowerRung.contains($0) } }

    /// The rows with `screens` the jumbotron's shown.
    static func rows(screens: [TitleItem]) -> [[TitleItem]] {
        [[.mute, .settings], screens, lowerRung] + (DebugUI.enabled ? debugRows : [])
    }

    /// The UI, FONT, CAPTURE, CPU VS CPU and V-KEY switches, in a debug build.
    static let debugRows: [[TitleItem]] = [
        [.tuning, .titleFont, .capture, .cpuVersusCPU, .vKeyLocked],
    ]
}

/// The main menu, on the customize screen's ground: the mute and the gear in frame 1 in the upper
/// corners; the jumbotron (`Jumbotron.swift`), its screens PLAY, ONLINE and VTV, PLAY and VTV swapping
/// them for the modes or the saved replays, and BACK, turned by the arrow2s either side or left and right with them under the
/// cursor, and its lower rung CHANGELOG, HOW TO PLAY and THEME, turned on its own, THEME's picker
/// under it; the Variaball logo small, bottom left. What the cursor's on is gold.
struct TitleOverlay: View {
    @ObservedObject var flow: FlowState
    @ObservedObject var net: GameCenter
    @AppStorage(GameScene.captureModeKey) private var captureMode = false
    @AppStorage(GameScene.cpuVersusCPUKey) private var cpuVersusCPU = false
    @ObservedObject private var tuning = UITuning.shared
    private func scale(_ part: UIPart) -> CGFloat { tuning.scale(.title, part) }

    private var busy: Bool {
        switch net.state {
        case .finding, .connecting, .connected: true
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
                            Image(systemName: "gearshape")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(colour)
                                .frame(width: 30 * TitleOverlay.settingsScale * scale(.buttons), height: 31 * TitleOverlay.settingsScale * scale(.buttons))
                        }
                    }
                    .buttonStyle(.plain)
                    .noSystemFocus()
                    .padding(.top, 14)
                    .padding(.trailing, 18)
                }
                .overlay(alignment: .topLeading) {
                    Button { flow.activate(.mute) } label: {
                        // The gear's frame turned round, its lead to the other side.
                        FuturisticFrame(name: "1", lit: flow.titleCursor == .mute, scale: TitleOverlay.settingsScale * scale(.buttons), mirrored: true) { colour in
                            Image(systemName: GameSettings.muted ? "speaker.slash.fill" : "speaker.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(colour)
                                .frame(width: 30 * TitleOverlay.settingsScale * scale(.buttons), height: 31 * TitleOverlay.settingsScale * scale(.buttons))
                        }
                    }
                    .buttonStyle(.plain)
                    .noSystemFocus()
                    .padding(.top, 14)
                    .padding(.leading, 18)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(uiImage: UIImage(named: "variaball_logo") ?? UIImage())
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: TitleOverlay.logoHeight * scale(.titles))
                            .padding(.leading, 24)
                            .padding(.bottom, (DebugUI.enabled ? 0 : 20) + TitleOverlay.logoLift)
                        if DebugUI.enabled { debugSwitches }
                    }
                }
            GeometryReader { geometry in
                let layout = JumbotronLayout(size: geometry.size)
                ZStack(alignment: .topLeading) {
                    JumbotronScreens(turns: AnimatablePair(Double(flow.screenTurn), Double(flow.subTurn)), swaps: Double(flow.screenSwaps),
                                     counts: [flow.screenSet(0).count, flow.screenSet(1).count], layout: layout) { set, index, size in
                        jumbotronScreen(screenItem(set, index), size: size, unit: layout.unit)
                    } picture: { set, index, size in
                        jumbotronPicture(screenItem(set, index), size: size, unit: layout.unit)
                    }
                    LowerRung(turn: Double(flow.lowerTurn), labels: TitleItem.lowerRung.map(TitleOverlay.lowerRungLabel),
                              lit: TitleItem.lowerRung.contains(flow.titleCursor) && !flow.themePickerOpen, layout: layout)
                    if flow.themePickerOpen {
                        themePicker(layout)
                            .transition(.opacity)
                    }
                    #if os(iOS)
                    tapCatcher(layout)
                        .offset(x: layout.point(JumbotronLayout.centreX - JumbotronLayout.screensTopRadius, 0).x,
                                y: layout.point(0, JumbotronLayout.screensTopY - JumbotronLayout.screensTopBow).y)
                    #endif
                    ringArrow(way: -1)
                        .position(layout.point(JumbotronLayout.centreX - JumbotronLayout.screensTopRadius - JumbotronLayout.arrowGap, JumbotronLayout.arrowY))
                    ringArrow(way: 1)
                        .position(layout.point(JumbotronLayout.centreX + JumbotronLayout.screensTopRadius + JumbotronLayout.arrowGap, JumbotronLayout.arrowY))
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
    }

    /// The Variaball logo, small in the bottom left corner.
    static let logoHeight: CGFloat = 24
    /// How far it sits up off the bottom, over what's there already.
    static let logoLift: CGFloat = 48

    static func lowerRungLabel(_ item: TitleItem) -> String {
        switch item {
        case .updates: "CHANGELOG"
        case .theme: "THEME"
        default: "HOW TO PLAY"
        }
    }

    static func screenTitle(_ item: TitleItem) -> String {
        switch item {
        case .play: "PLAY"
        case .vtv: "V-TV"
        case .bestOfSeven: "ROUNDS"
        case .fortySeven: "47"
        case .zones: "ZONES"
        case .breakerBall: "BREAKER BALL"
        case .back: "BACK"
        case .replay: "REPLAY"
        default: "ONLINE"
        }
    }

    /// A set's screen at its place, BACK where the set's changed under it.
    private func screenItem(_ set: Int, _ index: Int) -> TitleItem {
        let items = flow.screenSet(set)
        return items.indices.contains(index) ? items[index] : .back
    }

    /// A VTV screen's replay.
    private func replaySummary(_ item: TitleItem) -> ReplaySummary? {
        guard case .replay(let index) = item, flow.replays.indices.contains(index) else { return nil }
        return flow.replays[index]
    }

    /// The mode's name at the top, its description under it, its art below: laid out flat for the
    /// jumbotron to map onto the screen's trapezoid. Gold under the cursor; a parked mode greyed.
    /// No descriptions or art yet: their places are marked. ONLINE's description is Game Center's word.
    /// A replay's: when it was played, and who against whom, the ONLINE icon by it where it was online.
    private func jumbotronScreen(_ item: TitleItem, size: CGSize, unit: CGFloat) -> some View {
        let lit = flow.titleCursor == item
        let colour = lit ? Futuristic.lit : JumbotronLayout.line
        let parked = item == .zones && GameMode.parked.contains(.zones)
        let content = size.width / JumbotronLayout.screenContentSize.width
        let replay = replaySummary(item)
        return VStack(spacing: 5 * content) {
            Text(replay?.dateLine ?? TitleOverlay.screenTitle(item))
                .font(Futuristic.font(size: 15 * content))
                .foregroundStyle(colour)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let replay {
                HStack(spacing: 3 * content) {
                    if replay.online {
                        Image(uiImage: UIImage(named: "futuristic_icon_multiplayer") ?? UIImage())
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .colorMultiply(colour)
                            .frame(height: 9 * content)
                    }
                    Text(replay.matchup)
                        .font(Futuristic.font(size: 9 * content, face: TitleOverlay.subtextFace))
                        .foregroundStyle(JumbotronLayout.line.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            } else if item == .multiplayer {
                if let subtext = onlineSubtext {
                    Text(subtext)
                        .font(Futuristic.font(size: 9 * content, face: TitleOverlay.subtextFace))
                        .foregroundStyle(JumbotronLayout.line.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            } else if item != .back {
                // BACK has no description: its picture's all it says.
                Capsule().fill(JumbotronLayout.line.opacity(0.3)).frame(width: size.width * 0.75, height: 7 * content)
                Capsule().fill(JumbotronLayout.line.opacity(0.3)).frame(width: size.width * 0.52, height: 7 * content)
            }
            // The picture's place, left to `jumbotronPicture` floating in front.
            Spacer(minLength: 0)
        }
        .padding(7 * content)
        .frame(width: size.width, height: size.height)
        // The dark thin material, tinted with the light, or gold under the cursor.
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).opacity(JumbotronLayout.materialOpacity)
                Rectangle().fill((lit ? Futuristic.lit : JumbotronLayout.light).opacity(lit ? 0.08 : 0.07))
            }
        }
        .overlay(Rectangle().strokeBorder(lit ? Futuristic.lit : JumbotronLayout.line.opacity(0.85), lineWidth: JumbotronLayout.lineWidth * content))
        .saturation(parked ? 0 : 1)
        .opacity(parked ? TitleOverlay.parkedOpacity : (busy && TitleOverlay.heldWhileBusy(item) ? 0.5 : 1))
    }

    /// The screens that take nothing while a match is being found or played online: the modes, and PLAY into them.
    static func heldWhileBusy(_ item: TitleItem) -> Bool {
        [.play, .bestOfSeven, .fortySeven, .zones, .breakerBall].contains(item)
    }

    /// The screens' descriptions in a face against the titles': BoldPixels, as the lists' and descriptions' elsewhere.
    static let subtextFace = Futuristic.listFace

    /// A screen's picture, flat and unskewed, floating in front of it: its icon where it has one;
    /// the other modes' art to come, its place marked. Gold under the cursor, as its screen.
    @ViewBuilder
    private func jumbotronPicture(_ item: TitleItem, size: CGSize, unit: CGFloat) -> some View {
        let colour = flow.titleCursor == item ? Futuristic.lit : JumbotronLayout.line
        let parked = item == .zones && GameMode.parked.contains(.zones)
        Group {
            if let replay = replaySummary(item) {
                replayPicture(replay, lit: flow.titleCursor == item, size: size, unit: unit)
            } else if item == .back, let icon = TitleOverlay.screenIcon(item) {
                // Its chevrons turned from pointing left to up: laid out in the box turned, then turned into it.
                Image(uiImage: UIImage(named: icon) ?? UIImage())
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .colorMultiply(colour)
                    .frame(width: size.height, height: size.width)
                    .rotationEffect(.degrees(90))
            } else if let icon = TitleOverlay.screenIcon(item) {
                Image(uiImage: UIImage(named: icon) ?? UIImage())
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .colorMultiply(colour)
            } else {
                Rectangle()
                    .strokeBorder(JumbotronLayout.line.opacity(0.5),
                                  style: StrokeStyle(lineWidth: JumbotronLayout.faintLineWidth * unit, dash: [4 * unit, 3 * unit]))
            }
        }
        .frame(width: size.width, height: size.height)
        .saturation(parked ? 0 : 1)
        .opacity(parked ? TitleOverlay.parkedOpacity : 1)
    }

    /// A replay's picture: the shot of the stage it ended on, and over it player one on the bottom
    /// left corner and player two on the top right, each centred on its corner.
    private func replayPicture(_ replay: ReplaySummary, lit: Bool, size: CGSize, unit: CGFloat) -> some View {
        let pixel = size.height * TitleOverlay.replayFigureHeight / 48
        let side = (48 + 2 * CustomizeFigure.margin) * pixel
        let corners = [CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: 0)]
        return ZStack(alignment: .topLeading) {
            Group {
                if let shot = StageShots.shared.picture(for: replay.stage) {
                    Image(uiImage: shot).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                } else {
                    // A stage whose preview hasn't played here has no shot yet.
                    Rectangle().fill(JumbotronLayout.light.opacity(0.15))
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay(Rectangle().strokeBorder(lit ? Futuristic.lit : JumbotronLayout.line, lineWidth: JumbotronLayout.lineWidth * unit))
            ForEach(0..<min(replay.sides.count, 2), id: \.self) { index in
                let look = replay.sides[index].look
                if let figure = flow.scene.replayFigure(side: index, look: look) {
                    let shown = figure.frame
                    // What's drawn centred on the corner, mirrored for player two, then turned about that middle.
                    let middleX = index == 1 ? 48 - figure.middle.x : figure.middle.x
                    CustomizeFigure(portrait: shown.portrait, look: index == 1 ? look.turnedRound : look, pixel: pixel, mirrored: index == 1,
                                    headNudge: shown.headNudge, headScale: shown.headScale, ball: shown.ball, ballAura: shown.ballAura,
                                    overBall: shown.overBall, overBallLine: shown.overBallLine, still: true)
                        .frame(width: side, height: side)
                        .offset(x: (24 - middleX) * pixel, y: (24 - figure.middle.y) * pixel)
                        .rotationEffect(.degrees(TitleOverlay.replayFigureTurn))
                        .position(corners[index])
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
    /// A replay picture's figures: their art's 48 pixels this share of its height, each centred on its
    /// corner, turned this many degrees anticlockwise (player one to face up and right, player two down and left).
    static let replayFigureHeight: CGFloat = 0.6
    static let replayFigureTurn: Double = -45

    /// The icon floating in front of a screen, where it has one: Breaker Ball's is its HUD barrier, 47's
    /// the Moebius triangle.
    static func screenIcon(_ item: TitleItem) -> String? {
        switch item {
        case .play: "futuristic_icon_play"
        case .multiplayer: "futuristic_icon_multiplayer"
        case .vtv: "futuristic_icon_vtv"
        case .bestOfSeven: "futuristic_icon_rounds"
        case .fortySeven: "futuristic_icon_moebius_triangle"
        case .breakerBall: "futuristic_icon_shatter"
        case .back: "futuristic_icon_screen_back"
        default: nil
        }
    }

    /// THEME's picker under the lower rung, the customize screen's hood picker in its first side's
    /// display: every color but white free, the pick and the pad's cursor in white. A tap or a slide picks;
    /// the pick tapped again puts it away.
    private func themePicker(_ layout: JumbotronLayout) -> some View {
        let frames = SwatchPicker.firstSideFrames(centre: layout.point(JumbotronLayout.centreX, JumbotronLayout.themePickerY),
                                                  width: JumbotronLayout.themePickerWidth * layout.unit)
        let picked = MenuTheme.choices.firstIndex(of: MenuTheme.colour) ?? 0
        return ZStack(alignment: .topLeading) {
            SwatchPicker(display: "customize_p1_display", displayFrame: frames.display, barFrame: frames.bar,
                         barColour: MenuTheme.colour.glow, columns: MenuTheme.choices.map { (top: $0.glow, accent: $0.rampDown) },
                         picked: picked, hovered: flow.themeCursor, cursorColour: 0xFFFFFF,
                         pick: { index in flow.pickTheme(index) },
                         confirmed: { _ in flow.closeThemePicker(sound: SoundBoard.confirm) })
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    /// THEME's picker coming and going.
    static let themePickerFadeSeconds = 0.2

    /// ONLINE's description: Game Center's word, signed out what the screen does.
    private var onlineSubtext: String? {
        if case .signedOut = net.state { return "SIGNS IN TO GAME CENTER" }
        return net.state.caption
    }

    #if os(iOS)
    /// Taps and swipes on the jumbotron. A tap: a screen facing out is picked (turned to first, if it
    /// isn't at the front); on the lower rung, the front option's picked and either end turns it.
    /// A swipe across either ring turns it a step, the way the finger went.
    private func tapCatcher(_ layout: JumbotronLayout) -> some View {
        // Over the jumbotron alone, so the corners' buttons still take their own taps.
        let topLeft = layout.point(JumbotronLayout.centreX - JumbotronLayout.screensTopRadius,
                                   JumbotronLayout.screensTopY - JumbotronLayout.screensTopBow)
        let bottomRight = layout.point(JumbotronLayout.centreX + JumbotronLayout.screensTopRadius,
                                       JumbotronLayout.rungBottomY + JumbotronLayout.rungBow)
        let area = CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
        return Color.clear
            .contentShape(Rectangle())
            .frame(width: area.width, height: area.height)
            // One drag reads both, so neither gesture swallows the other.
            .gesture(DragGesture(minimumDistance: 0).onEnded { drag in
                let start = CGPoint(x: drag.startLocation.x + area.minX, y: drag.startLocation.y + area.minY)
                let horizontalTravel = drag.translation.width, verticalTravel = drag.translation.height
                if hypot(horizontalTravel, verticalTravel) < TitleOverlay.tapSlop {
                    tapped(at: start, layout)
                } else if abs(horizontalTravel) >= TitleOverlay.swipeDistance, abs(horizontalTravel) > abs(verticalTravel) {
                    // Swiped left, the next option on the right comes round to the front.
                    swiped(from: start, way: horizontalTravel < 0 ? 1 : -1, layout)
                }
            })
    }

    private func onLowerRung(_ point: CGPoint, _ layout: JumbotronLayout) -> Bool {
        let rungLeft = layout.point(JumbotronLayout.centreX - JumbotronLayout.rungRadius, 0).x
        let rungRight = layout.point(JumbotronLayout.centreX + JumbotronLayout.rungRadius, 0).x
        let rungTop = layout.point(0, JumbotronLayout.rungTopY - JumbotronLayout.rungBow).y
        let rungBottom = layout.point(0, JumbotronLayout.rungBottomY + JumbotronLayout.rungBow).y
        return (rungLeft...rungRight).contains(point.x) && (rungTop...rungBottom).contains(point.y)
    }

    private func tapped(at point: CGPoint, _ layout: JumbotronLayout) {
        if onLowerRung(point, layout) {
            let across = (point.x - layout.point(JumbotronLayout.centreX, 0).x) / (JumbotronLayout.rungRadius * layout.unit)
            if abs(across) < TitleOverlay.rungFrontShare { flow.activate(flow.frontLower) } else { flow.stepLowerRung(across > 0 ? 1 : -1) }
            return
        }
        // The screens at rest only: none mid-swap.
        guard !flow.screensInFlight else { return }
        let ring = flow.screenRing
        let count = ring.count
        let span = JumbotronLayout.screenSpan(count: count)
        let facingOut = (0..<count)
            .map { (index: $0, angle: JumbotronScreens<EmptyView, EmptyView>.angle(of: $0, turn: Double(flow.shownTurn), count: count)) }
            .filter { cos($0.angle) > 0.05 }
            .sorted { cos($0.angle) > cos($1.angle) }
        if let hit = facingOut.first(where: { JumbotronLayout.contains(layout.screenCorners(angle: $0.angle, span: span), point) }) {
            flow.activate(ring[hit.index])
        }
    }

    /// The ring the swipe started on turned a step; the screens held still while busy, as their arrows are.
    private func swiped(from point: CGPoint, way: Int, _ layout: JumbotronLayout) {
        if onLowerRung(point, layout) {
            flow.stepLowerRung(way)
        } else if !busy, !flow.screensInFlight {
            flow.stepScreenRing(way)
        }
    }

    /// The middle of the lower rung, a share of its half width, that picks the front option.
    static let rungFrontShare: CGFloat = 0.6
    /// A touch that moves less than this, in points, is a tap.
    static let tapSlop: CGFloat = 10
    /// How far across a swipe goes, in points, to turn a ring.
    static let swipeDistance: CGFloat = 30
    #endif

    /// An arrow2 beside the jumbotron, pointing out, turning its screens that way.
    private func ringArrow(way: Int) -> some View {
        Button { flow.stepScreenRing(way) } label: {
            FuturisticPiece(name: "arrow2", scale: TitleOverlay.arrowScale * scale(.buttons))
                .scaleEffect(x: CGFloat(way))
        }
        .buttonStyle(.plain)
        .disabled(busy || flow.screensInFlight)
        .noSystemFocus()
    }

    /// The jumbotron's turn, its screens' and its lower rung's.
    static let ringTurn = Animation.spring(response: 0.45, dampingFraction: 0.8)
    /// A swap of the jumbotron's sets, out and in: quickening as the going set flies out, slowing as
    /// the coming one comes to rest (`JumbotronLayout.flightSpread`, `flightTurn`).
    static let screenSwapSeconds = 0.7
    static let screenSwap = Animation.easeInOut(duration: screenSwapSeconds)

    /// The settings gear and its frame against the other pieces.
    static let settingsScale: CGFloat = 0.5
    static let arrowScale: CGFloat = 0.6

    static let parkedOpacity = 0.35

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
        .noSystemFocus()
    }

    static let debugRuleWidth: CGFloat = 80

    /// The UI and FONT switches, bottom left: for working on the game.
    private var debugSwitches: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                debugSwitch("UI", picked: flow.tuningOpen, item: .tuning)
                debugSwitch("FONT " + String(UnicodeScalar(UInt8(65 + Futuristic.typefacePick))), picked: true, item: .titleFont)
                debugSwitch("CAPTURE", picked: captureMode, item: .capture)
                debugSwitch("CPU VS CPU", picked: cpuVersusCPU, item: .cpuVersusCPU)
                debugSwitch("V-KEY", picked: VKey.owned, item: .vKeyLocked)
            }
        }
        .padding(.bottom, 20)
        .padding(.leading, 24)
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
