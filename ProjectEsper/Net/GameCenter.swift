import GameKit
import UIKit

/// Game Center: signing in, finding the other phone through GameKit's matchmaker behind the
/// game's own multiplayer screen (play now, or invite a friend and hear back), and the match
/// between them. Bytes go in and out here; the scene makes sense of them.
@MainActor
final class GameCenter: NSObject, ObservableObject {
    enum State: Equatable {
        case signedOut
        case signingIn
        case ready
        case finding
        case connecting
        case connected
        case failed(String)

        /// What the title says under MULTIPLAYER.
        var caption: String? {
            switch self {
            case .signedOut: "SIGN IN TO GAME CENTER"
            case .signingIn: "SIGNING IN"
            case .ready: nil
            case .finding: "FINDING AN OPPONENT"
            case .connecting: "CONNECTING"
            case .connected: "CONNECTED"
            case .failed(let why): why.uppercased()
            }
        }
    }

    @Published private(set) var state = State.signedOut
    private(set) var match: GKMatch?
    /// Looks in on a match still connecting, since the connection callback doesn't
    /// always come: the count of players still to arrive is read every half second.
    private var connectTimer: Timer?
    /// Bytes from the other phone, on the main thread.
    var onData: ((Data) -> Void)?
    /// The match is on: both phones connected.
    var onConnected: (() -> Void)?
    /// The link broke or they left, with why.
    var onDisconnect: ((String) -> Void)?
    /// An invite was accepted from outside the game: the multiplayer screen shows the joining.
    var onInviteAccepted: (() -> Void)?
    /// Signed in, after being asked to: whatever waited on it goes on.
    var onSignedIn: (() -> Void)?

    // MARK: ZONES, turn by turn

    /// ZONES online goes turn by turn through Game Center's turn-based matches, Words With
    /// Friends fashion: a turn is the game's state and the run set, kept by Game Center and
    /// handed to the other phone; the list of this player's matches, newest first with their
    /// turn first; the one being played; and a note under the list.
    @Published private(set) var turnMatches: [GKTurnBasedMatch] = []
    @Published var turnNote: String?
    private(set) var currentTurnMatch: GKTurnBasedMatch?
    /// A match tapped in a Game Center notification: the multiplayer screen opens on its turn.
    var onTurnTapped: ((GKTurnBasedMatch) -> Void)?

    /// A friend's answer to an invite.
    enum InviteAnswer: Equatable { case waiting, accepted, declined }
    /// Game Center friends to invite, once loaded, and why the list is empty if it is.
    @Published private(set) var friends: [GKPlayer] = []
    @Published private(set) var friendsNote: String?
    /// Who was invited, and how each has answered, by player ID.
    @Published private(set) var invited: [GKPlayer] = []
    @Published private(set) var answers: [String: InviteAnswer] = [:]

    /// Whether this phone sorts first of the two by Game Center's player ID, so plays
    /// the left side; both phones sort the same way.
    var localIsFirst: Bool {
        guard let other = match?.players.first else { return true }
        return GKLocalPlayer.local.gamePlayerID < other.gamePlayerID
    }

    var isConnected: Bool { state == .connected && match != nil }

    func signIn() {
        guard state == .signedOut || { if case .failed = state { return true } else { return false } }() else { return }
        state = .signingIn
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let viewController {
                    self.present(viewController)
                    return
                }
                if GKLocalPlayer.local.isAuthenticated {
                    GKLocalPlayer.local.register(self)
                    if self.state == .signingIn || self.state == .signedOut { self.state = .ready }
                    self.onSignedIn?()
                } else {
                    self.state = .failed(error.map { self.short($0) } ?? "Not signed in")
                }
            }
        }
    }

    /// Whether matching can start: signed in, multiplayer allowed, nothing under way. Signs in
    /// or says why not otherwise.
    private func readyToMatch() -> Bool {
        guard GKLocalPlayer.local.isAuthenticated else {
            signIn()
            return false
        }
        if GKLocalPlayer.local.isMultiplayerGamingRestricted {
            state = .failed("Multiplayer is off in Screen Time")
            return false
        }
        return match == nil && state != .finding
    }

    /// Two players; the app's record in App Store Connect needs Game Center on, or matching
    /// fails at once.
    private func matchRequest() -> GKMatchRequest {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.defaultNumberOfPlayers = 2
        request.inviteMessage = "Project Esper: best of seven?"
        return request
    }

    /// Play now: matched with anyone else looking.
    func playNow() {
        guard readyToMatch() else { return }
        invited = []
        answers = [:]
        state = .finding
        GKMatchmaker.shared().findMatch(for: matchRequest()) { [weak self] found, error in
            DispatchQueue.main.async { self?.finished(found, error) }
        }
    }

    /// The friends list, asked for once; empty with a note if it's off or there are none.
    func loadFriends() {
        friendsNote = "LOADING FRIENDS"
        GKLocalPlayer.local.loadFriendsAuthorizationStatus { [weak self] status, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized || status == .notDetermined else {
                    self.friends = []
                    self.friendsNote = "FRIENDS LIST IS OFF IN SETTINGS"
                    return
                }
                GKLocalPlayer.local.loadFriends { players, error in
                    DispatchQueue.main.async {
                        self.friends = (players ?? []).sorted { $0.displayName < $1.displayName }
                        self.friendsNote = error.map { self.short($0).uppercased() } ?? (self.friends.isEmpty ? "NO GAME CENTER FRIENDS YET" : nil)
                    }
                }
            }
        }
    }

    /// Invites `friend` and waits for them; their answer comes back as it's given.
    func invite(_ friend: GKPlayer) {
        guard readyToMatch() else { return }
        let request = matchRequest()
        request.recipients = [friend]
        request.recipientResponseHandler = { [weak self] player, response in
            DispatchQueue.main.async {
                guard let self else { return }
                self.answers[player.gamePlayerID] = response == .accepted ? .accepted : .declined
                if response != .accepted, self.state == .finding {
                    // Declined, or couldn't be reached: the wait is over.
                    GKMatchmaker.shared().cancel()
                    self.state = .failed("\(player.displayName) can't play")
                }
            }
        }
        invited = [friend]
        answers = [friend.gamePlayerID: .waiting]
        state = .finding
        GKMatchmaker.shared().findMatch(for: request) { [weak self] found, error in
            DispatchQueue.main.async { self?.finished(found, error) }
        }
    }

    /// Stops a search or an invite under way.
    func cancelFinding() {
        guard state == .finding else { return }
        GKMatchmaker.shared().cancel()
        state = .ready
    }

    /// The matchmaker's answer: the match, or why not; a cancel is no failure.
    private func finished(_ found: GKMatch?, _ error: Error?) {
        if let found {
            take(found)
        } else if let error, (error as? GKError)?.code != .cancelled {
            state = .failed(short(error))
        } else if state == .finding {
            state = .ready
        }
    }

    func send(_ data: Data, reliable: Bool) {
        guard let match else { return }
        do {
            try match.sendData(toAllPlayers: data, with: reliable ? .reliable : .unreliable)
        } catch {
            // A send that fails outright is a link that's gone; the delegate says so.
        }
    }

    /// Why the last match ended, lettered under MULTIPLAYER.
    func fail(_ why: String) {
        state = .failed(why)
    }

    /// Off the match, and back to ready.
    func leave() {
        connectTimer?.invalidate()
        connectTimer = nil
        match?.delegate = nil
        match?.disconnect()
        match = nil
        state = GKLocalPlayer.local.isAuthenticated ? .ready : .signedOut
    }

    private func short(_ error: Error) -> String {
        let text = error.localizedDescription
        return text.count > 40 ? String(text.prefix(40)) : text
    }

    private func present(_ controller: UIViewController) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let root = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(controller, animated: true)
    }

    private func take(_ found: GKMatch) {
        match = found
        found.delegate = self
        state = .connecting
        connectTimer?.invalidate()
        connectTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.settleIfEveryoneIsHere() }
        }
        settleIfEveryoneIsHere()
    }

    /// Connected once nobody is still expected, or once the other side's bytes arrive,
    /// whichever GameKit shows first; either way only once.
    private func settleIfEveryoneIsHere(dataArrived: Bool = false) {
        guard let match, state == .connecting else { return }
        guard match.expectedPlayerCount == 0 || (dataArrived && !match.players.isEmpty) else {
            // A knock, so the other side settles on our bytes if its count never reaches nought.
            try? match.sendData(toAllPlayers: Data([0]), with: .unreliable)
            return
        }
        connectTimer?.invalidate()
        connectTimer = nil
        state = .connected
        onConnected?()
    }
}

// MARK: - Turn-based

extension GameCenter {
    /// Whether turn-based play can start: signed in and allowed. Signs in or says why not otherwise.
    private func readyForTurns() -> Bool {
        guard GKLocalPlayer.local.isAuthenticated else {
            signIn()
            turnNote = "SIGN IN TO GAME CENTER"
            return false
        }
        if GKLocalPlayer.local.isMultiplayerGamingRestricted {
            turnNote = "MULTIPLAYER IS OFF IN SCREEN TIME"
            return false
        }
        return true
    }

    /// This player's matches: those on their turn first, then the rest, newest first.
    func loadTurnMatches() {
        guard readyForTurns() else { return }
        turnNote = "LOADING MATCHES"
        GKTurnBasedMatch.loadMatches { [weak self] matches, error in
            DispatchQueue.main.async {
                guard let self else { return }
                let loaded = (matches ?? []).sorted { a, b in
                    let aMine = self.isLocalTurn(a), bMine = self.isLocalTurn(b)
                    if aMine != bMine { return aMine }
                    return (a.creationDate ?? .distantPast) > (b.creationDate ?? .distantPast)
                }
                self.turnMatches = loaded
                self.turnNote = error.map { self.short($0).uppercased() } ?? (loaded.isEmpty ? "NO MATCHES YET" : nil)
            }
        }
    }

    /// A new match: with `friend`, or with anyone looking, who Game Center finds once the
    /// first turn is sent. The match comes back to be played.
    func newTurnMatch(with friend: GKPlayer?, _ done: @escaping (GKTurnBasedMatch?) -> Void) {
        guard readyForTurns() else { return done(nil) }
        let request = matchRequest()
        request.inviteMessage = "Project Esper: ZONES?"
        if let friend { request.recipients = [friend] }
        turnNote = "MAKING A MATCH"
        GKTurnBasedMatch.find(for: request) { [weak self] match, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error { self.turnNote = self.short(error).uppercased() } else { self.turnNote = nil }
                if let match { self.turnMatches.insert(match, at: 0) }
                done(match)
            }
        }
    }

    /// The side this phone plays in a match: its place among the participants, the maker first.
    func localIndex(in match: GKTurnBasedMatch) -> Int {
        match.participants.firstIndex { $0.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID } ?? 0
    }

    func isLocalTurn(_ match: GKTurnBasedMatch) -> Bool {
        match.status == .open && match.currentParticipant?.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID
    }

    /// The other side's name, or who they'll be.
    func otherName(in match: GKTurnBasedMatch) -> String {
        let local = localIndex(in: match)
        let other = match.participants.indices.contains(1 - local) ? match.participants[1 - local] : nil
        return other?.player?.displayName.uppercased() ?? "ANYONE"
    }

    /// What a match's row says: whose turn, or how it ended.
    func turnLine(for match: GKTurnBasedMatch) -> String {
        let local = localIndex(in: match)
        switch match.status {
        case .ended:
            let mine = match.participants.indices.contains(local) ? match.participants[local].matchOutcome : .none
            return mine == .won ? "OVER: YOU WON" : mine == .lost ? "OVER: YOU LOST" : "OVER"
        case .matching:
            return isLocalTurn(match) ? "YOUR TURN" : "FINDING AN OPPONENT"
        default:
            return isLocalTurn(match) ? "YOUR TURN" : "THEIR TURN"
        }
    }

    /// The match being played: its turn data, or nothing for a new one.
    func openTurn(_ match: GKTurnBasedMatch) -> Data? {
        currentTurnMatch = match
        return match.matchData.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var others: [GKTurnBasedParticipant] {
        guard let match = currentTurnMatch else { return [] }
        return match.participants.filter { $0.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID }
    }

    /// The turn's state kept mid-turn, so leaving and coming back resumes it.
    func saveCurrentTurn(_ data: Data) {
        currentTurnMatch?.saveCurrentTurn(withMatch: data) { _ in }
    }

    /// The turn over: the state to the other side, who's told.
    func endCurrentTurn(_ data: Data, _ done: @escaping (String?) -> Void) {
        guard let match = currentTurnMatch else { return done("NO MATCH") }
        match.endTurn(withNextParticipants: others, turnTimeout: GKTurnTimeoutDefault, match: data) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error == nil { self.currentTurnMatch = nil }
                done(error.map { self.short($0).uppercased() })
            }
        }
    }

    /// The game won: the outcomes set and the match ended, by the side whose turn it was.
    func endCurrentMatch(_ data: Data, winner: Int) {
        guard let match = currentTurnMatch else { return }
        for (index, participant) in match.participants.enumerated() {
            participant.matchOutcome = index == winner ? .won : .lost
        }
        match.endMatchInTurn(withMatch: data) { [weak self] _ in
            DispatchQueue.main.async { self?.currentTurnMatch = nil; self?.loadTurnMatches() }
        }
    }

    /// Out of a match: quit, in turn or not, and the match off the list.
    func quitTurnMatch(_ match: GKTurnBasedMatch) {
        let finish: (Error?) -> Void = { [weak self] _ in
            match.remove { _ in DispatchQueue.main.async { self?.loadTurnMatches() } }
        }
        if match.status == .ended {
            finish(nil)
        } else if isLocalTurn(match) {
            let next = match.participants.filter { $0.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID }
            match.participantQuitInTurn(with: .quit, nextParticipants: next, turnTimeout: GKTurnTimeoutDefault, match: match.matchData ?? Data(), completionHandler: finish)
        } else {
            match.participantQuitOutOfTurn(with: .quit, withCompletionHandler: finish)
        }
        if currentTurnMatch?.matchID == match.matchID { currentTurnMatch = nil }
    }

    func dropCurrentTurn() { currentTurnMatch = nil }
}

extension GameCenter: GKTurnBasedEventListener {
    /// A turn came in, or a match's over: the list again; tapped in a notification, the match opens.
    nonisolated func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        DispatchQueue.main.async {
            self.loadTurnMatches()
            if didBecomeActive { self.onTurnTapped?(match) }
        }
    }

    nonisolated func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        DispatchQueue.main.async { self.loadTurnMatches() }
    }

    nonisolated func player(_ player: GKPlayer, wantsToQuitMatch match: GKTurnBasedMatch) {
        DispatchQueue.main.async { self.quitTurnMatch(match) }
    }
}

extension GameCenter: GKMatchDelegate {
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        DispatchQueue.main.async {
            guard match === self.match else { return }
            self.settleIfEveryoneIsHere(dataArrived: true)
            self.onData?(data)
        }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        DispatchQueue.main.async {
            guard match === self.match else { return }
            switch state {
            case .connected:
                self.settleIfEveryoneIsHere()
            case .disconnected:
                self.onDisconnect?("DISCONNECTED")
            default:
                break
            }
        }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: Error?) {
        DispatchQueue.main.async {
            guard match === self.match else { return }
            self.onDisconnect?(error.map { self.short($0).uppercased() } ?? "CONNECTION LOST")
        }
    }

    nonisolated func match(_ match: GKMatch, shouldReinviteDisconnectedPlayer player: GKPlayer) -> Bool {
        false
    }
}

extension GameCenter: GKLocalPlayerListener {
    /// An invite accepted from Game Center's own notification: the multiplayer screen opens
    /// on the joining, and the match is made from the invite.
    nonisolated func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        DispatchQueue.main.async {
            guard self.match == nil else { return }
            self.invited = []
            self.answers = [:]
            self.state = .finding
            self.onInviteAccepted?()
            GKMatchmaker.shared().match(for: invite) { [weak self] found, error in
                DispatchQueue.main.async { self?.finished(found, error) }
            }
        }
    }
}
