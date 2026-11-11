import EsperSim
import SpriteKit

/// Anozira's scenery (`AnoziraRules`), from `Anozira.aseprite` and its pieces beside it, each by
/// `Tools/import_stage_art.py`. The background and sky stand still; the mountains, rocks, sand,
/// foreground and road are each laid three times side by side and slid left forever, the
/// foreground with the road, each further back slower. The car (`Car_v4`) stands on the road where the file's
/// [DO NOT DRAW] box has it; the truck (`Truck.aseprite`) carries the rim, its pole leaning with the
/// sim's jostle, the flag on its roof at half size. Both idle a pixel up and down, whoever stands on
/// them with them, and their near wheels' hubs turn clockwise as wheels on the road would. While someone
/// holds the ball the car takes that player's energy colour, glowing, and the truck's head and tail
/// lights (its palette 3 and 4) their two colours, the bright and the glow, glowing; nobody holding
/// it, the car's drawn as painted and the lights grey. The truck itself is white, and doesn't glow.
enum AnoziraArt {
    final class Handles {
        var background: SKSpriteNode?
        /// Each sliding layer's copies, its width, and its speed in art pixels a second.
        var sliding: [(copies: [SKSpriteNode], width: CGFloat, left: CGFloat, speed: CGFloat)] = []
        var carWheels: SKSpriteNode?
        var carBody: SKSpriteNode?
        var carTint: SKSpriteNode?
        /// Breaker Ball's second car, in the hoop truck's place, and its hubs; each car's glow eased on
        /// while its own player holds the ball.
        var secondCarWheels: SKSpriteNode?
        var secondCarBody: SKSpriteNode?
        var secondCarTint: SKSpriteNode?
        var secondCarHubs: [SKSpriteNode] = []
        var carTintShares: [CGFloat] = [0, 0]
        var truckBar: SKSpriteNode?
        var truckWheels: SKSpriteNode?
        var truckBody: SKSpriteNode?
        /// The head and tail lights' two colours, the lighter and the darker.
        var truckLights: [SKSpriteNode] = []
        var flag: SKSpriteNode?
        /// The Phoenix: its tail's ring behind the ball, its body, and the ring's front over the ball; its sparkles.
        var phoenix: [SKSpriteNode] = []
        var phoenixSparkles: [(node: SKSpriteNode, age: Double)] = []
        var phoenixLastTime: CFTimeInterval?
        /// The billboards by the road, sliding by; the plane far off, and when the next comes.
        var billboards: [SKSpriteNode] = []
        var billboardPictures: [SKTexture] = []
        var plane: SKSpriteNode?
        var planeFlight: (start: CFTimeInterval, rightward: Bool)?
        var nextPlaneAt: CFTimeInterval?
        /// Where the near wheels meet the road this frame, for the skid sparks, and the depth they're drawn at.
        var wheelContacts: [(at: CGPoint, z: CGFloat)] = []
        /// The near wheels' hubs, the car's and the truck's.
        var carHubs: [SKSpriteNode] = []
        var truckHubs: [SKSpriteNode] = []
        /// The sky's two warm colours, turned by the rain (`AnoziraSkyOrange`, `AnoziraSkyYellow`).
        var skyTurns: [SKSpriteNode] = []
        /// The potholes on the road, as many as the match has.
        var potholes: [SKSpriteNode] = []
        /// The oncoming traffic on the far lane, each where it is, and each one's veer, its own;
        /// when the next comes; the last frame's time.
        var traffic: [SKSpriteNode] = []
        var trafficVeers: [UInt32] = []
        var trafficSpeeds: [CGFloat] = []
        var nextVehicleAt: CFTimeInterval = 0
        var lastTime: CFTimeInterval?
        /// The pictures it's drawn from: the car in each ramp, and the white truck.
        var trafficPictures: [SKTexture] = []
        /// How much of the holder's colour is on, easing in and out.
        var tintShare: CGFloat = 0
        var tintColours = Colours(car: .white, light: .white, dark: .white)
        /// The nodes drawn as painted, which mustn't glow, and the tinted ones, which do.
        var flats: [SKSpriteNode] {
            ([carWheels, carBody, truckBar, truckWheels, truckBody, flag, secondCarWheels, secondCarBody] + sliding.flatMap(\.copies)).compactMap { $0 }
                .filter { !$0.isHidden } + carHubs + (truckHubs + secondCarHubs).filter { !$0.isHidden } + traffic
                + potholes.filter { !$0.isHidden } + billboards + [plane].compactMap { $0 }.filter { !$0.isHidden }
        }
        var glowing: [SKSpriteNode] {
            (tintShare > 0 ? [carTint].compactMap { $0 } + truckLights.filter { !$0.isHidden } : []) + phoenix.filter { !$0.isHidden } + phoenixSparkles.map(\.node)
                + [secondCarTint].compactMap { $0 }.filter { !$0.isHidden && $0.alpha > 0 }
        }
    }

    /// The holder's colours: the car's, and the lights' lighter and darker.
    struct Colours {
        var car: SKColor
        var light: SKColor
        var dark: SKColor
    }
    /// The lights with nobody holding the ball: greys off the car's paint.
    static let unheldLightsRGB: (light: RGB, dark: RGB) = (0x858585, 0x5D5D5D)
    static let unheldLights = (light: SKColor(rgb: unheldLightsRGB.light), dark: SKColor(rgb: unheldLightsRGB.dark))

    /// The rain turns the sky's palette 37 to 12 and 34 to 11, as hard as it's raining.
    static let skyTurnColours: [RGB] = [PixelPalette.colours[12], PixelPalette.colours[11]]
    /// A pothole's middle, up from the stage's foot, under the near wheels; each drawn up to
    /// `potholeSpread` art pixels above or below that, its own way, drawn only.
    static let potholeY: CGFloat = 30
    static let potholeSpread = 8
    /// In the rain a vehicle's this much smaller veered all the way up its lane, larger all the way down.
    static let veerScale: CGFloat = 0.1
    /// Washes: palette 8 over the layers under the road (not the sky), a third, keeping them back as
    /// the Wreck Center's is; and palette 10 over the whole world, a third, as hard as it's raining,
    /// laid by the composite so the far lightning can stay out of it.
    static let underWashColour: RGB = PixelPalette.colours[8]
    static let underWashAlpha: CGFloat = 0.33
    static let rainWashColour: RGB = PixelPalette.colours[10]
    static let rainWashAlpha: CGFloat = 0.33

    /// Past the file's edges: its background's colour.
    static let beyond: RGB = 0x131313
    /// The file's bottom left in the stage's art pixels: its [DO NOT DRAW] box is 16 up.
    static let fileOrigin = CGPoint(x: 0, y: -16)
    /// The file's height, for its top-down cels.
    static let fileHeight: CGFloat = 352
    /// The sliding layers back to front, by their pictures: their tops in the file, and their
    /// speeds, art pixels a second: the foreground with the road, each further back half as fast.
    static let roadSpeed: CGFloat = 384
    static let slidingLayers: [(name: String, top: CGFloat, speed: CGFloat)] = [
        ("AnoziraMountains", 114, roadSpeed / 8), ("AnoziraRocks", 191, roadSpeed / 4), ("AnoziraSand", 244, roadSpeed / 2),
        ("AnoziraForeground", 244, roadSpeed), ("AnoziraRoad", 280, roadSpeed),
    ]
    static let backgroundZ: CGFloat = -8
    /// The sliding layers from here, a step apart; the lightning far off behind them all.
    static let slidingZ: CGFloat = -7.95
    static let lightningZ: CGFloat = -7.97
    static let carZ: CGFloat = -7.7
    /// The truck under the hoop (its backboard is 5, its pole assembly 4.9): the pole behind the
    /// body, in the bed; the wheels under the body.
    static let truckZ: CGFloat = 3
    /// The flag on the cab's roof, its pole's foot this far along the truck's picture and up it;
    /// its frames (`AnoziraFlag`, nine 32 by 32 down the picture) at this many a second.
    static let flagFoot = CGPoint(x: 64, y: 49)
    static let flagAnchor = CGPoint(x: 21.5 / 32, y: 0)
    static let flagScale: CGFloat = 0.5
    static let flagFramesPerSecond = 20.0
    static let flagFrames: [SKTexture] = cells(of: "AnoziraFlag", height: 32)
    /// The Phoenix's pictures (`AnoziraPhoenixRing`, `AnoziraPhoenix`, `AnoziraPhoenixFront`, six
    /// 48 by 32 down each) at this many a second; in the glowers, the ring under the ball (6), its front over it.
    static let phoenixPictures = ["AnoziraPhoenixRing", "AnoziraPhoenix", "AnoziraPhoenixFront"]
    static let phoenixDepths: [CGFloat] = [5.8, 5.9, 6.5]
    static let phoenixFramesPerSecond = 10.0
    static let phoenixFrames: [[SKTexture]] = phoenixPictures.map { cells(of: $0, height: 32) }
    /// Its sparkles: this many a second off its body, each this long, falling behind it this far a second.
    static let phoenixSparklesPerSecond = 20.0
    static let phoenixSparkleSeconds = 0.6
    static let phoenixSparkleFall: CGFloat = 12
    static let sparkleTexture: SKTexture = {
        let side = 5
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for pixel in 0..<(side * side) where pixel % side == 2 || pixel / side == 2 {
            let level: UInt8 = pixel == 12 ? 255 : 170
            for channel in 0..<4 { pixels[pixel * 4 + channel] = level }
        }
        let texture = SKTexture(data: Data(pixels), size: CGSize(width: side, height: side))
        texture.filteringMode = .nearest
        return texture
    }()
    /// A strip's cells, top first.
    static func cells(of name: String, height: CGFloat) -> [SKTexture] {
        let sheet = SKTexture(imageNamed: name)
        sheet.filteringMode = .nearest
        let count = Int(sheet.size().height / height)
        return (0..<count).map { row in
            let cell = SKTexture(rect: CGRect(x: 0, y: CGFloat(count - 1 - row) / CGFloat(count), width: 1, height: 1 / CGFloat(count)), in: sheet)
            cell.filteringMode = .nearest
            return cell
        }
    }
    /// A billboard (`Billboard`, its blank face 126 by 62 at 4, 11 from its top left) with one of the
    /// five ads (`ad1`...`ad5`) on its face at random, at half size, between the sand and the
    /// foreground, its foot hidden in the foreground's ground; sliding by at `billboardSpeed`; as
    /// rare as the cargo truck in the traffic, one in `billboardOdds` of the vehicles that come.
    static let billboardFace = CGPoint(x: 4, y: 11)
    static let billboardScale: CGFloat = 0.5
    static let billboardZ = slidingZ + 0.025
    static let billboardFoot: CGFloat = 55
    static let billboardSpeed = roadSpeed * 3 / 4
    static let billboardOdds = 20
    static let adCount = 5
    /// The plane (`FlightB411Plane`) far off now and then, `planeGap` seconds apart: in off either side,
    /// between the mountains and the rocks, coming down from `planeHigh` to `planeLow` over its crossing
    /// at `planeSpeed` art pixels a second, its nose down along its path, at `planeScale`.
    static let planeScale: CGFloat = 0.0625
    static let planeZ = slidingZ + 0.005
    static let planeGap: ClosedRange<Double> = 30...90
    static let planeSpeed: CGFloat = 24
    static let planeHigh: CGFloat = 260
    static let planeLow: CGFloat = 100

    /// The oncoming traffic: white trucks (`Truck`, no pole, its lights grey) half the time, cars
    /// (`Car_v4`, its greys and white in a colour ramp at random) `trafficCarShare` in a hundred,
    /// and cargo trucks (`BallTruck`, door shut, no ball on its side) the rest; facing left, at `trafficScale`, a third (`trafficTint`) of
    /// palette 8 over them, their bottoms on the third row of tiles, on the far lane; one every
    /// coming now and then, each at its own speed (below).
    /// Drawn only: nothing meets them.
    static let trafficScale: CGFloat = 0.75
    static let trafficTintColour: RGB = PixelPalette.colours[8]
    static let trafficTint: CGFloat = 0.33
    static let trafficBottom: CGFloat = 48
    /// Not evenly: a share of them close behind the last (`trafficTailgate` in a hundred, `trafficCloseGap`
    /// seconds after it), the rest `trafficGap`; each at the road's speed and its own (`trafficOwnSpeed`).
    static let trafficGap: ClosedRange<Double> = 1.0...5.0
    static let trafficCloseGap: ClosedRange<Double> = 0.3...0.8
    static let trafficTailgate = 30
    static let trafficOwnSpeed: ClosedRange<CGFloat> = 160...480
    static let trafficZ: CGFloat = -7.82
    /// In a hundred: white trucks, then cars; the rest cargo trucks.
    static let trafficTruckShare = 50
    static let trafficCarShare = 45
    /// The car's paint, dark to light (its greys and its white), and the ramps it's swapped for:
    /// red, blue, green, orange, purple, yellow, navy and brown.
    static let carGreys: [RGB] = [0x5D5D5D, 0x858585, 0xB4B4B4, 0xFFFFFF]
    static let trafficRamps: [[Int]] = [[41, 42, 43, 44], [21, 20, 19, 18], [26, 27, 28, 29], [37, 32, 33, 34],
                                        [49, 48, 47, 55], [33, 34, 35, 1], [11, 12, 13, 14], [5, 4, 3, 2]]

    /// The car idles a frame out of step with the truck.
    static let carBobPhase = 1
    /// The hubs (`WheelHub`) over the near wheels, their middles in art pixels from each picture's bottom left.
    static let carHubMiddles = [CGPoint(x: 31.5, y: 5.5), CGPoint(x: 87.5, y: 5.5)]
    static let truckHubMiddles = [CGPoint(x: 31.5, y: 6.5), CGPoint(x: 87.5, y: 6.5)]

    /// The car's body this frame, up in art pixels from where its wheels stand: idling, and down a
    /// pixel more with anyone on it.
    static func carIdle(at frame: Int, ridden: Bool) -> CGFloat {
        (((frame / AnoziraRules.bobFrames + carBobPhase) % 2 == 0) ? 0 : 1) - (ridden ? 1 : 0)
    }
    /// A point on the hoop truck, where the match has it, to where it's drawn: jolted over a pothole
    /// and scaled about the truck's foot as it veers, as every piece of the truck is (`lay`), so the
    /// hoop stays on its pole.
    static func onTruck(_ point: CGPoint, match: Match) -> CGPoint {
        let truck = match.anoziraTruck
        let origin = SpriteLibrary.point(truck.origin)
        let jolt = CGPoint(x: shake(since: match.truckBumpAt, frame: match.frame, lasting: AnoziraRules.hoopJump.count),
                           y: jump(since: match.truckBumpAt, frame: match.frame))
        let size = scale(veered: SpriteLibrary.point(truck.standing).y)
        let foot = CGPoint(x: origin.x + CGFloat(AnoziraRules.truckWidth) / 2, y: origin.y)
        return CGPoint(x: foot.x + (point.x - foot.x) * size, y: foot.y + (point.y - foot.y) * size) + jolt
    }

    /// A vehicle's jump over a pothole, wheels and all, art pixels: the car's this frame, or any's.
    static func carJump(_ match: Match) -> CGFloat { jump(since: match.carBumpAt, frame: match.frame) }
    static func jump(since bumped: Int?, frame: Int) -> CGFloat {
        let into = bumped.map { frame - $0 } ?? -1
        return AnoziraRules.carJump.indices.contains(into) ? CGFloat(AnoziraRules.carJump[into]) : 0
    }

    /// A pothole's shake, across, art pixels: a pixel either way every other frame while it lasts.
    static func shake(since bumped: Int?, frame: Int, lasting: Int) -> CGFloat {
        guard let bumped, frame - bumped < lasting else { return 0 }
        return (frame - bumped) % 4 < 2 ? 1 : -1
    }

    /// A vehicle's size, its wheels' foot at `y`: smaller veered up its lane, larger down it.
    static func scale(veered y: CGFloat) -> CGFloat {
        let veered = (y - CGFloat(AnoziraRules.floorRows) * ElementsArt.tileSide) / CGFloat(AnoziraRules.veerMost)
        return 1 - veerScale * min(max(veered, -1), 1)
    }

    /// One of a vehicle's pieces, its picture's bottom left at `origin`, scaled about the middle of
    /// its foot, `width` across; `offset` the piece's own place on the picture, for one anchored there.
    static func lay(_ node: SKSpriteNode?, at origin: CGPoint, width: CGFloat, scale: CGFloat, offset: CGPoint = .zero) {
        guard let node else { return }
        node.position = CGPoint(x: origin.x + width / 2 + (offset.x - width / 2) * scale, y: origin.y + offset.y * scale)
        node.xScale = scale * (node.xScale < 0 ? -1 : 1)
        node.yScale = scale
    }

    /// Breaker Ball's cars, each painted in its player's ramp, dark to light, in place of its greys.
    static func paintCars(_ handles: Handles, ramps: [[RGB]]) {
        guard let body = SKTexture(imageNamed: "AnoziraCarBody").cgImage() as CGImage? else { return }
        for (node, ramp) in zip([handles.carBody, handles.secondCarBody], ramps) {
            var swaps: [RGB: RGB] = [:]
            for (grey, colour) in zip(carGreys, ramp) { swaps[grey] = colour }
            guard let painted = recoloured(body, swaps: swaps) else { continue }
            let texture = SKTexture(cgImage: painted)
            texture.filteringMode = .nearest
            node?.texture = texture
        }
    }

    /// On Breaker Ball's second car, where it is.
    static func standsOnSecondCar(_ player: Player, match: Match) -> Bool {
        let car = CarRules.collision(at: match.anoziraSecondCar, facesRight: true)
        let body = player.body, middle = (body.min.x + body.max.x) / 2
        return player.grounded
            && (car.tops.contains { body.min.x < $0.max.x && body.max.x > $0.min.x && abs($0.max.y - body.min.y) < 0.01 }
                || car.slopes.contains { $0.box.min.x <= middle && middle <= $0.box.max.x && abs($0.surface(at: middle) - body.min.y) < 0.01 })
    }

    /// Whether anyone stands on the car, which dips it.
    static func carRidden(_ match: Match) -> Bool { match.players.contains(where: { standsOnCar($0, match: match) }) }
    /// On the car's tops or slopes, where it is.
    static func standsOnCar(_ player: Player, match: Match) -> Bool {
        let car = CarRules.collision(at: match.anoziraCar, facesRight: true)
        let body = player.body, middle = (body.min.x + body.max.x) / 2
        return player.grounded
            && (car.tops.contains { body.min.x < $0.max.x && body.max.x > $0.min.x && abs($0.max.y - body.min.y) < 0.01 }
                || car.slopes.contains { $0.box.min.x <= middle && middle <= $0.box.max.x && abs($0.surface(at: middle) - body.min.y) < 0.01 })
    }
    /// The holder's colour eases in and out by this share a frame.
    static let tintEase: CGFloat = 0.15

    static func build(into parent: SKNode, glowers: SKNode) -> Handles {
        let handles = Handles()
        func picture(_ name: String, z: CGFloat, into parent: SKNode = parent) -> SKSpriteNode {
            let texture = SKTexture(imageNamed: name)
            texture.filteringMode = .nearest
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = .zero
            node.size = texture.size()
            node.zPosition = z
            parent.addChild(node)
            SKTexture.preload([texture]) {}
            return node
        }
        let background = picture("AnoziraBackground", z: backgroundZ)
        background.position = fileOrigin
        handles.background = background
        handles.skyTurns = zip(["AnoziraSkyOrange", "AnoziraSkyYellow"], skyTurnColours).map { name, colour in
            let turn = picture(name, z: backgroundZ + 0.001)
            turn.position = fileOrigin
            turn.color = SKColor(rgb: colour)
            turn.colorBlendFactor = 1
            turn.alpha = 0
            return turn
        }
        for (step, layer) in slidingLayers.enumerated() {
            let copies = (0..<3).map { _ in picture(layer.name, z: slidingZ + CGFloat(step) * 0.01) }
            // Under the road, washed back; the sky behind them stays bright.
            if layer.name != "AnoziraRoad" {
                for copy in copies {
                    copy.color = SKColor(rgb: underWashColour)
                    copy.colorBlendFactor = underWashAlpha
                }
            }
            let width = copies[0].size.width
            let bottom = fileOrigin.y + fileHeight - layer.top - copies[0].size.height
            for copy in copies { copy.position.y = bottom }
            handles.sliding.append((copies, width, fileOrigin.x, layer.speed))
        }
        handles.carWheels = picture("AnoziraCarWheels", z: carZ)
        handles.carBody = picture("AnoziraCarBody", z: carZ + 0.01)
        // The tint over the body, in the glowers, still behind the bodies (theirs is 20, the glowers' 21).
        let tint = picture("AnoziraCarTint", z: carZ + 0.02 - 21, into: glowers)
        tint.colorBlendFactor = 1
        tint.alpha = 0
        handles.carTint = tint
        let bar = picture("AnoziraTruckBar", z: truckZ - 0.02)
        bar.anchorPoint = CGPoint(x: CGFloat(AnoziraRules.poleFoot.x) / bar.size.width, y: CGFloat(AnoziraRules.poleFoot.y) / bar.size.height)
        handles.truckBar = bar
        handles.truckWheels = picture("AnoziraTruckWheels", z: truckZ - 0.01)
        handles.truckBody = picture("AnoziraTruckBody", z: truckZ)
        handles.truckLights = ["AnoziraTruckLightsLight", "AnoziraTruckLightsDark"].map { name in
            let lights = picture(name, z: truckZ + 0.01 - 21, into: glowers)
            lights.colorBlendFactor = 1
            return lights
        }
        handles.secondCarWheels = picture("AnoziraCarWheels", z: carZ)
        handles.secondCarBody = picture("AnoziraCarBody", z: carZ + 0.01)
        let secondTint = picture("AnoziraCarTint", z: carZ + 0.02 - 21, into: glowers)
        secondTint.colorBlendFactor = 1
        secondTint.alpha = 0
        handles.secondCarTint = secondTint
        handles.carHubs = WheelHub.nodes(carHubMiddles.count, z: carZ + 0.005, into: parent)
        handles.secondCarHubs = WheelHub.nodes(carHubMiddles.count, z: carZ + 0.005, into: parent)
        handles.truckHubs = WheelHub.nodes(truckHubMiddles.count, z: truckZ - 0.005, into: parent)
        handles.trafficPictures = trafficPictures()
        handles.billboardPictures = billboardPictures()
        let planeTexture = SKTexture(imageNamed: "FlightB411Plane")
        let plane = SKSpriteNode(texture: planeTexture)
        plane.size = CGSize(width: planeTexture.size().width * planeScale, height: planeTexture.size().height * planeScale)
        plane.zPosition = planeZ
        plane.color = SKColor(rgb: underWashColour)
        plane.colorBlendFactor = underWashAlpha
        plane.isHidden = true
        parent.addChild(plane)
        handles.plane = plane
        let flag = SKSpriteNode(texture: flagFrames.first)
        flag.anchorPoint = flagAnchor
        flag.size = CGSize(width: 32 * flagScale, height: 32 * flagScale)
        flag.zPosition = truckZ + 0.02
        parent.addChild(flag)
        handles.flag = flag
        handles.phoenix = zip(phoenixFrames, phoenixDepths).map { frames, depth in
            let node = SKSpriteNode(texture: frames.first)
            node.anchorPoint = .zero
            node.size = CGSize(width: CGFloat(AnoziraRules.phoenixWidth), height: 32)
            node.zPosition = depth
            node.isHidden = true
            glowers.addChild(node)
            SKTexture.preload(frames) {}
            return node
        }
        return handles
    }

    /// The billboard with each ad on its face.
    private static func billboardPictures() -> [SKTexture] {
        guard let board = SKTexture(imageNamed: "AnoziraBillboard").cgImage() as CGImage? else { return [] }
        return (1...adCount).compactMap { index -> SKTexture? in
            let ad = SKTexture(imageNamed: "AnoziraAd\(index)").cgImage()
            guard let context = CGContext(data: nil, width: board.width, height: board.height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .none
            context.draw(board, in: CGRect(x: 0, y: 0, width: board.width, height: board.height))
            context.draw(ad, in: CGRect(x: Int(billboardFace.x), y: board.height - Int(billboardFace.y) - ad.height, width: ad.width, height: ad.height))
            guard let image = context.makeImage() else { return nil }
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .nearest
            return texture
        }
    }

    /// The plane far off: in off a side at random every `planeGap`, down across, gone off the other.
    private static func flyPlane(_ handles: Handles, at time: CFTimeInterval) {
        guard let plane = handles.plane else { return }
        let width = CGFloat(AnoziraRules.columns) * ElementsArt.tileSide
        if handles.nextPlaneAt == nil { handles.nextPlaneAt = time + .random(in: planeGap) }
        if handles.planeFlight == nil, let next = handles.nextPlaneAt, time >= next {
            handles.planeFlight = (time, Bool.random())
        }
        guard let flight = handles.planeFlight else { plane.isHidden = true; return }
        let across = width + plane.size.width * 2
        let flown = CGFloat(time - flight.start) * planeSpeed
        guard flown <= across else {
            handles.planeFlight = nil
            handles.nextPlaneAt = time + .random(in: planeGap)
            plane.isHidden = true
            return
        }
        let share = flown / across
        let x = -plane.size.width + flown
        plane.isHidden = false
        plane.position = CGPoint(x: (flight.rightward ? x : width - x).rounded(), y: (planeHigh + (planeLow - planeHigh) * share).rounded())
        // Its picture faces left: flipped going right, the nose turned down the path.
        let descent = atan((planeHigh - planeLow) / across)
        plane.xScale = flight.rightward ? -1 : 1
        plane.zRotation = flight.rightward ? -descent : descent
    }

    /// The traffic's pictures: the car in each ramp over its wheels, and the truck's body over its
    /// wheels with its lights grey.
    private static func trafficPictures() -> [SKTexture] {
        func image(_ name: String) -> CGImage? { SKTexture(imageNamed: name).cgImage() }
        let cars = trafficRamps.compactMap { ramp -> SKTexture? in
            var swaps: [RGB: RGB] = [:]
            for (grey, index) in zip(carGreys, ramp) { swaps[grey] = PixelPalette.colours[index] }
            guard let wheels = image("AnoziraCarWheels"), let body = image("AnoziraCarBody").flatMap({ recoloured($0, swaps: swaps) }) else { return nil }
            return composite([wheels, body])
        }
        let truck = image("AnoziraTruckBody").flatMap { recoloured($0, swaps: [0xE69C69: unheldLightsRGB.light, 0xBF6F4A: unheldLightsRGB.dark]) }
        let trucks = [image("AnoziraTruckWheels"), truck].compactMap { $0 }
        let cargo = ["BallTruckWheelsBack", "BallTruckCargo", "BallTruckWheelsFront", "BallTruckBody"].compactMap(image)
        return cars + [trucks.count == 2 ? composite(trucks) : nil, cargo.count == 4 ? composite(cargo) : nil].compactMap { $0 }
    }

    private static func recoloured(_ image: CGImage, swaps: [RGB: RGB]) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for pixel in 0..<(width * height) where pixels[pixel * 4 + 3] == 255 {
            let index = pixel * 4
            let rgb = RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])
            guard let swap = swaps[rgb] else { continue }
            pixels[index] = UInt8((swap >> 16) & 0xFF)
            pixels[index + 1] = UInt8((swap >> 8) & 0xFF)
            pixels[index + 2] = UInt8(swap & 0xFF)
        }
        return context.makeImage()
    }

    /// Pictures the same size laid one over the next, the first lowest.
    private static func composite(_ images: [CGImage]) -> SKTexture? {
        guard let first = images.first,
              let context = CGContext(data: nil, width: first.width, height: first.height, bitsPerComponent: 8, bytesPerRow: first.width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        for image in images { context.draw(image, in: CGRect(x: 0, y: 0, width: first.width, height: first.height)) }
        guard let made = context.makeImage() else { return nil }
        let texture = SKTexture(cgImage: made)
        texture.filteringMode = .nearest
        return texture
    }

    /// The traffic a frame on: each one further along, gone once it's off the left; the next on its
    /// way in from the right when it's due.
    private static func driveTraffic(_ handles: Handles, into parent: SKNode?, at time: CFTimeInterval, rain: Double) {
        let step = CGFloat(min(time - (handles.lastTime ?? time), 0.1))
        handles.lastTime = time
        for (vehicle, speed) in zip(handles.traffic, handles.trafficSpeeds) { vehicle.position.x -= speed * step }
        // Veering in the rain, smaller up the far lane, larger down it.
        for (vehicle, salt) in zip(handles.traffic, handles.trafficVeers) {
            let veer = CGFloat(AnoziraRules.veer(at: Int(time * 60), rain: rain, salt: salt) * 1.6)
            vehicle.position.y = trafficBottom + veer
            let size = trafficScale * (1 - veerScale * veer / CGFloat(AnoziraRules.veerMost))
            vehicle.xScale = -size / trafficScale
            vehicle.yScale = size / trafficScale
        }
        for index in handles.traffic.indices.reversed() where handles.traffic[index].position.x < -handles.traffic[index].size.width {
            handles.traffic[index].removeFromParent()
            handles.traffic.remove(at: index)
            handles.trafficVeers.remove(at: index)
            handles.trafficSpeeds.remove(at: index)
        }
        for board in handles.billboards { board.position.x -= billboardSpeed * step }
        for index in handles.billboards.indices.reversed() where handles.billboards[index].position.x < -handles.billboards[index].size.width {
            handles.billboards[index].removeFromParent()
            handles.billboards.remove(at: index)
        }
        guard time >= handles.nextVehicleAt, let parent, !handles.trafficPictures.isEmpty else { return }
        handles.nextVehicleAt = time + .random(in: Int.random(in: 0..<100) < trafficTailgate ? trafficCloseGap : trafficGap)
        if Int.random(in: 0..<billboardOdds) == 0, let picture = handles.billboardPictures.randomElement() {
            let board = SKSpriteNode(texture: picture)
            board.anchorPoint = .zero
            board.size = CGSize(width: picture.size().width * billboardScale, height: picture.size().height * billboardScale)
            board.color = SKColor(rgb: underWashColour)
            board.colorBlendFactor = underWashAlpha
            board.zPosition = billboardZ
            board.position = CGPoint(x: CGFloat(AnoziraRules.columns) * ElementsArt.tileSide, y: billboardFoot)
            parent.addChild(board)
            handles.billboards.append(board)
        }
        // The cars first in the pictures, then the white truck, then the cargo truck.
        let pictures = handles.trafficPictures, cars = min(trafficRamps.count, pictures.count)
        let roll = Int.random(in: 0..<100)
        let picture: SKTexture
        if roll < trafficTruckShare, pictures.count > cars {
            picture = pictures[cars]
        } else if roll < trafficTruckShare + trafficCarShare || pictures.count <= cars + 1 {
            picture = pictures[Int.random(in: 0..<cars)]
        } else {
            picture = pictures[cars + 1]
        }
        let vehicle = SKSpriteNode(texture: picture)
        vehicle.size = CGSize(width: picture.size().width * trafficScale, height: picture.size().height * trafficScale)
        // Facing left, coming the other way: its picture's right edge its front.
        vehicle.anchorPoint = .zero
        vehicle.xScale = -1
        vehicle.color = SKColor(rgb: trafficTintColour)
        vehicle.colorBlendFactor = trafficTint
        vehicle.zPosition = trafficZ
        vehicle.position = CGPoint(x: CGFloat(AnoziraRules.columns) * ElementsArt.tileSide + vehicle.size.width, y: trafficBottom)
        parent.addChild(vehicle)
        handles.traffic.append(vehicle)
        handles.trafficVeers.append(UInt32.random(in: 0...UInt32.max))
        handles.trafficSpeeds.append(roadSpeed + .random(in: trafficOwnSpeed))
    }

    private static func blend(_ from: SKColor, _ to: SKColor, by share: CGFloat) -> SKColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return SKColor(red: r1 + (r2 - r1) * share, green: g1 + (g2 - g1) * share, blue: b1 + (b2 - b1) * share, alpha: 1)
    }

    /// A frame on: the layers slid, the car and the truck where the match has them, idling, and the
    /// holder's colour eased on or off.
    static func animate(_ handles: Handles, match: Match, holderColours: Colours?, breakerBrights: [SKColor] = [], at time: CFTimeInterval) {
        driveTraffic(handles, into: handles.background?.parent, at: time, rain: match.rain)
        flyPlane(handles, at: time)
        for layer in handles.sliding {
            let slid = (CGFloat(time) * layer.speed).truncatingRemainder(dividingBy: layer.width).rounded()
            for (index, copy) in layer.copies.enumerated() {
                copy.position.x = layer.left + CGFloat(index - 1) * layer.width - slid
            }
        }
        // The sky turning as it comes over, the warning. The rain's wash is the composite's (`GameScene.worldWash`).
        for turn in handles.skyTurns { turn.alpha = CGFloat(match.overcast) }
        // The potholes where the match has them.
        while handles.potholes.count < match.potholes.count, let parent = handles.background?.parent {
            let hole = SKSpriteNode(texture: SKTexture(imageNamed: "AnoziraPothole"))
            hole.texture?.filteringMode = .nearest
            hole.size = hole.texture?.size() ?? .zero
            hole.zPosition = slidingZ + 0.055
            parent.addChild(hole)
            handles.potholes.append(hole)
        }
        for (index, hole) in handles.potholes.enumerated() {
            hole.isHidden = index >= match.potholes.count
            guard !hole.isHidden else { continue }
            // Each its own height, from the frame it came in on, which it keeps.
            let x = match.potholes[index]
            let cameIn = match.frame - Int(((match.stage.width + Stage.tileSize - x) / AnoziraRules.potholeSpeed).rounded())
            let lift = Int(AnoziraRules.mixed(cameIn, salt: 0x4F1E) % UInt32(potholeSpread * 2 + 1)) - potholeSpread
            hole.position = CGPoint(x: CGFloat(x * SpriteLibrary.pixelsPerUnit).rounded(), y: potholeY + CGFloat(lift))
        }
        // The wheels where they stand, the bodies over them idling, dipping, and jumping and shaking
        // over a pothole; every piece smaller veered up the lane in the rain, larger down it.
        let turn = WheelHub.turn(at: time, rolling: roadSpeed)
        let carWheelsAt = SpriteLibrary.point(match.anoziraCar)
        let carSize = scale(veered: carWheelsAt.y)
        let carJumped = carWheelsAt + CGPoint(x: shake(since: match.carBumpAt, frame: match.frame, lasting: AnoziraRules.carJump.count), y: carJump(match))
        let carAt = carJumped + CGPoint(x: 0, y: carIdle(at: match.frame, ridden: carRidden(match)))
        lay(handles.carWheels, at: carJumped, width: 128, scale: carSize)
        for node in [handles.carBody, handles.carTint] { lay(node, at: carAt, width: 128, scale: carSize) }
        for (hub, middle) in zip(handles.carHubs, carHubMiddles) {
            lay(hub, at: carJumped, width: 128, scale: carSize, offset: middle)
            hub.zRotation = turn
        }
        // Breaker Ball: no truck, a second car in its place, each car glowing in its own player's bright
        // while they hold the ball.
        let breaker = match.mode == .breakerBall
        for node in [handles.truckBar, handles.truckWheels, handles.truckBody, handles.flag].compactMap({ $0 }) + handles.truckLights + handles.truckHubs {
            node.isHidden = breaker
        }
        for node in [handles.secondCarWheels, handles.secondCarBody, handles.secondCarTint].compactMap({ $0 }) + handles.secondCarHubs {
            node.isHidden = !breaker
        }
        if breaker {
            let secondWheelsAt = SpriteLibrary.point(match.anoziraSecondCar)
            let secondSize = scale(veered: secondWheelsAt.y)
            let secondJumped = secondWheelsAt + CGPoint(x: shake(since: match.secondCarBumpAt, frame: match.frame, lasting: AnoziraRules.carJump.count),
                                                        y: jump(since: match.secondCarBumpAt, frame: match.frame))
            let secondRidden = match.players.contains { standsOnSecondCar($0, match: match) }
            let secondAt = secondJumped + CGPoint(x: 0, y: carIdle(at: match.frame + 1, ridden: secondRidden))
            lay(handles.secondCarWheels, at: secondJumped, width: 128, scale: secondSize)
            for node in [handles.secondCarBody, handles.secondCarTint] { lay(node, at: secondAt, width: 128, scale: secondSize) }
            for (hub, middle) in zip(handles.secondCarHubs, carHubMiddles) {
                lay(hub, at: secondJumped, width: 128, scale: secondSize, offset: middle)
                hub.zRotation = turn
            }
            handles.wheelContacts = (carHubMiddles.map { (CGPoint(x: carWheelsAt.x + 64 + ($0.x - 64) * carSize, y: carWheelsAt.y), carZ + 0.03) }
                + carHubMiddles.map { (CGPoint(x: secondWheelsAt.x + 64 + ($0.x - 64) * secondSize, y: secondWheelsAt.y), carZ + 0.03) })
            flyPhoenix(handles, match: match, at: time)
            for (index, tint) in [handles.carTint, handles.secondCarTint].enumerated() {
                handles.carTintShares[index] += ((match.ball.holder == index ? 1 : 0) - handles.carTintShares[index]) * tintEase
                if handles.carTintShares[index] < 0.01 { handles.carTintShares[index] = 0 }
                if let colour = breakerBrights.indices.contains(index) ? breakerBrights[index] : nil { tint?.color = colour }
                tint?.alpha = handles.carTintShares[index]
            }
            handles.tintShare = handles.carTintShares[0]
            return
        }
        let truck = match.anoziraTruck
        let truckJolt = CGPoint(x: shake(since: match.truckBumpAt, frame: match.frame, lasting: AnoziraRules.hoopJump.count),
                                y: jump(since: match.truckBumpAt, frame: match.frame))
        let standing = SpriteLibrary.point(truck.standing)
        let wheelsAt = standing + truckJolt
        let origin = SpriteLibrary.point(truck.origin) + truckJolt
        let truckSize = scale(veered: standing.y)
        lay(handles.truckWheels, at: wheelsAt, width: 128, scale: truckSize)
        for node in [handles.truckBody].compactMap({ $0 }) + handles.truckLights { lay(node, at: origin, width: 128, scale: truckSize) }
        for (hub, middle) in zip(handles.truckHubs, truckHubMiddles) {
            lay(hub, at: wheelsAt, width: 128, scale: truckSize, offset: middle)
            hub.zRotation = turn
        }
        handles.wheelContacts = carHubMiddles.map { (CGPoint(x: carWheelsAt.x + 64 + ($0.x - 64) * carSize, y: carWheelsAt.y), carZ + 0.03) }
            + truckHubMiddles.map { (CGPoint(x: standing.x + 64 + ($0.x - 64) * truckSize, y: standing.y), truckZ + 0.03) }
        // The pole leaning, and jumping in its bed over a pothole.
        if let bar = handles.truckBar {
            lay(bar, at: origin, width: 128, scale: truckSize,
                offset: CGPoint(x: CGFloat(AnoziraRules.poleFoot.x), y: CGFloat(AnoziraRules.poleFoot.y) + CGFloat(truck.jump * 1.6).rounded()))
            bar.zRotation = CGFloat(truck.lean)
        }
        if let flag = handles.flag {
            lay(flag, at: origin, width: 128, scale: truckSize, offset: flagFoot)
            let frame = Int(time * flagFramesPerSecond) % max(flagFrames.count, 1)
            if flagFrames.indices.contains(frame) { flag.texture = flagFrames[frame] }
        }
        flyPhoenix(handles, match: match, at: time)
        if let holderColours { handles.tintColours = holderColours }
        handles.tintShare += ((holderColours == nil ? 0 : 1) - handles.tintShare) * tintEase
        if handles.tintShare < 0.01 { handles.tintShare = 0 }
        handles.carTint?.color = handles.tintColours.car
        handles.carTint?.alpha = handles.tintShare
        // The lights from grey to the holder's colours and back.
        for (lights, (unheld, held)) in zip(handles.truckLights, [(unheldLights.light, handles.tintColours.light), (unheldLights.dark, handles.tintColours.dark)]) {
            lights.color = blend(unheld, held, by: handles.tintShare)
        }
    }

    /// The Phoenix where the match has it, flapping, sparkles falling off it; out of sight while it's away.
    private static func flyPhoenix(_ handles: Handles, match: Match, at time: CFTimeInterval) {
        let at = match.phoenix.flatMap { AnoziraRules.phoenix($0, at: match.frame) }.map { SpriteLibrary.point($0) }
        let frame = Int(time * phoenixFramesPerSecond)
        for (node, frames) in zip(handles.phoenix, phoenixFrames) {
            node.isHidden = at == nil
            guard let at, !frames.isEmpty else { continue }
            node.position = CGPoint(x: at.x.rounded(), y: at.y.rounded())
            node.texture = frames[frame % frames.count]
        }
        // Held with the stage clock, paused or in hit-stop.
        let step = max(time - (handles.phoenixLastTime ?? time), 0)
        handles.phoenixLastTime = time
        handles.phoenixSparkles = handles.phoenixSparkles.compactMap { sparkle in
            let age = sparkle.age + step
            guard age < phoenixSparkleSeconds else { sparkle.node.removeFromParent(); return nil }
            let pop = CGFloat(sin(age / phoenixSparkleSeconds * .pi))
            sparkle.node.size = CGSize(width: 5 * pop, height: 5 * pop)
            sparkle.node.position.y -= phoenixSparkleFall * CGFloat(step)
            return (sparkle.node, age)
        }
        guard let at, let parent = handles.phoenix.first?.parent, Double.random(in: 0..<1) < phoenixSparklesPerSecond * step else { return }
        let sparkle = SKSpriteNode(texture: sparkleTexture)
        sparkle.size = .zero
        sparkle.blendMode = .add
        sparkle.zPosition = phoenixDepths[1] + 0.01
        sparkle.position = CGPoint(x: (at.x + CGFloat.random(in: 0...CGFloat(AnoziraRules.phoenixWidth))).rounded(), y: (at.y + CGFloat.random(in: 4...28)).rounded())
        parent.addChild(sparkle)
        handles.phoenixSparkles.append((sparkle, 0))
    }
}
