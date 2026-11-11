import EsperSim
import Foundation

/// A run through the Tutorial's lessons (`Stage.tutorial`, `TutorialRules`), offline: the lesson
/// on the wall and its count; once it's done, the belt on, the player held and carried through
/// the doors into the next room, which shows the next lesson, and at its middle everything moved
/// back a room so the run goes on for ever in the same two. Moving, Jumping and Shooting in turn
/// the first time, then the hub, whose back wall's hoops are the lessons: a basket through one
/// loads it as the next room, and a basket through either side's rim turns its page, the rows
/// carried round on their belts. Each lesson done is kept, and once the hub's been reached a run
/// starts there.
final class TutorialRun {
    enum Lesson: String, CaseIterable {
        case moving, jumping, shooting, layups, dunking, hub
        /// Over its hoop in the hub.
        var title: String { ["Moving", "Jumping", "Shooting", "Layups", "Dunking", "Hub"][Self.allCases.firstIndex(of: self)!] }
        /// What its room's laid out as: the hub's hoops, or the rim on the right.
        var layout: TutorialRoomLayout { self == .hub ? .hub : .rim }
    }
    /// The hub's pages, each its title and its hoops' lessons slot by slot; the slots past these
    /// have none yet. The right rim turns to the next, the left to the one before, round.
    static let hubPages: [(title: String, lessons: [Lesson])] = [
        ("The Basics", [.moving, .jumping, .shooting, .layups, .dunking]),
        ("More", []),
    ]
    /// A page turn's length, sim frames: the belts carry the rows a whole lap in it, easing in and
    /// out; on to the next, the top row right and the next left, back to the one before the other way.
    static let pageTurnFrames = 90

    static let stepsWanted = 47
    static let jumpsWanted = 3
    static let doubleJumpsWanted = 3
    static let shotsWanted = 3
    static let layupsWanted = 3
    static let dunksWanted = 3

    // MARK: Kept

    private static let completedKey = "tutorial.completed"
    private static let reachedHubKey = "tutorial.reachedHub"
    static var completed: Set<Lesson> {
        get { Set((UserDefaults.standard.stringArray(forKey: completedKey) ?? []).compactMap(Lesson.init)) }
        set { UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: completedKey) }
    }
    static var reachedHub: Bool {
        get { UserDefaults.standard.bool(forKey: reachedHubKey) }
        set { UserDefaults.standard.set(newValue, forKey: reachedHubKey) }
    }

    // MARK: The doors

    /// A door: shut, opening (sim frames in), open, closing (sim frames in). Its opening's left
    /// empty in the sim once it's open, solid again as it starts to shut.
    enum Door: Equatable { case shut, opening(Int), open, closing(Int) }
    /// The doors' art at this many sim frames a frame; a door opens as the player's carried within
    /// `doorApproach` of its middle, and shuts once they're `doorBehind` past it.
    static let doorStepsPerFrame = 2
    static let doorApproach = 60.0
    static let doorBehind = 24.0
    /// The other side, out of the way till a lesson wants it.
    static let parked = Vec2(x: -300, y: 300)

    static func doorArtFrame(_ door: Door) -> Int {
        switch door {
        case .shut: 0
        case .opening(let frames): min(frames / doorStepsPerFrame, WreckCenterArt.doorOpenFrame)
        case .open: WreckCenterArt.doorOpenFrame
        case .closing(let frames): min(frames / doorStepsPerFrame, WreckCenterArt.doorFrames.count - 1)
        }
    }

    // MARK: The run

    private(set) var lesson: Lesson
    /// The belt carrying the player on, and the lesson the next room has.
    private(set) var carrying = false
    private var next: Lesson?
    private(set) var doors: [Door] = TutorialRules.doorColumns.map { _ in .shut }
    /// The ball owed the player: at the start, and as the belt takes them on.
    private var givesBall = true
    private var laidOut = false
    private var steps = 0, jumps = 0, doubleJumps = 0, shots = 0, layups = 0, dunks = 0
    /// In the hub, the lesson whose hoop was scored through.
    private var hubChoice: Lesson?
    /// The hub's page, and a turn to another under way (the page it goes to, the way: 1 on, -1
    /// back, sim frames in) or asked for by a basket (the way).
    private(set) var page = 0
    private(set) var pageTurn: (to: Int, way: Int, frames: Int)?
    private var pageAsked: Int?

    init() {
        lesson = TutorialRun.reachedHub ? .hub : .moving
    }

    /// The lesson's lines for the wall, its count as it stands.
    var lines: [String] {
        func count(_ done: Int, _ wanted: Int) -> String { "\(min(done, wanted))/\(wanted)" }
        switch lesson {
        case .moving:
            return ["How To Move", "", "Press [left] or [right] to move", "",
                    "Take \(Self.stepsWanted) steps. \(count(steps, Self.stepsWanted))"]
        case .jumping where jumps < Self.jumpsWanted:
            return ["How To Jump", "", "Press [jump] to jump", "", "Jump \(Self.jumpsWanted) times. \(count(jumps, Self.jumpsWanted))"]
        case .jumping:
            return ["How To Jump", "", "Press [jump] again in the air to double jump", "",
                    "Double jump \(Self.doubleJumpsWanted) times. \(count(doubleJumps, Self.doubleJumpsWanted))"]
        case .shooting:
            return ["How To Shoot", "", "Press [shoot] to shoot", "", "Make \(Self.shotsWanted) shots. \(count(shots, Self.shotsWanted))"]
        case .layups:
            return ["How To Layup", "", "Hold [up] and press [throw] to layup", "",
                    "Make \(Self.layupsWanted) layups. \(count(layups, Self.layupsWanted))"]
        case .dunking:
            return ["How To Dunk", "", "Jump at the rim and press [throw] to dunk", "",
                    "Dunk \(Self.dunksWanted) times. \(count(dunks, Self.dunksWanted))"]
        case .hub:
            return ["Shoot a hoop to pick a lesson"]
        }
    }

    /// The hub's page's title, over its lines; and those of the pages a side's rim turns to.
    var pageTitle: String { Self.hubPages[pageTurn?.to ?? page].title }
    var previousPageTitle: String { Self.hubPages[(page + Self.hubPages.count - 1) % Self.hubPages.count].title }
    var nextPageTitle: String { Self.hubPages[(page + 1) % Self.hubPages.count].title }
    /// How far a page turn has carried the rows, art pixels round their lap, back a negative way.
    var hubSlide: Double {
        guard let pageTurn else { return 0 }
        let share = Double(pageTurn.frames) / Double(Self.pageTurnFrames)
        return Double(pageTurn.way) * (share * share * (3 - 2 * share)) * TutorialRules.hubLap
    }
    /// The lesson a hub slot's hoop loads as it's shown: through a turn, the next page's once
    /// it's gone round.
    func hubLesson(slot: Int) -> Lesson? {
        let shown = pageTurn.map { TutorialRules.hubPlace(slot: slot, slide: hubSlide).wrapped ? $0.to : page } ?? page
        let lessons = Self.hubPages[shown].lessons
        return slot < lessons.count ? lessons[slot] : nil
    }

    private var done: Bool {
        switch lesson {
        case .moving: steps >= Self.stepsWanted
        case .jumping: jumps >= Self.jumpsWanted && doubleJumps >= Self.doubleJumpsWanted
        case .shooting: shots >= Self.shotsWanted
        case .layups: layups >= Self.layupsWanted
        case .dunking: dunks >= Self.dunksWanted
        case .hub: hubChoice != nil
        }
    }

    /// Where a lesson done goes: the first time through, on to the next of the first three; once
    /// the hub's been reached, and after Shooting, the hub; from the hub, the lesson picked.
    private var upcoming: Lesson? {
        guard done else { return nil }
        if lesson == .hub { return hubChoice }
        if TutorialRun.reachedHub { return .hub }
        switch lesson {
        case .moving: return .jumping
        case .jumping: return .shooting
        default: return .hub
        }
    }

    /// The player's footfall, walking or running.
    func noteFootfall() {
        guard lesson == .moving, !carrying else { return }
        steps += 1
    }

    /// A frame's events: jumps, double jumps and baskets, the player's, as the lesson counts them.
    func note(_ events: [MatchEvent], local: Int) {
        guard !carrying else { return }
        for event in events {
            switch event {
            case .jumped(let player) where player == local && lesson == .jumping && jumps < Self.jumpsWanted:
                jumps += 1
            case .doubleJumped(let player) where player == local && lesson == .jumping && jumps >= Self.jumpsWanted:
                doubleJumps += 1
            case .scored(let player, let hoop, _, _, let floater, let dunk) where player == local:
                switch lesson {
                case .shooting where hoop == TutorialRules.sideHoop(room: 0) && !floater && !dunk: shots += 1
                case .layups where hoop == TutorialRules.sideHoop(room: 0) && floater: layups += 1
                case .dunking where hoop == TutorialRules.sideHoop(room: 0) && dunk: dunks += 1
                case .hub where pageTurn == nil:
                    if hoop == TutorialRules.sideHoop(room: 0) {
                        pageAsked = 1
                    } else if hoop == TutorialRules.leftHoop(room: 0) {
                        pageAsked = -1
                    } else if let slot = TutorialRules.hubSlot(of: hoop), hoop == TutorialRules.hubHoop(slot: slot, room: 0), let lesson = hubLesson(slot: slot) {
                        hubChoice = lesson
                    }
                default: break
                }
            default: break
            }
        }
    }

    /// A sim frame of the run, before it's stepped (`mutate` changes the match): the other side
    /// kept parked; the first frame, the room laid out; a lesson done, the belt started and the
    /// next room laid out; the ball into the player's hands when it's owed; the doors; and carried
    /// to the next room's middle, everything moved back a room. The player's input, or none while
    /// the belt has them.
    func step(match: Match, local: Int, input: PlayerInput, mutate: ((inout Match) -> Void) -> Void) -> PlayerInput {
        let other = 1 - local
        mutate { match in
            guard match.players.indices.contains(other) else { return }
            match.players[other].position = TutorialRun.parked
            match.players[other].velocity = .zero
            match.players[other].frozen = 2
        }
        if !laidOut {
            laidOut = true
            let layout = lesson.layout
            mutate { match in
                match.layTutorialRoom(0, as: layout)
                match.layTutorialRoom(1, as: .empty)
            }
        }
        if !carrying, let upcoming {
            if lesson != .hub { TutorialRun.completed.insert(lesson) }
            carrying = true
            next = upcoming
            givesBall = true
            mutate { match in
                match.stage.conveyors[0].running = true
                match.layTutorialRoom(1, as: upcoming.layout)
            }
        }
        // The ball into the player's hands once play's begun, from wherever it is.
        if givesBall, match.countdown == 0 {
            if match.ball.holder == local {
                givesBall = false
            } else if match.ball.holder == nil {
                mutate { $0.giveBall(to: local) }
            }
        }
        let x = match.players.indices.contains(local) ? match.players[local].position.x : 0
        stepDoors(x: x, mutate: mutate)
        if lesson == .hub, !carrying, let way = pageAsked {
            pageAsked = nil
            pageTurn = ((page + way + Self.hubPages.count) % Self.hubPages.count, way, 0)
        }
        // A page turning: the rows carried round, the player held till it's done.
        if let turn = pageTurn {
            let frames = turn.frames + 1
            pageTurn = frames >= Self.pageTurnFrames ? nil : (turn.to, turn.way, frames)
            if pageTurn == nil { page = turn.to }
            let slide = hubSlide
            mutate { $0.layTutorialRoom(0, as: .hub, slide: slide) }
            return .idle
        }
        guard carrying, let next else { return input }
        guard x >= TutorialRules.roomMiddle(1) else { return .idle }
        // Arrived: back a room, the new lesson's room the first now, the second cleared.
        let width = TutorialRules.roomWidth()
        let doorBehind = doors[1]
        mutate { match in
            if match.players.indices.contains(local) { match.players[local].position.x -= width }
            if match.ball.holder == nil { match.ball.position.x -= width }
            match.stage.conveyors[0].running = false
            match.layTutorialRoom(0, as: next.layout)
            match.layTutorialRoom(1, as: .empty)
            match.setTutorialDoor(0, open: doorBehind == .open)
            match.setTutorialDoor(1, open: false)
        }
        doors[0] = doorBehind
        doors[1] = .shut
        carrying = false
        self.next = nil
        lesson = next
        steps = 0; jumps = 0; doubleJumps = 0; shots = 0; layups = 0; dunks = 0
        hubChoice = nil
        pageAsked = nil
        if lesson == .hub { TutorialRun.reachedHub = true }
        return input
    }

    private func stepDoors(x: Double, mutate: ((inout Match) -> Void) -> Void) {
        for index in doors.indices {
            let middle = TutorialRules.doorMiddle(index)
            switch doors[index] {
            case .shut:
                if carrying, x > middle - Self.doorApproach, x < middle { doors[index] = .opening(0) }
            case .opening(let frames):
                if frames / Self.doorStepsPerFrame >= WreckCenterArt.doorOpenFrame {
                    doors[index] = .open
                    mutate { $0.setTutorialDoor(index, open: true) }
                } else {
                    doors[index] = .opening(frames + 1)
                }
            case .open:
                if x > middle + Self.doorBehind {
                    doors[index] = .closing(WreckCenterArt.doorOpenFrame * Self.doorStepsPerFrame)
                    mutate { $0.setTutorialDoor(index, open: false) }
                }
            case .closing(let frames):
                doors[index] = frames / Self.doorStepsPerFrame >= WreckCenterArt.doorFrames.count - 1 ? .shut : .closing(frames + 1)
            }
        }
    }

    /// The hub's hoops laid again where the spacing has them now (HUB COLUMNS, HUB ROWS), in each
    /// room they're up in.
    func relayHub(match: Match, mutate: ((inout Match) -> Void) -> Void) {
        for room in 0..<TutorialRules.rooms where match.stage.hoops.indices.contains(TutorialRules.hubHoop(slot: 0, room: room))
            && match.stage.hoops[TutorialRules.hubHoop(slot: 0, room: room)].position != HighwayRules.parked {
            let slide = room == 0 ? hubSlide : 0
            mutate { $0.layTutorialRoom(room, as: .hub, slide: slide) }
        }
    }

    /// The camera across, units: on the first room, or carried on with the player toward the next.
    func cameraX(match: Match, local: Int) -> Double {
        let here = TutorialRules.roomMiddle(0)
        guard carrying, match.players.indices.contains(local) else { return here }
        return min(max(match.players[local].position.x, here), TutorialRules.roomMiddle(1))
    }
}
