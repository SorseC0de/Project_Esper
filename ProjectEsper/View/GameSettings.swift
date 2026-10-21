import Foundation

/// The player's settings, kept between launches, each a row of the settings screen: what it's
/// called, its choices, and which is picked. The sound words' face and language are `Onomatopoeia`'s.
enum GameSettings {
    /// How many sound words show: all, only the biggest (`Onomatopoeia.Sound.biggest`), or none.
    enum Words: Int, CaseIterable { case on, some, off }

    static var words: Words {
        get { Words(rawValue: UserDefaults.standard.integer(forKey: "esper.settings.words")) ?? .on }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "esper.settings.words") }
    }
    /// The dust kicked up off a walk or a run.
    static var walkTrails: Bool {
        get { UserDefaults.standard.object(forKey: "esper.settings.walkTrails") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "esper.settings.walkTrails") }
    }
    /// The sound effects' loudness: off, low, mid, full.
    static let soundLevels: [Float] = [0, 0.33, 0.66, 1]
    static var soundLevel: Int {
        get { UserDefaults.standard.object(forKey: "esper.settings.soundLevel") as? Int ?? soundLevels.count - 1 }
        set { UserDefaults.standard.set(newValue, forKey: "esper.settings.soundLevel") }
    }
    /// A stage's background sound, the Elements' storm.
    /// Everything silenced at once, the title's speaker in its top left corner.
    static var muted: Bool {
        get { UserDefaults.standard.bool(forKey: "esper.settings.muted") }
        set { UserDefaults.standard.set(newValue, forKey: "esper.settings.muted") }
    }

    static var ambience: Bool {
        get { UserDefaults.standard.object(forKey: "esper.settings.ambience") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "esper.settings.ambience") }
    }
    /// The camera shaken by Quake-Up Coffee's landings and Titan Tea's steps.
    static var screenShake: Bool {
        get { UserDefaults.standard.object(forKey: "esper.settings.screenShake") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "esper.settings.screenShake") }
    }

    /// How the players' line is drawn in a match (`SpriteLibrary.LineStyle`): Normal, Semibold, Bold.
    /// Everywhere else it's Normal.
    static var playerVisibility: SpriteLibrary.LineStyle {
        get { SpriteLibrary.LineStyle(rawValue: UserDefaults.standard.integer(forKey: "esper.settings.playerVisibility")) ?? .normal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "esper.settings.playerVisibility") }
    }

    /// The screen's rows, top to bottom.
    /// The screen's categories, side by side; each opens onto its rows.
    enum Category: Int, CaseIterable {
        case visuals, sound, other
        var title: String {
            switch self {
            case .visuals: "VISUALS"
            case .sound: "SOUND"
            case .other: "OTHER STUFF"
            }
        }
    }

    @MainActor
    enum Row: CaseIterable {
        case words, wordStyle, wordLanguage, walkTrails, screenShake, playerVisibility, sound, ambience

        var category: Category {
            switch self {
            case .words, .wordStyle, .wordLanguage, .walkTrails, .screenShake, .playerVisibility: .visuals
            case .sound, .ambience: .sound
            }
        }
        static func rows(in category: Category) -> [Row] { allCases.filter { $0.category == category } }

        var title: String {
            switch self {
            case .words: "SFX"
            case .wordStyle: "SFX STYLE"
            case .wordLanguage: "SFX LANGUAGE"
            case .walkTrails: "WALK TRAILS"
            case .sound: "SOUND"
            case .ambience: "AMBIENCE"
            case .screenShake: "SCREEN SHAKE"
            case .playerVisibility: "PLAYER VISIBILITY"
            }
        }

        var options: [String] {
            switch self {
            case .words: ["ON", "SOME", "OFF"]
            case .wordStyle: Onomatopoeia.Style.lettered.map(\.label)
            case .wordLanguage: Onomatopoeia.Language.allCases.map(\.label)
            case .walkTrails, .ambience, .screenShake: ["ON", "OFF"]
            case .sound: ["OFF", "LOW", "MID", "FULL"]
            case .playerVisibility: ["NORMAL", "SEMIBOLD", "BOLD"]
            }
        }

        /// Which option is picked.
        var picked: Int {
            get {
                switch self {
                case .words: GameSettings.words.rawValue
                case .wordStyle: Onomatopoeia.Style.lettered.firstIndex(of: Onomatopoeia.style) ?? 0
                case .wordLanguage: Onomatopoeia.language.rawValue
                case .walkTrails: GameSettings.walkTrails ? 0 : 1
                case .sound: GameSettings.soundLevel
                case .ambience: GameSettings.ambience ? 0 : 1
                case .screenShake: GameSettings.screenShake ? 0 : 1
                case .playerVisibility: GameSettings.playerVisibility.rawValue
                }
            }
            nonmutating set {
                let index = min(max(newValue, 0), options.count - 1)
                switch self {
                case .words: GameSettings.words = Words(rawValue: index) ?? .on
                case .wordStyle: Onomatopoeia.style = Onomatopoeia.Style.lettered.indices.contains(index) ? Onomatopoeia.Style.lettered[index] : .daruma
                case .wordLanguage: Onomatopoeia.language = Onomatopoeia.Language(rawValue: index) ?? .english
                case .walkTrails: GameSettings.walkTrails = index == 0
                case .sound:
                    GameSettings.soundLevel = index
                    SoundBoard.shared.applyVolume()
                case .ambience:
                    GameSettings.ambience = index == 0
                    Ambience.shared.applySetting()
                case .screenShake: GameSettings.screenShake = index == 0
                case .playerVisibility: GameSettings.playerVisibility = SpriteLibrary.LineStyle(rawValue: index) ?? .normal
                }
            }
        }
    }
}
