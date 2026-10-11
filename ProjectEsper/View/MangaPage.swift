import CoreGraphics
import Foundation

/// The stage preview's page: `Manga_Panels.svg`'s five panels (`_Graphic Assets/Vectors/Stages`),
/// in its units (3750 by 2625, y down), fitted whole to the screen on the page's ground. Four
/// cuts down the right, top to bottom, then the big one on the left: the whole stage under its name.
enum MangaPage {
    static let size = CGSize(width: 3750, height: 2625)

    /// The panels in the order they fill: the right side's top, its middle, its bottom right,
    /// the triangle at the bottom between them, and the big one on the left.
    static let panels: [[CGPoint]] = [
        [CGPoint(x: 3660.7, y: 716.281), CGPoint(x: 3660.7, y: 159.348), CGPoint(x: 2664.41, y: 159.348), CGPoint(x: 2476.23, y: 924.289)],
        [CGPoint(x: 3661.86, y: 752.535), CGPoint(x: 3660.7, y: 1679.53), CGPoint(x: 2332.93, y: 1516.26), CGPoint(x: 2465.55, y: 962.117)],
        [CGPoint(x: 3660.7, y: 1730.82), CGPoint(x: 3660.7, y: 2465.64), CGPoint(x: 3480.04, y: 2465.66), CGPoint(x: 2353.89, y: 1562.51)],
        [CGPoint(x: 2093.07, y: 2465.8), CGPoint(x: 2308.89, y: 1592.08), CGPoint(x: 3398.17, y: 2465.67)],
        [CGPoint(x: 92.039, y: 2465.64), CGPoint(x: 92.039, y: 159.348), CGPoint(x: 2616.81, y: 159.348), CGPoint(x: 2043.89, y: 2465.64)],
    ]
    static let bigPanel = 4

    /// A panel's bounding box, in the page's units: what its cut fills.
    static func bounds(_ panel: Int) -> CGRect {
        let points = panels[panel]
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// The page fitted whole to a screen: its scale, and where its top left lands.
    static func fit(in screen: CGSize) -> (scale: CGFloat, origin: CGPoint) {
        let scale = min(screen.width / size.width, screen.height / size.height)
        return (scale, CGPoint(x: (screen.width - size.width * scale) / 2, y: (screen.height - size.height * scale) / 2))
    }

    /// How much of the screen a panel's cut shows, across and down: the middle of the screen
    /// cut to the panel's shape, as wide or as tall as the screen.
    static func cropShare(_ panel: Int, screen: CGSize) -> CGSize {
        let box = bounds(panel)
        let panelAspect = box.width / max(box.height, 1)
        let screenAspect = screen.width / max(screen.height, 1)
        return panelAspect > screenAspect
            ? CGSize(width: 1, height: screenAspect / panelAspect)
            : CGSize(width: panelAspect / screenAspect, height: 1)
    }

    /// box2 round the page: stretched so its clear inside (its lines' shares of it in from each
    /// side, as measured off `futuristic_box2`) holds every panel with `frameGap` to spare, in the
    /// page's units: the frame never over a panel, nor a panel over it.
    static let frameInside = (left: CGFloat(0.027), right: CGFloat(0.031), top: CGFloat(0.053), bottom: CGFloat(0.047))
    static let frameGap: CGFloat = 20
    static var frame: CGRect {
        let held = panels.indices.map(bounds).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -frameGap, dy: -frameGap)
        let width = held.width / (1 - frameInside.left - frameInside.right)
        let height = held.height / (1 - frameInside.top - frameInside.bottom)
        return CGRect(x: held.minX - frameInside.left * width, y: held.minY - frameInside.top * height, width: width, height: height)
    }

    /// The page's ground and the gutters between the panels: black.
    static let ground: RGB = 0x000000

    // MARK: The timeline, to `stage_preview.wav`'s 6.3 seconds

    /// When each panel comes in, in seconds from the start; how many frames its cut plays
    /// before it freezes (a shot's own count stands over it); and when it's all over.
    static let starts: [Double] = [0.15, 0.95, 1.75, 2.55, 3.45]
    static let liveFrames = 24
    static let bigLiveFrames = 40
    static let length = 6.3
    /// The name over the big panel's middle comes in this long after it, and its cap height as a
    /// share of the screen's height.
    static let titleDelay = 0.25
    static let titleHeight: CGFloat = 0.085
}

/// What the renderer is told of the page each frame: how many panels are up and which one's
/// cut is playing, captured from this frame's render.
struct MangaPageFrame: Equatable {
    var shown: Int
    var live: Int?
}
