/// The instruments for working on the game: the tuning panels, the pickers and sliders over
/// the pad, the HITBOX, WALLS and AI switches, the title's colour grids and the readouts.
/// A debug build has them; a Release build, the testers', has none.
enum DebugUI {
    #if DEBUG
    static let enabled = true
    #else
    static let enabled = false
    #endif
}
