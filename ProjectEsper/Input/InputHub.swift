import EsperSim
import Foundation
import GameController

/// Where each player's input comes from. On a phone the touch controls are player 0; one
/// controller is player 1, and with two the first is player 0 and the second player 1.
/// On the TV the first controller is player 0 and the second player 1. Everything is
/// read as held state each frame, so nothing queues and nothing is lost between frames.
@MainActor
final class InputHub {
    /// What the on-screen controls hold right now. The scene writes it.
    var touch = PlayerInput.idle
    private(set) var controllers: [GCController] = []
    /// A pad's menu button went down since the last check; the left bumper likewise.
    private(set) var resetPressed = false
    private(set) var cyclePressed = false
    private var menuWasDown = false
    private var bumperWasDown = false
    private var observers: [NSObjectProtocol] = []

    static let stickDeadzone = 0.2

    func activate() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    private func refresh() {
        controllers = GCController.controllers().filter { $0.extendedGamepad != nil }
        #if os(tvOS)
        // On the TV a menu button nobody handles sends the app home, so it's claimed
        // here: it resets, as it does on a phone.
        for controller in controllers {
            controller.extendedGamepad?.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { MainActor.assumeIsolated { self?.resetPressed = true } }
            }
        }
        #endif
    }

    /// This frame's input for every player.
    func frames(players: Int) -> [PlayerInput] {
        #if !os(tvOS)
        let menuDown = controllers.contains { $0.extendedGamepad?.buttonMenu.isPressed ?? false }
        if menuDown, !menuWasDown { resetPressed = true }
        menuWasDown = menuDown
        #endif
        let bumperDown = controllers.contains { $0.extendedGamepad?.leftShoulder.isPressed ?? false }
        if bumperDown, !bumperWasDown { cyclePressed = true }
        bumperWasDown = bumperDown
        return (0..<players).map { index in
            let pad = controller(for: index).map { read($0.extendedGamepad!) } ?? PlayerInput.idle
            return index == 0 ? merge(touch, pad) : pad
        }
    }

    /// The controller that drives this player, by the rule above.
    private func controller(for index: Int) -> GCController? {
        #if os(tvOS)
        return index < controllers.count ? controllers[index] : nil
        #else
        switch (controllers.count, index) {
        case (1, 1): return controllers[0]
        case (1, 0): return nil
        default: return index < controllers.count ? controllers[index] : nil
        }
        #endif
    }

    var playerOneHasController: Bool { controller(for: 0) != nil }
    /// A second person is on a pad: the computer sits out.
    var playerTwoHasController: Bool { controller(for: 1) != nil }

    /// True once per menu press.
    func consumeReset() -> Bool {
        defer { resetPressed = false }
        return resetPressed
    }

    /// True once per left bumper press.
    func consumeCycle() -> Bool {
        defer { cyclePressed = false }
        return cyclePressed
    }

    /// A: jump. B, the right bumper and the right trigger: shoot, each its own button so a
    /// second one cancels a shot. X: throw. Y: taunt. The left bumper steps the tuning
    /// picker, and the menu button resets.
    /// The right stick aims a stance; failing that, the left stick does.
    private func read(_ pad: GCExtendedGamepad) -> PlayerInput {
        var stick = deadzoned(Vec2(x: Double(pad.leftThumbstick.xAxis.value), y: Double(pad.leftThumbstick.yAxis.value)))
        let dpad = Vec2(x: Double(pad.dpad.xAxis.value), y: Double(pad.dpad.yAxis.value))
        if dpad != .zero { stick = dpad }
        let rightStick = deadzoned(Vec2(x: Double(pad.rightThumbstick.xAxis.value), y: Double(pad.rightThumbstick.yAxis.value)))
        var input = PlayerInput(stick: stick)
        input.aim = rightStick.length >= BallRules.flickThreshold ? rightStick : stick
        input.jump = pad.buttonA.isPressed
        input.shootButtons = (pad.buttonB.isPressed ? 1 : 0) | (pad.rightShoulder.isPressed ? 2 : 0) | (pad.rightTrigger.isPressed ? 4 : 0)
        input.throwBall = pad.buttonX.isPressed
        input.taunt = pad.buttonY.isPressed
        return input
    }

    private func merge(_ a: PlayerInput, _ b: PlayerInput) -> PlayerInput {
        PlayerInput(stick: a.stick.lengthSquared >= b.stick.lengthSquared ? a.stick : b.stick,
                    aim: a.aim.lengthSquared >= b.aim.lengthSquared ? a.aim : b.aim,
                    jump: a.jump || b.jump,
                    shootButtons: a.shootButtons | b.shootButtons,
                    throwBall: a.throwBall || b.throwBall,
                    taunt: a.taunt || b.taunt)
    }

    static func deadzoned(_ raw: Vec2) -> Vec2 {
        let length = raw.length
        guard length > stickDeadzone else { return .zero }
        return raw.normalized * min((length - stickDeadzone) / (1 - stickDeadzone), 1)
    }

    private func deadzoned(_ raw: Vec2) -> Vec2 { InputHub.deadzoned(raw) }
}
