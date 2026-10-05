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
            // Taken by the ground, so a tap off the choices doesn't reach the pause under it.
            Color(rgb: UIColourPicks.ground).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            VStack(spacing: 14 * scale(.buttons)) {
                Image(uiImage: TitleText.image("SETTINGS", size: 44 * scale(.titles)))
                VStack(alignment: .leading, spacing: 8 * scale(.buttons)) {
                    ForEach(Array(GameSettings.Row.allCases.enumerated()), id: \.offset) { index, row in
                        rowView(row, index: index)
                    }
                }
                back
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.colorScheme, .dark)
    }

    private func rowView(_ row: GameSettings.Row, index: Int) -> some View {
        let onRow = flow.settingsCursor == index
        // Read so the row redraws when a choice changes.
        _ = flow.settingsVersion
        return HStack(spacing: 8) {
            Text(row.title)
                .font(.system(size: 13 * scale(.text), weight: .heavy, design: .rounded))
                .foregroundStyle(onRow ? Color(rgb: EsperPalette.gold.body) : .white)
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                .frame(width: 130 * scale(.buttons), alignment: .trailing)
            ForEach(Array(row.options.enumerated()), id: \.offset) { option, label in
                choice(label, picked: row.picked == option, cursor: onRow) { flow.pickSetting(row: index, option: option) }
            }
        }
    }

    /// A choice: plum when it's the one picked, gold when it's also the cursor's row, black otherwise.
    private func choice(_ text: String, picked: Bool, cursor: Bool, action: @escaping () -> Void) -> some View {
        let piece = picked ? (cursor ? UIPiece.buttonGold : UIPiece.buttonPlum) : UIPiece.buttonBlack
        return Button(action: action) {
            Text(text)
                .font(.system(size: 11 * scale(.text), weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                .offset(y: -UIPiece.buttonPlum.faceRise * scale(.buttons) * tuning.textRise)
                .frame(minWidth: 64 * scale(.buttons), minHeight: 28 * scale(.buttons))
                .padding(.horizontal, 6)
                .background(piece.image(corners: scale(.buttons)))
        }
        .buttonStyle(.plain)
        .noSystemFocus()
    }

    private var back: some View {
        let lit = flow.settingsCursor == GameSettings.Row.allCases.count
        let piece = lit ? UIPiece.buttonGold : UIPiece.buttonPlum
        return Button { flow.closeSettings() } label: {
            let rise = tuning.textRise
            let shift = TitleText.dropShift(size: 22 * scale(.text)) * rise
            Image(uiImage: TitleText.image("BACK", size: 22 * scale(.text), lit: lit))
                .offset(x: -shift, y: -(piece.faceRise * scale(.buttons) * rise + shift))
                .frame(width: 170 * scale(.buttons), height: 48 * scale(.buttons))
                .background(piece.image(corners: scale(.buttons)))
        }
        .buttonStyle(.plain)
        .scaleEffect(lit ? TitleOverlay.cursorGrowth : 1)
        .noSystemFocus()
    }
}

/// The settings gear, on one of the pack's round plates: gold under the cursor.
struct SettingsGear: View {
    let lit: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                (lit ? UIPiece.circleGold : UIPiece.circleBlue).image(corners: 0.6)
                    .frame(width: 46, height: 48)
                if let gear = UIImage(named: "ui_icon_settings") {
                    Image(uiImage: gear).resizable().interpolation(.high).frame(width: 24, height: 25).offset(y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(lit ? TitleOverlay.cursorGrowth : 1)
        .noSystemFocus()
    }
}
