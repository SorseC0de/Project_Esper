import EsperSim
import SpriteKit

/// A vehicle's hub (`wheel_hub.png`, 9 by 9) over a near wheel, turning clockwise as fast as a wheel
/// `wheelRadius` art pixels round rolls along the ground at a speed.
enum WheelHub {
    static let wheelRadius: CGFloat = 8

    static func nodes(_ count: Int, z: CGFloat, into parent: SKNode) -> [SKSpriteNode] {
        let hub = SKTexture(imageNamed: "WheelHub")
        hub.filteringMode = .nearest
        return (0..<count).map { _ in
            let node = SKSpriteNode(texture: hub)
            node.size = hub.size()
            node.zPosition = z
            parent.addChild(node)
            return node
        }
    }

    /// The turn at `time`, rolling at `speed` art pixels a second.
    static func turn(at time: CFTimeInterval, rolling speed: CGFloat) -> CGFloat {
        -(CGFloat(time) * speed / wheelRadius).truncatingRemainder(dividingBy: 2 * .pi)
    }
}

/// The ball truck (`BallTruck.aseprite`, `BallTruckRules`), on a stage that has one: its parts back to
/// front, the far wheels, the cargo door (shown only open, once the ball's let out), the cargo,
/// the near wheels with their hubs turning, and the body; where the match has it, gone with it.
/// The ball, in it or coming out of it, draws between the far wheels and the door, till it's out
/// past the door's left edge, `doorLeft` along the picture. On its side, in the gap in the cargo's
/// stripes, the ball's sprite at `decalSize`, palette `decalColour`, turned 45 degrees and then
/// squeezed to `decalSqueeze` across.
enum BallTruckArt {
    final class Handles {
        var parts: [SKSpriteNode] = []
        var wheelParts: [SKSpriteNode] = []
        var door: SKSpriteNode?
        /// The ball on its side: the squeeze, holding the turned ball.
        var decal: SKNode?
        var decalBall: SKSpriteNode?
        var hubs: [SKSpriteNode] = []
        /// Where its near wheels meet the road this frame, for the skid sparks.
        var wheelContacts: [CGPoint] = []
        /// What's drawn as painted, which mustn't glow.
        var flats: [SKSpriteNode] { (parts + hubs).filter { !$0.isHidden } }
        /// The decal, which the mask takes as drawn, turned and squeezed.
        var decalSnapshot: BodySnapshot? {
            guard let decal, let ball = decalBall, !decal.isHidden, let texture = ball.texture else { return nil }
            return BodySnapshot(texture: texture, position: decal.position, anchor: CGPoint(x: 0.5, y: 0.5), xScale: 1,
                                size: CGSize(width: decalSize * decalSqueeze, height: decalSize), zRotation: 0)
        }
    }

    /// Under the bodies and the hoop truck (Anozira's is at 3): its parts a step apart from here.
    static let z: CGFloat = 2.9
    static let ballUnderDoorZ: CGFloat = z + 0.005
    static let doorLeft: CGFloat = 7
    static let hubMiddles = [CGPoint(x: 47.5, y: 6.5), CGPoint(x: 119.5, y: 6.5)]
    /// The decal's middle on the picture, in the stripes' gap; its size, twice the ball's in play.
    static let decalMiddle = CGPoint(x: 47, y: 40.5)
    static let decalSize: CGFloat = 16
    static let decalColour: RGB = PixelPalette.colours[58]
    static let decalTurn: CGFloat = .pi / 4
    static let decalSqueeze: CGFloat = 0.9
    /// Its wheels turn as the road under it slides.
    static let rolling: CGFloat = AnoziraArt.roadSpeed

    static func build(into parent: SKNode, ball: SKTexture) -> Handles {
        let handles = Handles()
        handles.parts = ["BallTruckWheelsBack", "BallTruckDoor", "BallTruckCargo", "BallTruckWheelsFront", "BallTruckBody"].enumerated().map { step, name in
            let texture = SKTexture(imageNamed: name)
            texture.filteringMode = .nearest
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = .zero
            node.size = texture.size()
            node.zPosition = z + CGFloat(step) * 0.01
            parent.addChild(node)
            return node
        }
        handles.door = handles.parts[1]
        handles.wheelParts = [handles.parts[0], handles.parts[3]]
        // Over the cargo, under the near wheels.
        let decal = SKNode()
        decal.xScale = decalSqueeze
        decal.zPosition = z + 0.025
        let decalBall = SKSpriteNode(texture: ball)
        decalBall.size = CGSize(width: decalSize, height: decalSize)
        decalBall.zRotation = decalTurn
        decalBall.color = SKColor(rgb: decalColour)
        decalBall.colorBlendFactor = 1
        decal.addChild(decalBall)
        parent.addChild(decal)
        handles.decal = decal
        handles.decalBall = decalBall
        handles.hubs = WheelHub.nodes(hubMiddles.count, z: z + 0.035, into: parent)
        return handles
    }

    static func animate(_ handles: Handles, match: Match, at time: CFTimeInterval) {
        let truck = match.ballTruck
        let standing = truck.map { SpriteLibrary.point($0.standing) } ?? .zero
        // Its body jumping and shaking over a pothole, as the car's does; all of it smaller veered
        // up its lane in the rain, larger down it.
        let into = match.ballTruckBumpAt.map { match.frame - $0 } ?? -1
        let jump = AnoziraRules.carJump.indices.contains(into) ? CGFloat(AnoziraRules.carJump[into]) : 0
        let at = (truck.map { SpriteLibrary.point($0.origin) } ?? .zero)
            + CGPoint(x: AnoziraArt.shake(since: match.ballTruckBumpAt, frame: match.frame, lasting: AnoziraRules.carJump.count), y: jump)
        let size = AnoziraArt.scale(veered: standing.y)
        let width = CGFloat(BallTruckRules.width)
        for part in handles.parts {
            part.isHidden = truck == nil
            AnoziraArt.lay(part, at: handles.wheelParts.contains(part) ? standing + CGPoint(x: 0, y: jump) : at, width: width, scale: size)
        }
        handles.door?.isHidden = !(truck?.doorOpen ?? false)
        handles.decal?.isHidden = truck == nil
        handles.decal?.position = CGPoint(x: at.x + width / 2 + (decalMiddle.x - width / 2) * size, y: at.y + decalMiddle.y * size)
        handles.decal?.yScale = size
        handles.decal?.xScale = decalSqueeze * size
        let turn = WheelHub.turn(at: time, rolling: rolling)
        handles.wheelContacts = truck == nil ? [] : hubMiddles.map { CGPoint(x: standing.x + width / 2 + ($0.x - width / 2) * size, y: standing.y) }
        for (hub, middle) in zip(handles.hubs, hubMiddles) {
            hub.isHidden = truck == nil
            AnoziraArt.lay(hub, at: standing + CGPoint(x: 0, y: jump), width: width, scale: size, offset: middle)
            hub.zRotation = turn
        }
    }


    /// Whether the loose ball, `at` and this far round, is still in the ball truck or coming out of it under its door.
    static func ballInTruck(at point: CGPoint, radius: CGFloat, match: Match) -> Bool {
        guard let truck = match.ballTruck, match.ball.holder == nil else { return false }
        return point.x - radius > SpriteLibrary.point(truck.origin).x + doorLeft
    }
}
