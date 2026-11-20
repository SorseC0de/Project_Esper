import CoreGraphics
import Foundation

/// A player frame stored once for every look that shares its shape (`PlayerMap.ShapeKey`), drawn in
/// a look by `PlayerMapShaders`. Two textures replace the dozen pictures a look painted:
///
/// `bytes`, read pixel-sharp (each sample snapped to its texel's centre):
/// - red: the body's colour, `row * 32 + slot` into the look's palette (`PlayerMap.palette`).
/// - green: the glow mask's kind of body, `maskSkin` or `maskNeck`.
/// - blue: `body`, `glowLine`, `bareGlowLine`, `glowing`, `clothes`.
/// - alpha: 255 on the body, so whatever reads a body's alpha (the glow's mask, a shadow) reads it as before.
///
/// `coverage`, read as SpriteKit samples a picture in a shader, blended between texels, so the energy's
/// ramp and the glow mask's lines come out as they did from their own pictures:
/// - red: the energy's grey, green: the energy's alpha, blue: the bare line, alpha: the line.
struct PlayerMap {
    let width: Int
    let height: Int
    /// Top row first, four bytes a texel.
    let bytes: [UInt8]
    let coverage: [UInt8]
    /// The layers the recolour made a picture of: one it didn't is nil to whatever asks, as the picture was.
    let present: Set<PlayerMapShaders.Layer>
    /// Pixels a lenient map left out (`make`): none, or the map isn't the frame as painted.
    let faults: Int

    static let slotsPerRow = 32
    /// The neck under the hood: its colour isn't any one part's.
    static let neckSlot = BodyPart.allCases.count + 1

    static func slot(_ part: BodyPart) -> Int { BodyPart.allCases.firstIndex(of: part)! + 1 }

    enum Flag {
        /// In `bytes`' blue.
        static let body: UInt8 = 1
        static let glowLine: UInt8 = 2
        static let bareGlowLine: UInt8 = 4
        static let glowing: UInt8 = 8
        static let clothes: UInt8 = 16
        /// In `bytes`' green.
        static let maskSkin: UInt8 = 1
        static let maskNeck: UInt8 = 2
    }

    /// The map of what a recolour made, its body's colours on row `row` of `palette` (the look's,
    /// `palette(_:)`). Nil where the layers hold something a map can't say (a head apart, a body pixel
    /// with no part or not in its part's colour), unless `lenient`: then those pixels are left out.
    static func make(layers: PlayerRecolour.Layers, parts: [BodyPart?], hooded: Bool, row: Int, palette: [UInt8], width: Int, height: Int,
                     lenient: Bool = false) -> PlayerMap? {
        guard layers.head == nil, layers.drawn.width == width, layers.drawn.height == height else { return nil }
        func read(_ image: CGImage?) -> [UInt8]? {
            guard let image, image.width == width, image.height == height,
                  let (context, pixels) = PlayerRecolour.canvas(width: width, height: height) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return Array(UnsafeBufferPointer(start: pixels, count: width * height * 4))
        }
        let images = [layers.drawn, layers.energy, layers.outline, layers.glowLine, layers.bareOutline, layers.bareGlowLine,
                      layers.glowing, layers.skin, layers.glowMask]
        let read = images.map(read)
        guard zip(images, read).allSatisfy({ ($0.0 == nil) == ($0.1 == nil) }), let drawn = read[0] else { return nil }
        let energy = read[1], line = read[2], glowLine = read[3], bareLine = read[4], bareGlowLine = read[5]
        let glowing = read[6], clothes = read[7], mask = read[8]
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var coverage = [UInt8](repeating: 0, count: width * height * 4)
        var faults = 0
        for pixel in 0..<(width * height) {
            let index = pixel * 4
            var flags: UInt8 = 0, kind: UInt8 = 0
            if drawn[index + 3] != 0 {
                // A body pixel: its part's colour, or under the hood the neck's, exactly.
                guard drawn[index + 3] == 255, let part = parts[pixel], !part.isEnergy, part != .ball else { faults += 1; continue }
                let slot = part == .head && hooded ? neckSlot : slot(part)
                let colour = (row * slotsPerRow + slot) * 4
                guard palette[colour + 3] == 255, palette[colour] == drawn[index], palette[colour + 1] == drawn[index + 1],
                      palette[colour + 2] == drawn[index + 2] else { faults += 1; continue }
                bytes[index] = UInt8(row * slotsPerRow + slot)
                bytes[index + 3] = 255
                flags |= Flag.body
            }
            if let energy, energy[index + 3] != 0 {
                // Grey and opaque, as the recolour draws it.
                guard energy[index + 3] == 255, energy[index] == energy[index + 1], energy[index] == energy[index + 2] else { faults += 1; continue }
                coverage[index] = energy[index]
                coverage[index + 1] = 255
            }
            // Every other layer is white wherever it's drawn, all or nothing.
            func covers(_ layer: [UInt8]?) -> Bool? {
                guard let layer, layer[index + 3] != 0 else { return false }
                return layer[index] == 255 && layer[index + 1] == 255 && layer[index + 2] == 255 && layer[index + 3] == 255 ? true : nil
            }
            guard let lineHere = covers(line), let glowLineHere = covers(glowLine), let bareLineHere = covers(bareLine),
                  let bareGlowLineHere = covers(bareGlowLine), let clothesHere = covers(clothes) else { faults += 1; continue }
            if lineHere { coverage[index + 3] = 255 }
            if bareLineHere { coverage[index + 2] = 255 }
            if glowLineHere { flags |= Flag.glowLine }
            if bareGlowLineHere { flags |= Flag.bareGlowLine }
            if clothesHere { flags |= Flag.clothes }
            if let glowing, glowing[index + 3] != 0 {
                // The body's own pixel again, as drawn.
                guard flags & Flag.body != 0, glowing[index..<index + 4] == drawn[index..<index + 4] else { faults += 1; continue }
                flags |= Flag.glowing
            }
            if let mask, mask[index + 3] != 0 {
                // Black where it glows, white the plain body, green skin, red the neck: what the flags say.
                guard flags & Flag.body != 0, mask[index + 3] == 255 else { faults += 1; continue }
                let red = mask[index], green = mask[index + 1], blue = mask[index + 2]
                let glows = flags & Flag.glowing != 0
                if red == 0 && green == 0 && blue == 0 && glows {
                } else if red == 255 && green == 255 && blue == 255 && !glows {
                } else if red == 0 && green == 255 && blue == 0 && !glows {
                    kind = Flag.maskSkin
                } else if red == 255 && green == 0 && blue == 0 && !glows {
                    kind = Flag.maskNeck
                } else {
                    faults += 1
                }
            } else if mask != nil, flags & Flag.body != 0 {
                faults += 1
            }
            bytes[index + 1] = kind
            bytes[index + 2] = flags
        }
        guard faults == 0 || lenient else { return nil }
        var present: Set<PlayerMapShaders.Layer> = [.body]
        let made: [(PlayerMapShaders.Layer, CGImage?)] = [(.line, layers.outline), (.glowLine, layers.glowLine), (.bareLine, layers.bareOutline),
                                                          (.bareGlowLine, layers.bareGlowLine), (.glowing, layers.glowing), (.clothes, layers.skin),
                                                          (.glowMask, layers.glowMask), (.energy, layers.energy)]
        for (layer, image) in made where image != nil { present.insert(layer) }
        return PlayerMap(width: width, height: height, bytes: bytes, coverage: coverage, present: present, faults: faults)
    }

    /// What decides a frame's map, colours aside: looks that agree on it share every frame's map,
    /// and a change of colour alone redraws nothing. Not the skin tone: every tone's hood is one shape
    /// (checked over every frame).
    struct ShapeKey: Hashable {
        var covered: Set<BodyPart>
        var energyForm: Bool
        var outlineWidth: Int
        var strokedGroups: [Set<BodyPart>]
        var lineStyle: PlayerLineStyle

        init(_ look: Look, lineStyle: PlayerLineStyle) {
            covered = look.dressing.covered
            energyForm = look.energyForm
            outlineWidth = look.outlineWidth
            strokedGroups = look.strokedGroups
            self.lineStyle = lineStyle
        }

        var name: String {
            let parts = BodyPart.allCases.filter(covered.contains).map { "\(PlayerMap.slot($0))" }.joined(separator: ".")
            let groups = strokedGroups.map { group in BodyPart.allCases.filter(group.contains).map { "\(PlayerMap.slot($0))" }.joined(separator: ".") }
                .joined(separator: "|")
            return "c\(parts)e\(energyForm ? 1 : 0)w\(outlineWidth)g\(groups)l\(lineStyle.rawValue)"
        }
    }

    /// A look's palette: `paletteRows` rows of `slotsPerRow` colours, top row first, four bytes each,
    /// opaque where a part has a colour. Row r is the look as `PlayerRecolour.adjusted(_:row:)` draws it.
    static func palette(_ look: Look) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: PlayerRecolour.paletteRows * slotsPerRow * 4)
        for row in 0..<PlayerRecolour.paletteRows {
            let adjusted = PlayerRecolour.adjusted(look, row: row)
            func put(_ slot: Int, _ colour: RGB) {
                let index = (row * slotsPerRow + slot) * 4
                bytes[index] = UInt8((colour >> 16) & 0xFF)
                bytes[index + 1] = UInt8((colour >> 8) & 0xFF)
                bytes[index + 2] = UInt8(colour & 0xFF)
                bytes[index + 3] = 255
            }
            for part in BodyPart.allCases {
                if let colour = adjusted.colours[part] { put(slot(part), colour) }
            }
            // As `PlayerRecolour.recolour` paints the neck under the hood.
            put(neckSlot, adjusted.energyForm ? adjusted.dressing.tone.back : adjusted.colours[.backHand] ?? adjusted.dressing.tone.back)
        }
        return bytes
    }
}

/// The shaders that draw a `PlayerMap` as each of the figure's layers. Each ends as SpriteKit's own
/// drawing does, the layer's colour times `v_color_mix`, so a node's colour, blend factor and alpha
/// tint it as they tinted the picture it replaces; the energy ends as the energy ramp's shader did.
/// `a_look`: the node's look's block of the palette (`u_palette`). `a_texels`: the map's size.
enum PlayerMapShaders {
    enum Layer: Int, CaseIterable {
        case body, glowing, glowLine, bareGlowLine, clothes, glowMask, line, bareLine, energy
        /// The energy's grey as its picture was, untoned: what an afterimage copies.
        case energyGrey
        /// Drawn from `PlayerMap.coverage` rather than `bytes`.
        var fromCoverage: Bool { self == .line || self == .bareLine || self == .energy || self == .energyGrey }
        /// Drawn in the look's palette.
        var paletted: Bool { self == .body || self == .glowing }
    }

    /// Looks the palette has room for, `PlayerRecolour.paletteRows` rows each.
    static let paletteLooks = 16

    /// A texel's byte, and a byte's bit. Helpers take plain values only: SpriteKit hands the uniforms,
    /// attributes and `v_tex_coord` to `main` alone, and a helper naming one fails to compile.
    static let common = """
    float mapByte(float channel) { return floor(channel * 255.0 + 0.5); }
    float mapBit(float value, float bit) { return mod(floor(value / bit), 2.0); }
    """

    /// The texel under `v_tex_coord`, as a pixel-sharp picture gives it: SpriteKit samples a shader's
    /// texture blended between texels whatever its filtering mode, so the sample's snapped to the centre.
    static let sharpTexel = "vec4 m = texture2D(u_texture, (floor(v_tex_coord * a_texels) + 0.5) / a_texels);"

    static func source(_ layer: Layer) -> String {
        let body: String
        switch layer {
        case .body, .glowing:
            // The look's colour for the texel's row and part.
            body = """
            \(sharpTexel)
                float flags = mapByte(m.b);
                float cover = mapBit(flags, 1.0)\(layer == .glowing ? " * mapBit(flags, 8.0)" : "");
                float colourByte = mapByte(m.r);
                float paletteRow = floor(colourByte / 32.0);
                float slot = colourByte - paletteRow * 32.0;
                vec2 paletteAt = vec2((slot + 0.5) / 32.0, (a_look * \(Double(PlayerRecolour.paletteRows)) + paletteRow + 0.5) / \(Double(paletteLooks * PlayerRecolour.paletteRows)));
                gl_FragColor = cover * vec4(texture2D(u_palette, paletteAt).rgb, 1.0) * v_color_mix;
            """
        case .glowMask:
            // Black where it glows, else white, green on skin, red on the neck.
            body = """
            \(sharpTexel)
                float flags = mapByte(m.b), kind = mapByte(m.g);
                float glows = mapBit(flags, 8.0), neck = mapBit(kind, 2.0), skin = mapBit(kind, 1.0);
                vec3 colour = neck > 0.5 ? vec3(1.0, 0.0, 0.0) : (skin > 0.5 ? vec3(0.0, 1.0, 0.0) : vec3(1.0));
                gl_FragColor = mapBit(flags, 1.0) * vec4(colour * (1.0 - glows), 1.0) * v_color_mix;
            """
        case .glowLine, .bareGlowLine, .clothes:
            let bit = layer == .glowLine ? 2 : (layer == .bareGlowLine ? 4 : 16)
            body = """
            \(sharpTexel)
                gl_FragColor = vec4(mapBit(mapByte(m.b), \(Double(bit)))) * v_color_mix;
            """
        case .line, .bareLine:
            body = """
            \(sharpTexel)
                gl_FragColor = vec4(m.\(layer == .line ? "a" : "b")) * v_color_mix;
            """
        case .energyGrey:
            body = """
            \(sharpTexel)
                gl_FragColor = vec4(m.r, m.r, m.r, m.g) * v_color_mix;
            """
        case .energy:
            // The energy ramp, as on its own grey picture: blended between texels, the grey over its alpha.
            body = """
            vec4 m = texture2D(u_texture, v_tex_coord);
                float level = m.g > 0.0 ? m.r / m.g : 0.0;
                vec3 toned = level > 0.9 ? a_glow : (level > 0.7 ? a_middle : (level > 0.5 ? a_deep : a_glow * (level * 2.0)));
                gl_FragColor = vec4(toned * m.g, m.g) * v_color_mix.a;
            """
        }
        return """
        \(common)
        void main() {
            \(body)
        }
        """
    }

    /// The glow mask's flat colour `u_flat` over one channel of a texture, blended as its flat shader
    /// blends a picture's alpha: green for the energy's alpha, blue for the bare line's.
    static func flatSource(channel: String) -> String {
        """
        void main() {
            float alpha = texture2D(u_texture, v_tex_coord).\(channel);
            gl_FragColor = vec4(u_flat.rgb * alpha, alpha);
        }
        """
    }
}
