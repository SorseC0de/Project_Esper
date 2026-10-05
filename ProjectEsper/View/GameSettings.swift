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
    static var ambience: Bool {
        get { UserDefaults.standard.object(forKey: "esper.settings.ambience") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "esper.settings.ambience") }
    }
    /// The camera shaken by Quake-Up Coffee's landings and Titan Tea's steps.
    static var screenShake: Bool {
        get { UserDefaults.standard.object(forKey: "esper.settings.screenShake") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "esper.settings.screenShake") }
    }

    /// The screen's rows, top to bottom.
    @MainActor
    enum Row: CaseIterable {
        case words, wordStyle, wordLanguage, walkTrails, sound, ambience, screenShake

        var title: String {
            switch self {
            case .words: "SFX"
            case .wordStyle: "SFX STYLE"
            case .wordLanguage: "SFX LANGUAGE"
            case .walkTrails: "WALK TRAILS"
            case .sound: "SOUND"
            case .ambience: "AMBIENCE"
            case .screenShake: "SCREEN SHAKE"
            }
        }

        var options: [String] {
            switch self {
            case .words: ["ON", "SOME", "OFF"]
            case .wordStyle: Onomatopoeia.Style.allCases.map(\.label)
            case .wordLanguage: Onomatopoeia.Language.allCases.map(\.label)
            case .walkTrails, .ambience, .screenShake: ["ON", "OFF"]
            case .sound: ["OFF", "LOW", "MID", "FULL"]
            }
        }

        /// Which option is picked.
        var picked: Int {
            get {
                switch self {
                case .words: GameSettings.words.rawValue
                case .wordStyle: Onomatopoeia.style.rawValue
                case .wordLanguage: Onomatopoeia.language.rawValue
                case .walkTrails: GameSettings.walkTrails ? 0 : 1
                case .sound: GameSettings.soundLevel
                case .ambience: GameSettings.ambience ? 0 : 1
                case .screenShake: GameSettings.screenShake ? 0 : 1
                }
            }
            nonmutating set {
                let index = min(max(newValue, 0), options.count - 1)
                switch self {
                case .words: GameSettings.words = Words(rawValue: index) ?? .on
                case .wordStyle: Onomatopoeia.style = Onomatopoeia.Style(rawValue: index) ?? .cherry
                case .wordLanguage: Onomatopoeia.language = Onomatopoeia.Language(rawValue: index) ?? .english
                case .walkTrails: GameSettings.walkTrails = index == 0
                case .sound:
                    GameSettings.soundLevel = index
                    SoundBoard.shared.applyVolume()
                case .ambience:
                    GameSettings.ambience = index == 0
                    Ambience.shared.applySetting()
                case .screenShake: GameSettings.screenShake = index == 0
                }
            }
        }
    }
}
