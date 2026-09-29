import Foundation

/// `_Graphic Assets/Pixel_Palette.png`, AAP-64: the game's pixel palette, for everything
/// drawn in the world. The interface has its own, `EsperPalette`.
enum PixelPalette {
    /// All 64, in the palette's order, left to right, top to bottom.
    static let colours: [RGB] = [
        0x060608, 0x141013, 0x3B1725, 0x73172D, 0xB4202A, 0xDF3E23, 0xFA6A0A, 0xF9A31B,
        0xFFD541, 0xFFFC40, 0xD6F264, 0x9CDB43, 0x59C135, 0x14A02E, 0x1A7A3E, 0x24523B,
        0x122020, 0x143464, 0x285CC4, 0x249FDE, 0x20D6C7, 0xA6FCDB, 0xFFFFFF, 0xFEF3C0,
        0xFAD6B8, 0xF5A097, 0xE86A73, 0xBC4A9B, 0x793A80, 0x403353, 0x242234, 0x221C1A,
        0x322B28, 0x71413B, 0xBB7547, 0xDBA463, 0xF4D29C, 0xDAE0EA, 0xB3B9D1, 0x8B93AF,
        0x6D758D, 0x4A5462, 0x333941, 0x422433, 0x5B3138, 0x8E5252, 0xBA756A, 0xE9B5A3,
        0xE3E6FF, 0xB9BFFB, 0x849BE4, 0x588DBE, 0x477D85, 0x23674E, 0x328464, 0x5DAF8D,
        0x92DCBA, 0xCDF7E2, 0xE4D2AA, 0xC7B08B, 0xA08662, 0x796755, 0x5A4E44, 0x423934
    ]

    static let teal: RGB = 0x20D6C7
    static let pink: RGB = 0xBC4A9B
    static let orange: RGB = 0xFA6A0A
    static let lime: RGB = 0x9CDB43
    static let blue: RGB = 0x285CC4
    static let gold: RGB = 0xF9A31B
    static let red: RGB = 0xDF3E23
    /// The loose ball's purple.
    static let purple: RGB = 0x793A80
    /// Surf Soda's darker colour: its darker bubbles and the board's tail.
    static let plumDark: RGB = 0x403353
    /// Outlines drawn in code in the world.
    static let outline: RGB = 0x242234
}
