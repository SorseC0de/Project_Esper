import GameKit
import UIKit

/// Game Center: signing in, finding the other phone through Apple's matchmaker, and the
/// match between them. Bytes go in and out here; the scene makes sense of them.
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
                } else {
                    self.state = .failed(error.map { self.short($0) } ?? "Not signed in")
                }
            }
        }
    }

    /// Apple's matchmaker sheet: invite a friend or automatch, for two. It needs the
    /// app's record in App Store Connect with Game Center on, or it fails at once.
    func findMatch() {
        guard GKLocalPlayer.local.isAuthenticated else {
            signIn()
            return
        }
        guard match == nil, state != .finding else { return }
        if GKLocalPlayer.local.isMultiplayerGamingRestricted {
            state = .failed("Multiplayer is off in Screen Time")
            return
        }
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.defaultNumberOfPlayers = 2
        request.inviteMessage = "Project Esper: best of seven?"
        guard let controller = GKMatchmakerViewController(matchRequest: request) else { return }
        controller.matchmakerDelegate = self
        state = .finding
        present(controller)
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

extension GameCenter: GKMatchmakerViewControllerDelegate {
    nonisolated func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        DispatchQueue.main.async {
            viewController.dismiss(animated: true)
            self.state = .ready
        }
    }

    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        DispatchQueue.main.async {
            viewController.dismiss(animated: true)
            self.state = .failed(self.short(error))
        }
    }

    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        DispatchQueue.main.async {
            viewController.dismiss(animated: true)
            self.take(match)
        }
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
    /// An invite accepted from Game Center's own UI: straight into the matchmaker with it.
    nonisolated func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        DispatchQueue.main.async {
            guard self.match == nil, let controller = GKMatchmakerViewController(invite: invite) else { return }
            controller.matchmakerDelegate = self
            self.state = .finding
            self.present(controller)
        }
    }
}
