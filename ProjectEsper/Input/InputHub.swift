import EsperSim
import Foundation
import GameController

/// Where each player's input comes from. Player 0 is the touch controls and the first
/// controller together; player 1 is the second controller. Everything is read as held
/// state each frame, so nothing queues and nothing is lost between frames.
@MainActor
final class InputHub {
    /// What the on-screen controls hold right now. The scene writes it.
    var touch = PlayerInput.idle
    private(set) var controllers: [GCController] = []
    /// A pad's menu button went down since the last check; the options button likewise.
    private(set) var resetPressed = false
    private(set) var cyclePressed = false
    private var menuWasDown = false
    private var optionsWasDown = false
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
    }

    /// This frame's input for every player.
    func frames(players: Int) -> [PlayerInput] {
        let menuDown = controllers.contains { $0.extendedGamepad?.buttonMenu.isPressed ?? false }
        if menuDown, !menuWasDown { resetPressed = true }
        menuWasDown = menuDown
        let optionsDown = controllers.contains { $0.extendedGamepad?.buttonOptions?.isPressed ?? false }
        if optionsDown, !optionsWasDown { cyclePressed = true }
        optionsWasDown = optionsDown
        return (0..<players).map { index in
            let pad = index < controllers.count ? read(controllers[index].extendedGamepad!) : PlayerInput.idle
            return index == 0 ? merge(touch, pad) : pad
        }
    }

    var playerOneHasController: Bool { !controllers.isEmpty }

    /// True once per menu press.
    func consumeReset() -> Bool {
        defer { resetPressed = false }
        return resetPressed
    }

    /// True once per options press.
    func consumeCycle() -> Bool {
        defer { cyclePressed = false }
        return cyclePressed
    }

    /// A: jump. B or the right bumper: shoot. X or the left bumper: throw. Y: taunt.
    /// The right stick aims a stance; failing that, the left stick does.
    private func read(_ pad: GCExtendedGamepad) -> PlayerInput {
        var stick = deadzoned(Vec2(x: Double(pad.leftThumbstick.xAxis.value), y: Double(pad.leftThumbstick.yAxis.value)))
        let dpad = Vec2(x: Double(pad.dpad.xAxis.value), y: Double(pad.dpad.yAxis.value))
        if dpad != .zero { stick = dpad }
        let rightStick = deadzoned(Vec2(x: Double(pad.rightThumbstick.xAxis.value), y: Double(pad.rightThumbstick.yAxis.value)))
        var input = PlayerInput(stick: stick)
        input.aim = rightStick.length >= BallRules.flickThreshold ? rightStick : stick
        input.jump = pad.buttonA.isPressed
        input.shoot = pad.buttonB.isPressed || pad.rightShoulder.isPressed
        input.throwBall = pad.buttonX.isPressed || pad.leftShoulder.isPressed
        input.taunt = pad.buttonY.isPressed
        return input
    }

    private func merge(_ a: PlayerInput, _ b: PlayerInput) -> PlayerInput {
        PlayerInput(stick: a.stick.lengthSquared >= b.stick.lengthSquared ? a.stick : b.stick,
                    aim: a.aim.lengthSquared >= b.aim.lengthSquared ? a.aim : b.aim,
                    jump: a.jump || b.jump,
                    shoot: a.shoot || b.shoot,
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
