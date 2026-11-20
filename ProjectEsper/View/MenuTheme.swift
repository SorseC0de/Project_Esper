import Foundation

/// The menus' color, THEME on the title's lower rung: one of the hood picker's, kept between
/// launches. Larimar, the first pick, draws the menus as they always were.
enum MenuTheme {
    static let key = "ui.menu.theme"
    static let defaultColour = EnergyColour.teal
    /// THEME's colors: the hood picker's without white, so the white cursor shows on every one.
    static let choices = EnergyColour.wheel.filter { $0 != .white }
    /// How far a color's glow is lifted toward white for the lines and lettering.
    static let lineLift = 0.55
    /// Larimar's lines: the menus' original blue, which no lift of its glow lands on.
    static let tealLineRGB: RGB = 0x88D7ED

    nonisolated(unsafe) private static var picked: EnergyColour?
    static var colour: EnergyColour {
        get {
            if let picked { return picked }
            let stored = UserDefaults.standard.string(forKey: key).flatMap(EnergyColour.init(rawValue:))
            let saved = stored.flatMap { choices.contains($0) ? $0 : nil } ?? defaultColour
            picked = saved
            return saved
        }
        set {
            picked = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    /// The lines and lettering: the glow lifted, Larimar's the original blue.
    static var lineRGB: RGB { lineRGB(for: colour) }
    static func lineRGB(for colour: EnergyColour) -> RGB {
        colour == .teal ? tealLineRGB : Look.lightened(colour.glow, lineLift)
    }
    /// The light the jumbotron's tinted with: the glow itself.
    static var lightRGB: RGB { colour.glow }
}
