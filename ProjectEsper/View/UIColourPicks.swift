import SwiftUI

/// The UI's colours. Settled: the ground, the win screen's ground, the lettering's lower
/// half and its lit version on a gold plate. Picked on the title's grids (placeholders,
/// while the real ones are chosen): the three tones of the non-selected (black) and the
/// light blue buttons, each a swatch of `EsperPalette.swatches`, kept between launches;
/// unpicked, the pack's own.
enum UIColourPicks {
    /// The screens' ground: purple's last, flat.
    static let ground: RGB = EsperPalette.purple.shadow
    /// The win screen's: black's second.
    static let winGround: RGB = EsperPalette.black.light
    /// The inside of the pause and win menus' card: purple's last.
    static let menuCard: RGB = EsperPalette.purple.shadow
    /// The title lettering's lower half: silver's second; on a gold plate, the cursor's,
    /// blue's lightest.
    static let letters: RGB = EsperPalette.silver.light
    static let litLetters: RGB = EsperPalette.blue.highlight

    /// The buttons a grid recolours.
    enum Grid: Hashable, CaseIterable {
        case nonSelected, blue
        var label: String { self == .nonSelected ? "NON-SELECTED" : "BLUE" }
    }

    /// A button's three tones: its face, its top edge and oval, its bottom edge.
    enum Tone: Hashable, CaseIterable {
        case main, top, bottom
        var label: String {
            switch self {
            case .main: "MAIN"
            case .top: "TOP"
            case .bottom: "BOTTOM"
            }
        }
    }

    private static func key(_ grid: Grid, _ tone: Tone) -> String { "ui.pick.\(grid).\(tone)" }

    static func index(_ grid: Grid, _ tone: Tone) -> Int? {
        (UserDefaults.standard.object(forKey: key(grid, tone)) as? Int).flatMap { EsperPalette.swatches.indices.contains($0) ? $0 : nil }
    }

    static func colour(_ grid: Grid, _ tone: Tone) -> RGB? { index(grid, tone).map { EsperPalette.swatches[$0] } }

    /// Picks `index`, or takes the pick back when it's the one picked.
    static func toggle(_ grid: Grid, _ tone: Tone, _ index: Int) {
        if self.index(grid, tone) == index {
            UserDefaults.standard.removeObject(forKey: key(grid, tone))
        } else {
            UserDefaults.standard.set(index, forKey: key(grid, tone))
        }
    }
}

/// One of the title's pickers: every swatch of the UI palette, its twelve ramps two to a
/// row, on a black plate; the pick ringed white, the cursor gold.
struct SwatchGrid: View {
    @ObservedObject var flow: FlowState
    let grid: UIColourPicks.Grid
    @ObservedObject private var tuning = UITuning.shared

    /// Swatch points by platform: the phone's small so the grids and the buttons fit.
    static var swatchSize: CGFloat {
        switch UIPlatform.current {
        case .phone: 7
        case .pad: 12
        case .tv: 16
        }
    }

    var body: some View {
        let size = SwatchGrid.swatchSize
        let picked = UIColourPicks.index(grid, flow.tone(for: grid))
        VStack(spacing: size * 0.3) {
            ForEach(0..<(EsperPalette.ramps.count / 2), id: \.self) { row in
                HStack(spacing: size * 0.6) {
                    ForEach(0..<2, id: \.self) { half in
                        HStack(spacing: 0) {
                            ForEach(0..<4, id: \.self) { shade in
                                let index = (row * 2 + half) * 4 + shade
                                Button { flow.activate(.swatch(grid, index)) } label: {
                                    Rectangle()
                                        .fill(Color(rgb: EsperPalette.swatches[index]))
                                        .frame(width: size, height: size)
                                        .overlay(Rectangle().stroke(.white, lineWidth: picked == index ? 2 : 0))
                                        .overlay(Rectangle().stroke(Color(rgb: EsperPalette.gold.body), lineWidth: flow.titleCursor == .swatch(grid, index) ? 2 : 0).padding(-2))
                                }
                                .buttonStyle(.plain)
                                .noSystemFocus()
                            }
                        }
                    }
                }
            }
        }
        .padding(size * 0.8)
        .background(UIPiece.buttonBlack.image)
        .id(tuning.revision)
    }
}
