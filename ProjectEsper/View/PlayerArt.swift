import SpriteKit

/// A player frame's textures in one shape (`PlayerMap.ShapeKey`), shared by every look of that shape.
final class PlayerFrameMaps {
    let map: SKTexture
    let coverage: SKTexture
    /// FloState's line at half its thickness, on a canvas twice as fine: an energy form's alone.
    let thinLine: SKTexture?
    let present: Set<PlayerMapShaders.Layer>
    let texels: vector_float2

    init(_ made: PlayerMap, thinLine: CGImage?) {
        let size = CGSize(width: made.width, height: made.height)
        // Rows top first, as a picture's are.
        map = SKTexture(data: Data(made.bytes), size: size, flipped: true)
        coverage = SKTexture(data: Data(made.coverage), size: size, flipped: true)
        map.filteringMode = .nearest
        coverage.filteringMode = .nearest
        self.thinLine = thinLine.map { image in
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .nearest
            return texture
        }
        present = made.present
        texels = vector_float2(Float(made.width), Float(made.height))
    }

    var textures: [SKTexture] { [map, coverage] + (thinLine.map { [$0] } ?? []) }
}

/// One layer of a player frame as a node shows it: the frame's map or coverage, drawn through the
/// layer's shader in a look; or FloState's thin line, a plain picture.
struct PlayerArt {
    let frame: PlayerFrameMaps
    /// Nil: FloState's thin line.
    let layer: PlayerMapShaders.Layer?
    /// The look's block of the palette: the player slot it's drawn as.
    let look: Int
    let shaders: PlayerArtShaders

    var texture: SKTexture {
        guard let layer else { return frame.thinLine ?? frame.coverage }
        return layer.fromCoverage ? frame.coverage : frame.map
    }
    var shader: SKShader? { layer.map(shaders.shader) }

    /// The same frame and look as another of its layers, nil where the frame has none.
    func layer(_ other: PlayerMapShaders.Layer) -> PlayerArt? {
        frame.present.contains(other) ? PlayerArt(frame: frame, layer: other, look: look, shaders: shaders) : nil
    }

    /// The node's attributes for the shader: the map's size, and the look's block where it's in the palette.
    var attributes: [String: SKAttributeValue] {
        guard let layer else { return [:] }
        var values = ["a_texels": SKAttributeValue(vectorFloat2: frame.texels)]
        if layer.paletted { values["a_look"] = SKAttributeValue(float: Float(look)) }
        return values
    }

    /// Which channel of its texture the glow's mask reads as its alpha, blended as it read a picture's.
    var maskChannel: MaskChannel {
        switch layer {
        case .energy: .green
        case .bareLine: .blue
        default: .alpha
        }
    }
}

extension SKSpriteNode {
    /// Shows a player layer: its texture, its shader and the shader's attributes. The energy's ramp
    /// colours are the node's own, set apart (`GameScene.setEnergyRamp`).
    func show(_ art: PlayerArt) {
        let texture = art.texture
        if self.texture !== texture { self.texture = texture }
        let shader = art.shader
        if self.shader !== shader { self.shader = shader }
        guard let layer = art.layer else { return }
        setValue(SKAttributeValue(vectorFloat2: art.frame.texels), forAttribute: "a_texels")
        if layer.paletted { setValue(SKAttributeValue(float: Float(art.look)), forAttribute: "a_look") }
    }
}

/// The map shaders, one a layer, shared by every node a library draws; and the palette its looks'
/// colours are in, its own, so another library (the player gallery's) never recolours the game's.
final class PlayerArtShaders {
    let palette = SKUniform(name: "u_palette", texture: SKTexture())
    private var shaders: [PlayerMapShaders.Layer: SKShader] = [:]

    init() {
        for layer in PlayerMapShaders.Layer.allCases {
            let shader = SKShader(source: PlayerMapShaders.source(layer))
            if layer.paletted { shader.uniforms = [palette] }
            var attributes = [SKAttribute(name: "a_texels", type: .vectorFloat2)]
            if layer.paletted { attributes.append(SKAttribute(name: "a_look", type: .float)) }
            if layer == .energy { attributes += ["a_glow", "a_middle", "a_deep"].map { SKAttribute(name: $0, type: .vectorFloat3) } }
            shader.attributes = attributes
            shaders[layer] = shader
        }
    }

    func shader(_ layer: PlayerMapShaders.Layer) -> SKShader { shaders[layer]! }

    /// Each slot's look in its own block of the palette.
    func setLooks(_ looks: [Look]) {
        let rows = PlayerRecolour.paletteRows, rowBytes = PlayerMap.slotsPerRow * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * rows * PlayerMapShaders.paletteLooks)
        for (slot, look) in looks.prefix(PlayerMapShaders.paletteLooks).enumerated() {
            bytes.replaceSubrange(slot * rows * rowBytes..<(slot + 1) * rows * rowBytes, with: PlayerMap.palette(look))
        }
        // Rows bottom first: the shaders count a look's block up from the bottom.
        let texture = SKTexture(data: Data(bytes), size: CGSize(width: PlayerMap.slotsPerRow, height: rows * PlayerMapShaders.paletteLooks), flipped: false)
        texture.filteringMode = .nearest
        palette.textureValue = texture
    }
}

/// The channel of a texture the glow's mask takes for its alpha.
enum MaskChannel {
    case alpha, green, blue
}
