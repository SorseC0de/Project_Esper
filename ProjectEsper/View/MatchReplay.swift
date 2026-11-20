import EsperSim
import Foundation
#if !os(tvOS)
import UIKit
import UniformTypeIdentifiers
#endif

/// A whole match as it was played, offline or online, saved from the win screen: how the series
/// began, each side's look, every session's recording, and the picks made between points. It plays
/// back only on the build it was made on (`protocolVersion` and `build` say which).
struct MatchReplayFile: Codable {
    static let fileExtension = "variaballreplay"

    var protocolVersion: UInt8
    var build: String
    var date: Date
    var mode: GameMode
    var sides: [PlayerCustomization]
    var start: Start
    /// The series as it began.
    var series: Series
    var sessions: [SessionRecording] = []
    var decisions: [Decision] = []
    /// Online, both players' Game Center names, player one's first; nil offline.
    var names: [String]?
    /// The stage it ended on; nil in a replay saved before this was kept.
    var endStage: StageChoice?

    /// How the match began: a series from its stage select, or the pause's RESTART MATCH on a stage.
    enum Start: Codable {
        case series(seed: UInt32)
        case restart(seed: UInt32, stage: StageChoice)
    }

    /// A pick made on a screen between points, and the series as it left it.
    struct Decision: Codable {
        enum Kind: Codable {
            case drink(choice: Int)
            case stage(StageChoice)
        }
        var kind: Kind
        var seriesAfter: Series
    }

    static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// Where replays are kept: the app's Documents, which the Files app shows on iOS; the TV keeps
    /// no Documents, so its Caches there.
    static var folder: URL {
        #if os(tvOS)
        let place = FileManager.SearchPathDirectory.cachesDirectory
        #else
        let place = FileManager.SearchPathDirectory.documentDirectory
        #endif
        let base = FileManager.default.urls(for: place, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Replays", isDirectory: true)
    }

    func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try (encoder.encode(self) as NSData).compressed(using: .lzfse) as Data
    }

    static func decoded(from data: Data) throws -> MatchReplayFile {
        let plain = try (data as NSData).decompressed(using: .lzfse) as Data
        return try PropertyListDecoder().decode(MatchReplayFile.self, from: plain)
    }

    /// The file's name: when it was played, the stage it ended on, and the mode.
    func fileName(endingOn stage: StageChoice) -> String {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd HHmmss"
        return "\(format.string(from: date)) \(stage.name) \(mode) b\(build).\(MatchReplayFile.fileExtension)"
    }

    /// Every replay in `folder`, oldest first.
    static func all(in folder: URL = MatchReplayFile.folder) -> [(url: URL, file: MatchReplayFile)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url), let file = try? decoded(from: data) else {
                    NSLog("[REPLAY] couldn't read %@", url.lastPathComponent)
                    return nil
                }
                return (url, file)
            }
    }
}

/// A saved replay as VTV lists it: when, who, where and what they looked like, without its recordings.
struct ReplaySummary: Identifiable {
    let url: URL
    let date: Date
    /// Online, both players' names, player one's first.
    let names: [String]?
    let sides: [PlayerCustomization]
    let stage: StageChoice
    var id: URL { url }
    var online: Bool { names != nil }

    init(url: URL, file: MatchReplayFile) {
        self.url = url
        date = file.date
        names = file.names
        sides = file.sides
        let lastPicked = file.decisions.reversed().lazy.compactMap { decision -> StageChoice? in
            if case .stage(let stage) = decision.kind { return stage }
            return nil
        }.first
        var started: StageChoice?
        if case .restart(_, let stage) = file.start { started = stage }
        stage = file.endStage ?? lastPicked ?? started ?? file.series.stage
    }

    /// "BLUE VS GREEN", or online "NAME VS NAME".
    var matchup: String {
        let sideNames = names ?? sides.map { $0.energy.rawValue }
        return sideNames.map { $0.uppercased() }.joined(separator: " VS ")
    }

    /// When it was played: "NOV 20, 3:42 PM".
    var dateLine: String {
        let format = DateFormatter()
        format.dateFormat = "MMM d, h:mm a"
        return format.string(from: date).uppercased()
    }

    /// The whole replay behind a summary, read off the main thread; nil if it can't be read.
    @MainActor func read(_ done: @escaping @MainActor (MatchReplayFile?) -> Void) {
        #if !os(tvOS)
        let folder = ProcessInfo.processInfo.isiOSAppOnMac ? ReplayFolder.granted() : nil
        #else
        let folder: URL? = nil
        #endif
        let url = url
        DispatchQueue.global(qos: .userInitiated).async {
            let opened = folder?.startAccessingSecurityScopedResource() ?? false
            let file = (try? Data(contentsOf: url)).flatMap { try? MatchReplayFile.decoded(from: $0) }
            if opened { folder?.stopAccessingSecurityScopedResource() }
            Task { @MainActor in done(file) }
        }
    }

    /// Every saved replay, newest first, read off the main thread: on the Mac from `_Replays` once it's been granted.
    @MainActor static func load(_ done: @escaping @MainActor ([ReplaySummary]) -> Void) {
        #if !os(tvOS)
        let folder = ProcessInfo.processInfo.isiOSAppOnMac ? ReplayFolder.granted() ?? MatchReplayFile.folder : MatchReplayFile.folder
        #else
        let folder = MatchReplayFile.folder
        #endif
        DispatchQueue.global(qos: .userInitiated).async {
            let opened = folder.startAccessingSecurityScopedResource()
            let summaries = MatchReplayFile.all(in: folder).map { ReplaySummary(url: $0.url, file: $0.file) }.reversed()
            if opened { folder.stopAccessingSecurityScopedResource() }
            let listed = Array(summaries)
            Task { @MainActor in done(listed) }
        }
    }
}

/// The match being played, recorded as it goes: each session closed as the next replaces it, and
/// the picks made between points.
@MainActor
final class MatchRecorder {
    private(set) var file: MatchReplayFile
    /// The session recording now, by its serial.
    var liveSerial: Int?
    private(set) var saved = false

    init(mode: GameMode, sides: [PlayerCustomization], start: MatchReplayFile.Start, series: Series, names: [String]?) {
        file = MatchReplayFile(protocolVersion: NetRules.protocolVersion, build: MatchReplayFile.currentBuild, date: Date(),
                               mode: mode, sides: sides, start: start, series: series, names: names)
    }

    /// The session's recording kept, if it's the one this recorder started.
    func close(_ session: RollbackSession) {
        guard session.serial == liveSerial, let recording = session.recording else { return }
        file.sessions.append(recording)
        liveSerial = nil
    }

    func decided(_ kind: MatchReplayFile.Decision.Kind, series: Series) {
        file.decisions.append(MatchReplayFile.Decision(kind: kind, seriesAfter: series))
    }

    /// The match so far, the live session too, written to `folder`: the replays folder unless given another.
    func save(live session: RollbackSession, endingOn stage: StageChoice, into folder: URL = MatchReplayFile.folder) -> URL? {
        var whole = file
        whole.endStage = stage
        if session.serial == liveSerial, let recording = session.recording { whole.sessions.append(recording) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(whole.fileName(endingOn: stage))
            try whole.encoded().write(to: url, options: .atomic)
            saved = true
            NSLog("[REPLAY] saved %@", url.lastPathComponent)
            return url
        } catch {
            NSLog("[REPLAY] couldn't save: %@", "\(error)")
            return nil
        }
    }
}

/// A replay played back under footage: each session's start and changes laid over the session the
/// game's own flow made in its place, the recorded inputs fed in, and the picks made as they were.
@MainActor
final class MatchReplayPlayer {
    let file: MatchReplayFile
    let name: String
    private var sessionIndex = -1
    private var liveSerial: Int?
    var nextDecision = 0
    /// Frames the current pick screen has been up, so it shows before it's made.
    var pickFrames = 0

    init(file: MatchReplayFile, name: String) {
        self.file = file
        self.name = name
    }

    var recording: SessionRecording? { file.sessions.indices.contains(sessionIndex) ? file.sessions[sessionIndex] : nil }

    /// Past the last recorded frame of the last session.
    func over(frame: Int) -> Bool {
        sessionIndex >= file.sessions.count - 1 && frame >= (recording?.endFrame ?? 0)
    }

    /// Past the end of a session the match left for another (the round reset): time for the next.
    func wantsNextSession(frame: Int) -> Bool {
        sessionIndex >= 0 && sessionIndex < file.sessions.count - 1 && frame >= (recording?.endFrame ?? 0)
    }

    /// The inputs for the session's next frame, the match first put as the recording had it there.
    func inputs(for session: inout RollbackSession) -> [PlayerInput] {
        if liveSerial != session.serial {
            liveSerial = session.serial
            sessionIndex += 1
        }
        guard let recording else { return [.idle, .idle] }
        if let changed = recording.change(at: session.frame) {
            session.mutate { $0 = changed }
        } else if session.frame == recording.start.frame, session.match != recording.start {
            session.mutate { $0 = recording.start }
        }
        return recording.inputs(at: session.frame) ?? [.idle, .idle]
    }

    var pendingDecision: MatchReplayFile.Decision? {
        file.decisions.indices.contains(nextDecision) ? file.decisions[nextDecision] : nil
    }
}

#if !os(tvOS)
/// On the Mac, where the iPad build can only write its own sandbox: the folder saved replays go to,
/// picked once (the picker opens on the project's `_Replays`) and kept as a bookmark, so every save
/// after goes straight there.
@MainActor
enum ReplayFolder {
    static let bookmarkKey = "esper.replayFolderBookmark"

    /// The project's `_Replays`, from this source file's own place in it.
    static var projectReplays: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("_Replays", isDirectory: true)
    }

    /// `use` with the folder open for writing, picking it first if none's been granted; nil if the
    /// pick was cancelled.
    static func withFolder(_ use: @escaping (URL?) -> Void) {
        if let folder = granted() {
            let opened = folder.startAccessingSecurityScopedResource()
            use(folder)
            if opened { folder.stopAccessingSecurityScopedResource() }
            return
        }
        pick { folder in
            guard let folder else { return use(nil) }
            let opened = folder.startAccessingSecurityScopedResource()
            if let bookmark = try? folder.bookmarkData() { UserDefaults.standard.set(bookmark, forKey: bookmarkKey) }
            use(folder)
            if opened { folder.stopAccessingSecurityScopedResource() }
        }
    }

    /// The folder picked before, if its bookmark still leads to it.
    static func granted() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) else { return nil }
        if stale, folder.startAccessingSecurityScopedResource() {
            if let fresh = try? folder.bookmarkData() { UserDefaults.standard.set(fresh, forKey: bookmarkKey) }
            folder.stopAccessingSecurityScopedResource()
        }
        return folder
    }

    private static var picking: Picking?

    private static func pick(_ picked: @escaping (URL?) -> Void) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        guard let top else { return picked(nil) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.directoryURL = projectReplays
        let delegate = Picking { folder in
            picking = nil
            picked(folder)
        }
        picking = delegate
        picker.delegate = delegate
        top.present(picker, animated: true)
    }

    @MainActor private final class Picking: NSObject, UIDocumentPickerDelegate {
        let done: (URL?) -> Void
        init(done: @escaping (URL?) -> Void) { self.done = done }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            done(urls.first)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            done(nil)
        }
    }
}
#endif
