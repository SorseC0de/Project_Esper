import SpriteKit

/// `_Graphic Assets/Esper_Palette.png`, the game's palette: thirteen rows, the first the
/// outline black, the rest four-shade ramps, each lightest to darkest (highlight, light,
/// body, shadow). Colours in the game come from here.
enum EsperPalette {
    struct Ramp {
        let highlight: RGB, light: RGB, body: RGB, shadow: RGB
        init(_ highlight: RGB, _ light: RGB, _ body: RGB, _ shadow: RGB) {
            self.highlight = highlight
            self.light = light
            self.body = body
            self.shadow = shadow
        }
    }

    static let outline: RGB = 0x000000
    static let blue = Ramp(0x6BD0FF, 0x45BCF5, 0x36A9E0, 0x1468A3)
    static let lime = Ramp(0xD0E962, 0xC1DF3F, 0xADCA31, 0x6D8A12)
    static let pink = Ramp(0xFF6BCD, 0xF545B9, 0xE036A5, 0xA31464)
    static let purple = Ramp(0xB66BFF, 0x9F45F5, 0x8D36E0, 0x4D14A3)
    static let red = Ramp(0xFF6B92, 0xF54573, 0xE03662, 0xA3142E)
    static let silver = Ramp(0xE2E8EB, 0xD1CED7, 0xC1BEC6, 0x948A90)
    static let gold = Ramp(0xFFD45F, 0xF5BB45, 0xEDA42F, 0xD26614)
    static let black = Ramp(0x423F54, 0x262634, 0x1F1F2E, 0x0B0B12)
    static let royal = Ramp(0x6B8CFF, 0x466DF9, 0x1F4AE4, 0x0C22A9)
    static let tan = Ramp(0xFFE4BB, 0xF5C986, 0xE0B778, 0xC17A40)
    static let plum = Ramp(0x825391, 0x6D417D, 0x572C66, 0x3D1D52)
    static let brown = Ramp(0x79574B, 0x472E2B, 0x32201E, 0x251816)
}
