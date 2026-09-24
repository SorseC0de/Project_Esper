import Foundation

/// The player's sprites, as the importer names them. Frame counts and rates come from the
/// GMS2 sprites and the strips in `_Graphic Assets`; run `Tools/import_sprites.py` and
/// check its table against this.
public enum Animation: String, CaseIterable {
    case idle = "player_idle"
    case dribbleIdle = "player_dribble_idle"
    case walk = "player_walk"
    case dribbleWalk = "player_dribble_walk"
    case run = "player_run"
    case dribbleRun = "player_dribble_run"
    case pivot = "player_pivot"
    case jumpSquat = "player_jump_squat"
    case air = "player_air"
    case airBall = "player_air_ball"
    case doubleJump = "player_dbl_jump"
    case land = "player_land"
    case wallLand = "player_wall_land"
    case wallLandBall = "player_wall_land_ball"
    case shoot = "player_shoot"
    case shootAir = "player_shoot_air"
    case throwForward = "player_throw_forward"
    case catchGround = "player_catch"
    case catchAir = "player_catch_air"
    case skid = "player_skid"
    case skidBall = "player_skid_ball"
    case taunt = "player_taunt"
    case crouch = "player_crouch"
    case crouchWalk = "player_crouch_walk"
    case slide = "player_slide"
    case esperSlash = "player_esperslash"
    case snatch = "player_snatch"
    case snatchAir = "player_snatch_air"
    case ledge = "player_ledge"
    case dunk = "player_dunk"
    case gunShoot = "player_gun_shoot"
    case gunShootAir = "player_gun_shoot_air"
    case gunRun = "player_gun_run"
    case gunRunShoot = "player_gun_run_shoot"
    case hurt = "player_hurt"

    public var frameCount: Int {
        switch self {
        case .idle, .dribbleIdle, .crouch, .crouchWalk, .snatch, .snatchAir, .gunShoot, .gunShootAir: 10
        case .hurt: 4
        case .walk, .dribbleWalk, .run, .dribbleRun, .slide, .gunRun, .gunRunShoot: 8
        case .pivot, .air, .airBall, .catchGround, .catchAir, .skid, .skidBall: 3
        case .jumpSquat: 4
        case .doubleJump, .wallLand, .wallLandBall, .esperSlash, .dunk: 6
        case .land: 9
        case .shoot: 10
        case .shootAir, .taunt: 11
        case .throwForward: 8
        case .ledge: 5
        }
    }

    /// Whether the sheet draws the ball in hand. Only these are searched for it; on the
    /// rest every white pixel is energy. The importer's `BALL_SHEETS` has to agree.
    public var holdsBall: Bool {
        switch self {
        case .dribbleIdle, .dribbleWalk, .dribbleRun, .airBall, .wallLandBall, .shoot, .shootAir, .throwForward,
             .catchGround, .catchAir, .skidBall, .taunt: true
        default: false
        }
    }

    /// Pixels from the sprite's bottom edge up to the feet.
    public var feetFromBottom: Double {
        pixelSize == 64 ? 16 : 8
    }

    public var pixelSize: Double {
        self == .throwForward || self == .esperSlash ? 64 : 48
    }
}

extension Animation {
    /// The dunk, frame by frame from the throw stance it starts in: each entry a frame and
    /// how many sim frames it holds; the last holds through the hang. The ball leaves the
    /// hand at the slam, the third dunk frame, which starts at the dunk's release frame.
    public static let dunkSequence: [(frame: AnimationFrame, frames: Int)] = [
        (AnimationFrame(.throwForward, 3), 8),
        (AnimationFrame(.dunk, 0), 6),
        (AnimationFrame(.dunk, 1), 6),
        (AnimationFrame(.dunk, 2), 10),
        (AnimationFrame(.dunk, 3), 10),
        (AnimationFrame(.dunk, 4), 10),
        (AnimationFrame(.dunk, 5), 1),
    ]

    /// Which entry of the dunk sequence shows `frames` in: its index and its frame.
    public static func dunkEntry(at frames: Int) -> (index: Int, frame: AnimationFrame) {
        var left = frames
        for (index, entry) in dunkSequence.enumerated() {
            if left < entry.frames || index == dunkSequence.count - 1 { return (index, entry.frame) }
            left -= entry.frames
        }
        return (dunkSequence.count - 1, dunkSequence[dunkSequence.count - 1].frame)
    }

    /// The sim frame the dunk sequence's entry starts on.
    public static func dunkStart(of index: Int) -> Int {
        dunkSequence.prefix(index).reduce(0) { $0 + $1.frames }
    }
}

public struct AnimationFrame: Equatable {
    public var animation: Animation
    public var frame: Int

    public init(_ animation: Animation, _ frame: Int) {
        self.animation = animation
        self.frame = min(max(frame, 0), animation.frameCount - 1)
    }
}

extension Player {
    /// Which sprite and frame shows this player right now. Nothing here feeds back into
    /// the sim, so the drawing can never change the game.
    public var animationFrame: AnimationFrame {
        let t = stateTimer
        if hitStun > 0, state == .air || state == .idle || state == .land || state == .walk {
            // Stunned: the hurt sheet, its frames in order and the last held.
            return AnimationFrame(.hurt, (BallRules.hitStunFrames - hitStun) * 15 / 60)
        }
        if boltPose > 0, state != .webSwing, state != .webPull, state != .webbed {
            // Zeus Juice's bolt: the throw from its set pose through the release.
            return AnimationFrame(.throwForward, 3 + (ZeusRules.boltPoseFrames - boltPose) * 15 / 60)
        }
        if webLinePose > 0, state != .webSwing, state != .webPull, state != .webbed {
            return AnimationFrame(.throwForward, 4)
        }
        switch state {
        case .idle:
            if previousState == .run || previousState == .dash || previousState == .slide, t < 15 {
                return AnimationFrame(hasBall ? .skidBall : .skid, t / 5)
            }
            if previousState == .land, t + spec.landingLagFrames < 22 {
                return AnimationFrame(.land, (t + spec.landingLagFrames) * 24 / 60)
            }
            return AnimationFrame(holding ? .dribbleIdle : .idle, (t * 12 / 60) % 10)
        case .walk:
            return AnimationFrame(holding ? .dribbleWalk : .walk, Int(animationPhase) % 8)
        case .dash, .run:
            if gunRunTimer > 0 { return AnimationFrame(.gunRunShoot, (PulseRules.runShotFrames - gunRunTimer) * 15 / 60) }
            return AnimationFrame(holding ? .dribbleRun : .run, Int(animationPhase) % 8)
        case .crouch:
            return AnimationFrame(.crouch, (t * 15 / 60) % 10)
        case .crouchWalk:
            return AnimationFrame(.crouchWalk, Int(animationPhase) % 10)
        case .slide:
            return AnimationFrame(.slide, t * 24 / 60)
        case .pivot:
            return AnimationFrame(.pivot, t * 12 / 60)
        case .jumpSquat:
            return AnimationFrame(.jumpSquat, t)
        case .air:
            if doubleJumpTimer > 0 {
                return AnimationFrame(.doubleJump, (30 - doubleJumpTimer) * 12 / 60)
            }
            let phase = velocity.y > 0.3 ? 0 : (abs(velocity.y) <= 0.3 ? 1 : 2)
            return AnimationFrame(hasBall ? .airBall : .air, phase)
        case .wallLand:
            return AnimationFrame(hasBall ? .wallLandBall : .wallLand, t * 12 / 60)
        case .land:
            return AnimationFrame(.land, t * 24 / 60)
        case .shootStance:
            // The ground sheet has one more windup frame before the set pose.
            return grounded ? AnimationFrame(.shoot, min(t * 12 / 60, 4)) : AnimationFrame(.shootAir, min(t * 12 / 60, 3))
        case .shooting:
            // Both sheets smear the release on frame 6, where the ball leaves.
            return grounded ? AnimationFrame(.shoot, 4 + t * 24 / 60) : AnimationFrame(.shootAir, 3 + t * 36 / 60)
        case .throwStance:
            // Frame 3 is the set pose with the ring on the ball; 4 is the release smear.
            return AnimationFrame(.throwForward, min(t * BallRules.throwSheetFramesPerSecond / 60, 3))
        case .throwing:
            return AnimationFrame(.throwForward, 3 + t * BallRules.throwSheetFramesPerSecond / 60)
        case .dunking:
            return Animation.dunkEntry(at: t).frame
        case .catching:
            return AnimationFrame(grounded ? .catchGround : .catchAir, t * 12 / 60)
        case .slashing:
            return AnimationFrame(.esperSlash, t * SlashRules.sheetFramesPerSecond / 60)
        case .rolling:
            // The double jump's somersault, run through in the roll's frames.
            return AnimationFrame(.doubleJump, t * SlashRules.sheetFramesPerSecond / 60)
        case .snatching, .walling:
            return AnimationFrame(grounded ? .snatch : .snatchAir, SnatchRules.sheetFrame(at: t))
        case .ledgeHang:
            return AnimationFrame(.ledge, (t - 1) * 12 / 60)
        case .ledgeClimb:
            return AnimationFrame(.ledge, 2 + (t - 1) * 3 / LedgeRules.climbFrames)
        case .taunt:
            return AnimationFrame(.taunt, t * 15 / 60)
        case .webSwing, .webPull:
            return AnimationFrame(hasBall ? .airBall : .air, 0)
        case .webbed:
            return AnimationFrame(hasBall ? .airBall : .air, 2)
        case .flying:
            return AnimationFrame(hasBall ? .airBall : .air, 1)
        case .gunShoot:
            return AnimationFrame(grounded ? .gunShoot : .gunShootAir, t * 15 / 60)
        }
    }
}
