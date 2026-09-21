import Foundation

/// The player's sprites, as the importer names them. Frame counts and rates come from the
/// GMS2 sprites; run `Tools/import_sprites.py` and check its table against this.
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

    public var frameCount: Int {
        switch self {
        case .idle, .dribbleIdle: 10
        case .walk, .dribbleWalk, .run, .dribbleRun: 8
        case .pivot, .air, .airBall, .catchGround, .catchAir, .skid, .skidBall: 3
        case .jumpSquat: 4
        case .doubleJump, .wallLand, .wallLandBall: 6
        case .land: 9
        case .shoot: 10
        case .shootAir, .taunt: 11
        case .throwForward: 8
        }
    }

    /// Pixels from the sprite's bottom edge up to the feet.
    public var feetFromBottom: Double {
        self == .throwForward ? 16 : 8
    }

    public var pixelSize: Double {
        self == .throwForward ? 64 : 48
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
        switch state {
        case .idle:
            if previousState == .run || previousState == .dash, t < 15 {
                return AnimationFrame(hasBall ? .skidBall : .skid, t / 5)
            }
            if previousState == .land, t + spec.landingLagFrames < 22 {
                return AnimationFrame(.land, (t + spec.landingLagFrames) * 24 / 60)
            }
            return AnimationFrame(hasBall ? .dribbleIdle : .idle, (t * 12 / 60) % 10)
        case .walk:
            return AnimationFrame(hasBall ? .dribbleWalk : .walk, Int(animationPhase) % 8)
        case .dash, .run:
            return AnimationFrame(hasBall ? .dribbleRun : .run, Int(animationPhase) % 8)
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
            return AnimationFrame(grounded ? .shoot : .shootAir, min(t * 12 / 60, 3))
        case .shooting:
            return AnimationFrame(grounded ? .shoot : .shootAir, 4 + t * 24 / 60)
        case .throwStance:
            return AnimationFrame(.throwForward, min(t * 12 / 60, 4))
        case .throwing:
            return AnimationFrame(.throwForward, 5 + t * 12 / 60)
        case .dunking:
            return AnimationFrame(.throwForward, 5)
        case .catching:
            return AnimationFrame(grounded ? .catchGround : .catchAir, t * 12 / 60)
        case .swatting:
            return AnimationFrame(.doubleJump, t * 12 / 60)
        case .taunt:
            return AnimationFrame(.taunt, t * 15 / 60)
        }
    }
}
