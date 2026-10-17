import SwiftUI

/// The UI's colours: the ground, the menus' card, the lettering's lower half and its lit
/// version on a gold plate.
enum UIColourPicks {
    /// The screens' ground: purple's last, flat.
    static let ground: RGB = EsperPalette.purple.shadow
    /// The win screen's: black's second.
    /// The inside of the pause and win menus' card: purple's last.
    static let menuCard: RGB = EsperPalette.purple.shadow
    /// The title lettering's lower half: silver's second; on a gold plate, the cursor's,
    /// blue's lightest.
    static let letters: RGB = EsperPalette.silver.light
    static let litLetters: RGB = EsperPalette.blue.highlight
}
