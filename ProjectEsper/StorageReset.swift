import Foundation

/// Everything the game keeps, wiped once on the first launch of a build whose saved data has a
/// new shape: an old shape never reaches code that expects the new one. Bump `version` when it
/// changes; a tester's build otherwise reads what the last one left.
enum StorageReset {
    static let version = "0.2-1"
    private static let key = "esper.storageVersion"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: key) != version else { return }
        if let domain = Bundle.main.bundleIdentifier { defaults.removePersistentDomain(forName: domain) }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("StageShots", isDirectory: true))
        defaults.set(version, forKey: key)
    }
}
