import UIKit

/// The Mac's window, centered on its display at every launch. macOS restoring the window moves it onto
/// the display with the active menu bar, and that move crashed the launch inside AppKit; so restoring is
/// off, and the window opens at its saved frame, rewritten first to sit centered.
enum MacWindowPlacement {
    /// Where macOS keeps the window's frame: "x y width height", then the area of the display it was on.
    static let savedFrameKey = "NSWindow Frame MainSceneWindow"

    static func centerSavedWindow() {
        #if os(iOS)
        guard ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp else { return }
        let defaults = UserDefaults.standard
        // Xcode's "Launch app without state restoration", always.
        defaults.register(defaults: ["ApplePersistenceIgnoreState": true])
        guard let saved = defaults.string(forKey: savedFrameKey) else { return }
        let numbers = saved.split(separator: " ").compactMap { Double($0) }
        let displays = displayAreas()
        guard numbers.count >= 8, numbers[2] > 0, numbers[3] > 0, !displays.isEmpty else {
            // Unreadable: macOS opens the window afresh.
            defaults.removeObject(forKey: savedFrameKey)
            return
        }
        let window = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        let savedDisplay = CGRect(x: numbers[4], y: numbers[5], width: numbers[6], height: numbers[7])
        // The display it was on; else the one it's most over; else the menu bar's.
        let display = displays.first { $0 == savedDisplay }
            ?? displays.max { overlapArea($0, window) < overlapArea($1, window) }
            ?? displays[0]
        // Shrunk to fit, its shape kept, where it's bigger than the display.
        let fit = min(1, display.width / window.width, display.height / window.height)
        let width = (window.width * fit).rounded(.down), height = (window.height * fit).rounded(.down)
        let x = (display.midX - width / 2).rounded(.down), y = (display.midY - height / 2).rounded(.down)
        let fields = [x, y, width, height, display.minX, display.minY, display.width, display.height]
        defaults.set(fields.map { String(Int($0)) }.joined(separator: " ") + " ", forKey: savedFrameKey)
        #endif
    }

    /// Each display's area clear of the menu bar and Dock (AppKit's `NSScreen.visibleFrame`), the menu bar's display first.
    private static func displayAreas() -> [CGRect] {
        guard let screens = NSClassFromString("NSScreen")?.value(forKey: "screens") as? [NSObject] else { return [] }
        return screens.compactMap { ($0.value(forKey: "visibleFrame") as? NSValue)?.cgRectValue }
    }

    private static func overlapArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let overlap = first.intersection(second)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }
}
