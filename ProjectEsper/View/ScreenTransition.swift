import SwiftUI

/// A change of screen behind a curtain: the curtain comes down over everything, the screen
/// changes at full cover, the curtain goes up. How it covers is its kind: a fade to a colour, a
/// wipe in from an edge, an iris closing to the middle. A new kind adds a case here and its
/// drawing in `TransitionCurtain`; the timing is the transition's own. The curtain is drawn by
/// modifiers of `cover` only, so it animates.
struct ScreenTransition: Equatable {
    enum Kind: Equatable {
        case fade
        case wipe(from: Edge)
        case iris
    }

    var kind: Kind
    /// Seconds down, and up again.
    var downSeconds = 0.3
    var upSeconds = 0.35
    var colour: Color = .black

    /// The one between the game's screens.
    static let fade = ScreenTransition(kind: .fade)
    static func wipe(from edge: Edge) -> ScreenTransition { ScreenTransition(kind: .wipe(from: edge), downSeconds: 0.35, upSeconds: 0.35) }
    static let iris = ScreenTransition(kind: .iris, downSeconds: 0.4, upSeconds: 0.4)
}

/// The curtain for a transition at `cover`, 0 clear to 1 everything hidden, over the whole screen.
struct TransitionCurtain: View {
    let transition: ScreenTransition
    let cover: Double

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            switch transition.kind {
            case .fade:
                transition.colour.opacity(cover)
            case .wipe(let edge):
                // Slid in from its edge, the whole screen's width or height, by the cover.
                let across = edge == .leading || edge == .trailing
                let sign: CGFloat = edge == .leading || edge == .top ? -1 : 1
                transition.colour
                    .offset(x: across ? sign * size.width * (1 - cover) : 0, y: across ? 0 : sign * size.height * (1 - cover))
            case .iris:
                // A hole in the colour closing on the middle: the hole scaled from past the
                // corners to nothing.
                let reach = hypot(size.width, size.height)
                transition.colour
                    .mask {
                        Rectangle()
                            .overlay(Circle().frame(width: reach, height: reach).scaleEffect(1 - cover).blendMode(.destinationOut))
                            .compositingGroup()
                    }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(cover > 0.01)
    }
}
