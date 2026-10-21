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
    case doubleJumpBall = "player_dbl_jump_ball"
    case land = "player_land"
    case wallLand = "player_wall_land"
    case wallLandBall = "player_wall_land_ball"
    case shoot = "player_shoot"
    case shootAir = "player_shoot_air"
    case throwForward = "player_throw"
    case throwAir = "player_throw_air"
    /// The up throw, on the ground or in the air, out of the throw's hold frame.
    case layup = "player_layup"
    case catchGround = "player_catch"
    case catchAir = "player_catch_air"
    case skid = "player_skid"
    case skidBall = "player_skid_ball"
    case taunt = "player_taunt"
    case crouch = "player_crouch"
    case crouchWalk = "player_crouch_walk"
    case slide = "player_slide"
    case esperSlash = "player_esperslash"
    /// The slash in the air: the same swing, drawn for the air.
    case esperSlashAir = "player_esperslash_air"
    case snatch = "player_snatch"
    case snatchAir = "player_snatch_air"
    /// In FloState, the snatch, on the ground or in the air, drawn in its own sheet.
    case snatchFloState = "player_snatch_flostate"
    /// Shielding's: forward (and back, turned round), up and down.
    case shield = "player_shield"
    /// The Spin Move, the ball held round in it.
    case spinBall = "player_spin_ball"
    /// The spin with nothing in hand: the Shieldflip's, and Gale Ale's double jump without the ball.
    case spin = "player_spin"
    /// Knocked into the air, stunned: one frame, held.
    case stunnedAir = "player_stunned_air"
    /// In FloState on the ground, the slash's step through: both swings, one attack.
    case esperSlashFloState = "player_esperslash_flostate"
    case ledge = "player_ledge"
    case dunk = "player_dunk"
    case gunShoot = "player_gun_shoot"
    case gunShootAir = "player_gun_shoot_air"
    case gunSnipe = "player_gun_snipe"
    case gunRun = "player_gun_run"
    case gunRunShoot = "player_gun_run_shoot"
    case transform = "player_transform"
    /// Super Smoothie's flight: hovering or going back, going forward or up, going down.
    case fly = "player_fly"
    case flyBall = "player_fly_ball"
    /// Z Tea's beam: the body, and its arms drawn over it apart so they turn with the aim.
    case beam = "player_beam"
    case beamArms = "player_beam_arms"
    /// Z Tea's blast: the body, and its arms drawn over it apart so they turn 45 degrees up on the ground.
    case blast = "player_blast_body"
    case blastArms = "player_blast_arms"

    public var frameCount: Int {
        switch self {
        case .idle, .dribbleIdle, .crouch, .crouchWalk, .snatch, .snatchAir, .gunShoot, .gunShootAir, .gunSnipe: 10
        case .transform: 9
        case .beam: 10
        case .beamArms, .stunnedAir: 1
        case .blast, .blastArms: 12
        case .shield: 3
        case .walk, .dribbleWalk, .run, .dribbleRun, .slide, .gunRun, .gunRunShoot: 8
        case .pivot, .air, .airBall, .catchGround, .catchAir, .skid, .skidBall, .fly, .flyBall: 3
        case .jumpSquat, .spinBall, .spin: 4
        case .doubleJump, .doubleJumpBall, .wallLand, .wallLandBall, .esperSlash, .esperSlashAir, .dunk: 6
        case .snatchFloState: 7
        case .esperSlashFloState: 9
        case .land: 9
        case .shoot: 10
        case .shootAir, .taunt: 11
        case .throwForward, .throwAir: 8
        case .layup: 9
        case .ledge: 5
        }
    }

    /// Whether the sheet draws the ball in hand. Only these are searched for it; on the
    /// rest every white pixel is energy. The importer's `BALL_SHEETS` has to agree.
    public var holdsBall: Bool {
        switch self {
        case .dribbleIdle, .dribbleWalk, .dribbleRun, .airBall, .flyBall, .wallLandBall, .shoot, .shootAir, .throwForward,
             .catchGround, .catchAir, .skidBall, .taunt, .layup, .doubleJumpBall, .spinBall: true
        default: false
        }
    }

    /// Pixels from the sprite's bottom edge up to the feet.
    public var feetFromBottom: Double {
        pixelSize == 64 ? 16 : 8
    }

    /// The sheet's cell, its height; and its width, which is the same but on FloState's slash,
    /// wider for its reach.
    public var pixelSize: Double {
        [.throwForward, .throwAir, .esperSlash, .esperSlashAir, .esperSlashFloState, .beam, .beamArms].contains(self) ? 64 : 48
    }
    public var pixelWidth: Double { self == .esperSlashFloState ? 80 : pixelSize }
}

extension Animation {
    /// The dunk, frame by frame from the throw stance it starts in: each entry a frame and
    /// how many sim frames it holds; the last holds through the hang. The ball leaves the
    /// hand at the slam, the third dunk frame, which starts at the dunk's release frame.
    public static let dunkSequence: [(frame: AnimationFrame, frames: Int)] = [
        (AnimationFrame(.throwForward, 3), 8),
        (AnimationFrame(.dunk, 0), 6),
        (AnimationFrame(.dunk, 1), 6),
        (AnimationFrame(.dunk, 2), 8),
        (AnimationFrame(.dunk, 3), 8),
        (AnimationFrame(.dunk, 4), 8),
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
        // Parried: reeling, the whole lockout; on the ground the ledge sheet's last frame, in the
        // air the stunned pose, looked at again every frame so a fall or a landing changes it.
        if parryLocked || clashPushed { return grounded ? AnimationFrame(.ledge, Animation.ledge.frameCount - 1) : AnimationFrame(.stunnedAir, 0) }
        if let blast = blastSheetFrame, Player.blastPoseStates.contains(state) {
            // Z Tea's blast: its own sheet, the arm firing drawn over it apart (`blastArms`).
            return AnimationFrame(.blast, blast)
        }
        if boltPose > 0, state != .webSwing, state != .webPull, state != .webbed {
            // Volta Cola's bolt: the whole throw sheet at 15 a second, ground or air.
            return AnimationFrame(grounded ? .throwForward : .throwAir, (VoltaRules.boltPoseFrames - boltPose) * 15 / 60)
        }
        if summonPose > 0, hasFireball, [.idle, .walk, .air, .land].contains(state) {
            // The fireball gathers in the throw's hold frame.
            return AnimationFrame(grounded ? .throwForward : .throwAir, 3)
        }
        if webLinePose > 0, state != .webSwing, state != .webPull, state != .webbed {
            return AnimationFrame(.throwForward, 4)
        }
        // Stunned in the air: its own pose, till the stun's done or it lands.
        if hitStun > 0, !grounded, state == .air { return AnimationFrame(.stunnedAir, 0) }
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
        case .dash where power == .surfSoda && grounded, .run where power == .surfSoda && grounded:
            // Riding the board: the skid's first frame, still.
            return AnimationFrame(holding ? .skidBall : .skid, 0)
        case .dash, .run:
            // Firing on the run: the shooting sheet, whose legs are the run's frame for frame, on
            // the run's own cycle, so the stride carries on through the shot rather than restarting.
            if gunRunTimer > 0 { return AnimationFrame(.gunRunShoot, Int(animationPhase) % 8) }
            return AnimationFrame(holding ? .dribbleRun : .run, Int(animationPhase) % 8)
        case .crouch:
            // Pulsepistol Punch at level two holds the crouch's first frame on the way into the snipe.
            if power == .pulsepistol, powerLevel >= 2, !holding { return AnimationFrame(.crouch, 0) }
            return AnimationFrame(.crouch, (t * 15 / 60) % 10)
        case .gunSnipe:
            // The aim held on the first frame; a shot plays the sheet through.
            return AnimationFrame(.gunSnipe, snipeFire > 0 ? min(snipeFire * 15 / 60, 9) : 0)
        case .crouchWalk:
            return AnimationFrame(.crouchWalk, Int(animationPhase) % 10)
        case .slide:
            return AnimationFrame(.slide, t * 24 / 60)
        case .pivot:
            // The whole sheet over the turn, however short it is.
            let frames = Animation.pivot.frameCount
            return AnimationFrame(.pivot, min(t * frames / max(spec.pivotFrames, 1), frames - 1))
        case .jumpSquat:
            return AnimationFrame(.jumpSquat, t)
        case .air where surfing:
            return AnimationFrame(holding ? .skidBall : .skid, 0)
        case .air:
            if doubleJumpTimer > 0 {
                // Gale Ale at level two: the Spin Move's spin in place of the flip, at its pace;
                // without the ball, the empty-handed spin.
                if power == .galeAle, powerLevel >= 2 {
                    let sheet: Animation = hasBall ? .spinBall : .spin
                    return AnimationFrame(sheet, ((30 - doubleJumpTimer) * SpinRules.sheetFramesPerSecond / 60) % sheet.frameCount)
                }
                return AnimationFrame(hasBall ? .doubleJumpBall : .doubleJump, (30 - doubleJumpTimer) * 12 / 60)
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
            // Held on the last while the shot's watched.
            return grounded ? AnimationFrame(.shoot, min(4 + t * 24 / 60, Animation.shoot.frameCount - 1))
                : AnimationFrame(.shootAir, min(3 + t * 30 / 60, Animation.shootAir.frameCount - 1))
        case .throwStance:
            // Frame 3 is the set pose with the ring on the ball; 4 is the release smear.
            return AnimationFrame(grounded ? .throwForward : .throwAir, min(t * BallRules.throwSheetFramesPerSecond / 60, 3))
        case .stepback:
            // Out of a shot, the air-with-ball sheet's last frame; out of a throw, the throw sheet's third.
            if stepbackFrom == .shootStance { return AnimationFrame(.airBall, Animation.airBall.frameCount - 1) }
            return AnimationFrame(grounded ? .throwForward : .throwAir, StepbackRules.sheetFrame)
        case .throwing:
            // Straight up, the layup's nine at its own 30 a second, the ball leaving on its frame 5.
            if layingUp { return AnimationFrame(.layup, min(t * BallRules.layupFramesPerSecond / 60, Animation.layup.frameCount - 1)) }
            // Frames 4 to 7 at the windup's 15 a second, the smear on the release; the 15-frame
            // recovery ends with the last shown three sim frames rather than four.
            return AnimationFrame(grounded ? .throwForward : .throwAir, min(4 + t * BallRules.throwSheetFramesPerSecond / 60, 7))
        case .dunking:
            return Animation.dunkEntry(at: t).frame
        case .catching:
            return AnimationFrame(grounded ? .catchGround : .catchAir, t * 12 / 60)
        case .slashing where floSlash:
            return AnimationFrame(.esperSlashFloState, min(t * FloSlashRules.sheetFramesPerSecond / 60, FloSlashRules.sheetFrames - 1))
        case .slashing:
            return AnimationFrame(slashAirborne ? .esperSlashAir : .esperSlash, t * SlashRules.sheetFramesPerSecond / 60)
        case .rolling:
            // The double jump's somersault, run through in the roll's frames.
            return AnimationFrame(.doubleJump, t * SlashRules.sheetFramesPerSecond / 60)
        case .spinning:
            let count = Animation.spinBall.frameCount
            return AnimationFrame(.spinBall, min(t * SpinRules.sheetFramesPerSecond / 60, count * SpinRules.turns - 1) % count)
        case .flipJump, .tumbling:
            // The double jump's somersault backward over the flip, and on round it, the same
            // way at the same pace, through the tumble.
            let count = Animation.doubleJump.frameCount
            let played = (state == .tumbling ? ShieldRules.flipFrames : 0) + t
            let step = state == .flipJump ? min(played * count / max(ShieldRules.flipFrames, 1), count - 1) : played * count / max(ShieldRules.flipFrames, 1) % count
            return AnimationFrame(.doubleJump, count - 1 - step)
        case .snatching, .walling:
            // In FloState, on the ground or in the air, its own sheet at the same timing, its last frame held.
            if inFloState, state == .snatching {
                return AnimationFrame(.snatchFloState, min(SnatchRules.sheetFrame(at: t), Animation.snatchFloState.frameCount - 1))
            }
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
            // Going down more than forward, frame 2; going back, up or not, frame 0; forward or up,
            // frame 1; hovering, frame 0.
            let forward = velocity.x * facing.sign
            let sheetFrame = velocity.y < -FlightSheet.still && -velocity.y > forward ? 2
                : (forward < -FlightSheet.still ? 0 : (forward > FlightSheet.still || velocity.y > FlightSheet.still ? 1 : 0))
            return AnimationFrame(hasBall ? .flyBall : .fly, sheetFrame)
        case .transforming:
            return AnimationFrame(.transform, min(t * TransformRules.sheetFramesPerSecond / 60, Animation.transform.frameCount - 1))
        case .beamCharging:
            // Its first frame, then the second held through the charge, the third as it ends.
            let each = ZRules.blastSheetFrameLength
            return AnimationFrame(.beam, t < each ? 0 : (t < ZRules.chargeFrames - each ? 1 : 2))
        case .beamFiring:
            // Firing, frames 3 to 7 round and round under the arms; then the last two.
            let each = ZRules.blastSheetFrameLength
            if t < beamFiringFrames { return AnimationFrame(.beam, 3 + (t / each) % 5) }
            return AnimationFrame(.beam, min(8 + (t - beamFiringFrames) / each, 9))
        case .suspended:
            // Falling, as it hangs.
            return AnimationFrame(hasBall ? .airBall : .air, 2)
        case .gunShoot:
            return AnimationFrame(grounded ? .gunShoot : .gunShootAir, t * 15 / 60)
        }
    }
}

extension Animation {
    /// The frames of a sheet where the ball in hand is at its lowest, under five art pixels off
    /// the floor and no higher than the frames either side: where a dribble meets the floor.
    public func dribbleBounceFrames() -> Set<Int> {
        let count = frameCount
        let heights = (0..<count).map { BallLandmarks.offset(AnimationFrame(self, $0))?.y }
        var frames = Set<Int>()
        for index in 0..<count {
            guard let height = heights[index], height < 5 else { continue }
            let neighbours = [heights[(index + count - 1) % count], heights[(index + 1) % count]].compactMap { $0 }
            if neighbours.allSatisfy({ height <= $0 }) { frames.insert(index) }
        }
        return frames
    }

    /// The dribble's sheets, whose ball reaches down off a ledge to the floor under it.
    public static let dribbles: [Animation] = [.dribbleIdle, .dribbleWalk, .dribbleRun]
}

/// Super Smoothie's flight sheet: under this a frame, in units, the body counts as still that way.
public enum FlightSheet {
    public static let still = 0.3
}
