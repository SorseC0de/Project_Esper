import SwiftUI
import UIKit

/// Where the game runs, for the interface's sizes: a phone, an iPad or a Mac, or the TV.
enum UIPlatform: String {
    case phone, pad, tv

    static var current: UIPlatform {
        #if os(tvOS)
        return .tv
        #else
        if ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp { return .pad }
        return UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
        #endif
    }
}

/// The screens whose sizes are tuned, and what in them scales.
enum UIScreenKind: String, CaseIterable {
    case title, pause, win, stageSelect, pick, hud, touch

    /// Shown on the tuning panel.
    var label: String {
        switch self {
        case .stageSelect: "STAGE"
        default: rawValue.uppercased()
        }
    }

    /// The dialogs: a header, a card or plates, buttons. They share their sizes' starts.
    var isDialog: Bool { [.pause, .win, .stageSelect, .pick].contains(self) }
}

/// The plates, the lettering on them, the title lettering, and the panels: the header
/// ribbons and the cards under them.
enum UIPart: String, CaseIterable {
    case buttons, text, titles, panels
}

/// Each screen's button, text and title scales on this platform, set on the UI tuning
/// panel in steps of 0.05 and kept between launches, until the right numbers are known
/// and become the defaults here.
final class UITuning: ObservableObject {
    static let shared = UITuning()
    static let step: CGFloat = 0.05

    /// Bumped on every change, so SwiftUI redraws and the scene rebuilds its screen.
    @Published private(set) var revision = 0

    func scale(_ screen: UIScreenKind, _ part: UIPart) -> CGFloat {
        let key = UITuning.key(screen, part)
        if let saved = UserDefaults.standard.object(forKey: key) as? Double { return CGFloat(saved) }
        return UITuning.defaultScale(screen, part, on: .current)
    }

    func nudge(_ screen: UIScreenKind, _ part: UIPart, by steps: Int) {
        let stepped = ((scale(screen, part) + CGFloat(steps) * UITuning.step) * 100).rounded() / 100
        let value = min(max(stepped, 0.25), 5)
        UserDefaults.standard.set(Double(value), forKey: UITuning.key(screen, part))
        revision += 1
    }

    /// How much of the lift that centres lettering on a plate's face, and takes off its
    /// drop, is applied: one value for every screen on this platform.
    var textRise: CGFloat {
        (UserDefaults.standard.object(forKey: UITuning.textRiseKey) as? Double).map { CGFloat($0) } ?? UITuning.defaultTextRise
    }

    func nudgeTextRise(by steps: Int) {
        let stepped = ((textRise + CGFloat(steps) * UITuning.step) * 100).rounded() / 100
        UserDefaults.standard.set(Double(min(max(stepped, 0), 2)), forKey: UITuning.textRiseKey)
        revision += 1
    }

    /// Half the lift, as tuned, the same on every platform.
    static let defaultTextRise: CGFloat = 0.5

    private static var textRiseKey: String { "ui.\(UIPlatform.current.rawValue).textRise" }

    /// Something tuned outside the scales changed: redraw.
    func touch() { revision += 1 }

    func reset(_ screen: UIScreenKind) {
        for part in UIPart.allCases { UserDefaults.standard.removeObject(forKey: UITuning.key(screen, part)) }
        revision += 1
    }

    private static func key(_ screen: UIScreenKind, _ part: UIPart) -> String {
        "ui.\(UIPlatform.current.rawValue).\(screen.rawValue).\(part.rawValue)"
    }

    /// Where each platform starts, as tuned on each: the title, the dialogs (all sharing the
    /// pause's and the win's), and the HUD and the touch pad as drawn.
    static func defaultScale(_ screen: UIScreenKind, _ part: UIPart, on platform: UIPlatform) -> CGFloat {
        switch (platform, screen, part) {
        case (.phone, .title, .buttons): 1.1
        case (.phone, .title, .titles): 0.8
        case (.phone, .title, _): 1
        case (.phone, _, .text) where screen.isDialog, (.phone, _, .titles) where screen.isDialog: 0.8
        case (.phone, _, .panels) where screen.isDialog: 0.9
        case (.pad, .title, _), (.tv, .title, _): 2.5
        case (.pad, _, .text) where screen.isDialog, (.pad, _, .titles) where screen.isDialog: 1.5
        case (.pad, _, .panels) where screen.isDialog: 0.9
        case (.tv, _, .text) where screen.isDialog: 1.5
        case (.pad, .touch, .buttons): 0.75
        case (.pad, .touch, .text): 1.5
        default: 1
        }
    }
}

/// The UI tuning panel: the screen to tune, and its three scales with − and + a step at a
/// time, the value between; Pause and Win are shown behind it as they'd be.
struct UITuningPanel: View {
    @ObservedObject var tuning = UITuning.shared
    @ObservedObject var flow: FlowState
    @State private var screen = UIScreenKind.title

    var body: some View {
        VStack(spacing: 10) {
            Text("UI TUNING · \(UIPlatform.current.rawValue.uppercased())")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
            HStack(spacing: 8) {
                ForEach(UIScreenKind.allCases, id: \.self) { kind in
                    panelButton(kind.label, picked: kind == screen) {
                        screen = kind
                        flow.scene.preview(kind == .title ? nil : kind)
                    }
                }
            }
            ForEach(UIPart.allCases, id: \.self) { part in
                HStack(spacing: 8) {
                    Text(part.rawValue.uppercased()).frame(width: 80, alignment: .leading)
                    panelButton("−", picked: false) { change(part, -1) }
                    Text(String(format: "×%.2f", tuning.scale(screen, part))).monospacedDigit().frame(width: 64)
                    panelButton("+", picked: false) { change(part, 1) }
                }
                .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            if screen == .hud {
                lineRow("3PT WIDTH", key: ThreePointTuning.widthKey, value: ThreePointTuning.lineWidth, step: 1, range: 1...8)
                lineRow("NET TOP", key: NetTuning.topScaleKey, value: NetTuning.topScale, step: 0.25, range: 0.25...4)
                lineRow("NET BOTTOM", key: NetTuning.bottomScaleKey, value: NetTuning.bottomScale, step: 0.25, range: 0.25...4)
                lineRow("NET SPREAD", key: NetTuning.spreadKey, value: NetTuning.spread, step: 1, range: 1...8)
            }
            HStack(spacing: 8) {
                Text("TEXT Y").frame(width: 80, alignment: .leading)
                panelButton("−", picked: false) { tuning.nudgeTextRise(by: -1); flow.scene.refreshPreview() }
                Text(String(format: "×%.2f", tuning.textRise)).monospacedDigit().frame(width: 64)
                panelButton("+", picked: false) { tuning.nudgeTextRise(by: 1); flow.scene.refreshPreview() }
            }
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            HStack(spacing: 8) {
                panelButton("RESET", picked: false) {
                    tuning.reset(screen)
                    flow.scene.refreshPreview()
                }
                panelButton("CLOSE", picked: false) {
                    flow.scene.preview(nil)
                    flow.tuningOpen = false
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(UIPiece.cardBlack.image)
    }

    /// A row for 47's lines or the net: − and + a step at a time, kept under its own key.
    private func lineRow(_ title: String, key: String, value: CGFloat, step: CGFloat, range: ClosedRange<CGFloat>) -> some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 96, alignment: .leading)
            panelButton("−", picked: false) { setLine(key, value - step, range) }
            Text(String(format: step < 1 ? "%.2f" : "%.0f", value)).monospacedDigit().frame(width: 64)
            panelButton("+", picked: false) { setLine(key, value + step, range) }
        }
        .font(.system(size: 13, weight: .bold, design: .monospaced))
    }

    private func setLine(_ key: String, _ value: CGFloat, _ range: ClosedRange<CGFloat>) {
        UserDefaults.standard.set(Double((min(max(value, range.lowerBound), range.upperBound) * 100).rounded() / 100), forKey: key)
        tuning.touch()
        flow.scene.refreshPreview()
    }

    private func change(_ part: UIPart, _ steps: Int) {
        tuning.nudge(screen, part, by: steps)
        flow.scene.refreshPreview()
    }

    private func panelButton(_ text: String, picked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 28)
                .padding(.horizontal, 6)
                .background((picked ? UIPiece.buttonGold : UIPiece.buttonBlack).image)
        }
        .buttonStyle(.plain)
    }
}
