import EsperSim
import SwiftUI

/// The order a side's bottles are shown in on the drink pick.
enum DrinkSort: CaseIterable {
    case aToZ, zToA, biomorphsFirst, boostersFirst

    var label: String {
        switch self {
        case .aToZ: "A–Z"
        case .zToA: "Z–A"
        case .biomorphsFirst: "BIOMORPHS FIRST"
        case .boostersFirst: "BOOSTERS FIRST"
        }
    }

    var next: DrinkSort { DrinkSort.allCases[(DrinkSort.allCases.firstIndex(of: self)! + 1) % DrinkSort.allCases.count] }

    func sorted(_ drinks: [Greateraid]) -> [Greateraid] {
        let byName = drinks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        switch self {
        case .aToZ: return byName
        case .zToA: return byName.reversed()
        case .biomorphsFirst: return byName.filter { $0.kind == .biomorph } + byName.filter { $0.kind == .booster }
        case .boostersFirst: return byName.filter { $0.kind == .booster } + byName.filter { $0.kind == .biomorph }
        }
    }
}

/// The drink pick, in a mode that picks its drink before play (47): after START the figures go
/// off to the corners, and each side has, top to bottom, the raised drink's name and what it does
/// at its second level (both of its sentences), in frame 6 turned on end, its tail up as drawn and
/// its box stretched round the words; its sort; and every bottle, small, in rows like crayons in a
/// box, upright, the front row's leftmost first. A tap pulls a bottle up out
/// of its row (or puts it back, none picked); the bottle on the ball confirms.
struct DrinkPick: View {
    @ObservedObject var flow: FlowState
    let player: Int
    let size: CGSize
    /// Redrawn as the UI tuning panel's DRINKS scales change.
    @ObservedObject private var tuning = UITuning.shared

    /// Bottles to a row, and how the rows stack: each one behind a little higher and half a step over.
    static let perRow = 5
    /// The figures off in the corners: their size, and where, as shares of the screen.
    static let cornerScale: CGFloat = 0.5
    static let cornerSeconds = 0.35
    static func corner(_ player: Int, _ size: CGSize) -> CGPoint {
        CGPoint(x: size.width * (player == 0 ? 0.08 : 0.92), y: size.height * 0.24)
    }
    /// The bottle on the ball in place of START on the customize screen, its height a share of the
    /// screen's, leaning back; and the drink cursor's place on START (the sort's is -1).
    static let startBottleShare: CGFloat = 0.11
    static let startBottleLean: Double = -20
    static let startCursor = -2
    /// The small bottles in the gutter under the figure off in the corner, No Power over Random;
    /// their size against a bottle's, and their feet down the screen, as shares of it.
    static let noPowerCursor = -3
    static let randomCursor = -4
    static let smallBottleScale: CGFloat = 0.6
    static let noPowerFootShare: CGFloat = 0.62
    static let randomFootShare: CGFloat = 0.82
    /// The side's room: across, and the box's top, the sort's line and the bottles' foot, down.
    static let sideRange: (outer: CGFloat, inner: CGFloat) = (0.05, 0.41)
    /// The words' box, a fixed size: its left edge, top and height as shares of the screen; its tail
    /// under it, this share of the box's width.
    static let boxLeftShare: CGFloat = 0.13
    static let boxTopShare: CGFloat = 0.1
    static let boxHeightShare: CGFloat = 0.38
    static let tailShare: CGFloat = 0.3
    static let sortShare: CGFloat = 0.56
    static let bottlesFootShare: CGFloat = 0.95
    static let bottleHeightShare: CGFloat = 0.2
    /// Bottles across a row this share of a bottle's height apart: close, overlapping.
    static let bottleStepShare: CGFloat = 0.3
    static let rowRiseShare: CGFloat = 0.05
    /// The raised bottle: up out of its row this share of the screen, and this much bigger.
    static let raiseShare: CGFloat = 0.06
    static let raisedScale: CGFloat = 1.25
    /// The cursor's bottle outlined, solid, this share of its height thick (the silhouette's pad over its side).
    static let outlineShare: CGFloat = 8.0 / 200
    static let textSize: CGFloat = 11
    static let flavourSize: CGFloat = 9
    static let nameSize: CGFloat = 16
    static let lineColour = Color(rgb: Futuristic.lineRGB)
    static let tealColour = Color(rgb: Futuristic.lineRGB)
    static let litColour = Color(rgb: EsperPalette.gold.light)

    /// The side's room, mirrored for the second side.
    private func across(_ share: CGFloat) -> CGFloat { size.width * (player == 0 ? share : 1 - share) }
    /// The words' box's middle across: the bottles and the sort centred under it.
    private var boxMiddle: CGFloat { (across(DrinkPick.boxLeftShare) + across(DrinkPick.sideRange.inner)) / 2 }
    /// The lettering's size for the screen (DRINKS TEXT on the UI tuning panel), and the bottles' (DRINKS BUTTONS).
    private var textScale: CGFloat { size.height / 430 * UITuning.shared.scale(.drinks, .text) }
    private var bottleScale: CGFloat { UITuning.shared.scale(.drinks, .buttons) }

    var body: some View {
        let ownsCursor = !flow.customizeOnline || player == flow.customizeLocal
        ZStack(alignment: .topLeading) {
            description
            sortButton(lit: ownsCursor && flow.drinkCursors[player] == -1)
            bottles(cursor: ownsCursor ? flow.drinkCursors[player] : nil)
        }
        .frame(width: size.width, height: size.height)
        .opacity(flow.customizeReady[player] ? 0.6 : 1)
        .transition(.opacity)
    }

    // MARK: The words

    private var description: some View {
        let left = min(across(DrinkPick.boxLeftShare), across(DrinkPick.sideRange.inner))
        let right = max(across(DrinkPick.boxLeftShare), across(DrinkPick.sideRange.inner))
        let width = right - left
        let height = size.height * DrinkPick.boxHeightShare
        let drink = flow.shownCustomizations[player].drink
        let random = flow.drinkRandom[player]
        let inset = width * 0.12
        let scale = textScale
        let tailWidth = width * DrinkPick.tailShare
        let tail = DrinkPick.frameTail
        let tailHeight = tailWidth * tail.size.height / max(tail.size.width, 1)
        return VStack(spacing: 0) {
            VStack(spacing: size.height * 0.01) {
                // The name in teal, rule 6, the quote in italics, rule 6, what it does.
                Text(random ? "RANDOM" : drink?.name.uppercased() ?? "NO POWER")
                    .font(.custom(Futuristic.fontName, size: Futuristic.fontSize(DrinkPick.nameSize) * scale))
                    .foregroundStyle(DrinkPick.tealColour)
                rule(width: width - inset * 2)
                Text(random ? " " : drink.map { "\u{201C}\($0.comment)\u{201D}" } ?? " ")
                    .font(.system(size: DrinkPick.flavourSize * scale).italic())
                    .foregroundStyle(DrinkPick.lineColour.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                rule(width: width - inset * 2)
                DrinkPick.blurbText(random ? DrinkPick.randomText : drink.map { $0.blurbs.first + " " + $0.blurbs.second } ?? DrinkPick.noDrinkText,
                                    size: Futuristic.fontSize(DrinkPick.textSize) * scale)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, inset)
            .padding(.vertical, inset * 0.8)
            .frame(width: width, height: height)
            .background {
                Image(uiImage: DrinkPick.frameBox).resizable().interpolation(.high).colorMultiply(DrinkPick.lineColour)
            }
            // The tail under it, small, its line where the box's is.
            Image(uiImage: tail).resizable().interpolation(.high)
                .frame(width: tailWidth, height: tailHeight)
                .colorMultiply(DrinkPick.lineColour)
                .offset(x: width * (DrinkPick.tailLineShare - 0.5) - tailWidth * (DrinkPick.tailLineShare - 0.5))
        }
        .frame(width: width, height: height + tailHeight, alignment: .top)
        .position(x: left + width / 2, y: size.height * DrinkPick.boxTopShare + (height + tailHeight) / 2)
    }

    /// Rule 6 across the box.
    private func rule(width: CGFloat) -> some View {
        Image(uiImage: Futuristic.image("rule6")).resizable().aspectRatio(contentMode: .fit).frame(width: width)
            .colorMultiply(DrinkPick.lineColour)
    }
    static let noDrinkText = "FloState as itself: only its own [Slash] and [Snatch]."
    static let randomText = "A Greateraid drawn at random as you lock in."

    /// A blurb in the menus' face: bracketed words in gold, [Up], [Down], [Left] and [Right] the
    /// fat arrow turned that way, in gold.
    static func blurbText(_ text: String, size: CGFloat) -> Text {
        var made = Text("")
        for (index, piece) in PickScreen.blurbPieces(text).enumerated() {
            if index > 0, piece.spaced { made = made + Text(" ") }
            switch piece.kind {
            case .word(let word, let lit):
                made = made + Text(word).foregroundColor(lit ? litColour : lineColour)
            case .arrow(let turn):
                made = made + Text(Image(uiImage: arrow(turn: turn, side: size)).renderingMode(.template)).foregroundColor(litColour)
            }
        }
        return made.font(.custom(Futuristic.fontName, size: size))
    }

    /// The fat arrow at a size, turned from pointing right.
    private static func arrow(turn: CGFloat, side: CGFloat) -> UIImage {
        let key = "\(turn)|\(side)"
        if let made = arrows[key] { return made }
        let source = UIImage(named: "FatArrow") ?? UIImage()
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            context.cgContext.translateBy(x: side / 2, y: side / 2)
            // UIKit's y runs down: a turn up (anticlockwise) is the other way here.
            context.cgContext.rotate(by: -turn)
            source.withTintColor(.white).draw(in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
        }.withRenderingMode(.alwaysTemplate)
        arrows[key] = image
        return image
    }
    nonisolated(unsafe) private static var arrows: [String: UIImage] = [:]

    /// Frame 6 cut at its box's left edge into its tail and its box, each turned a quarter
    /// anticlockwise: the box stretched to its fixed size, the tail under it, small. The tail's line
    /// across it, as a share from its left once turned.
    private static let frameSplit: CGFloat = 330.0 / 1358.0
    static let tailLineShare: CGFloat = 0.49
    static let frameTail: UIImage = turnedPart(of: Futuristic.image("6"), from: 0, to: frameSplit)
    static let frameBox: UIImage = turnedPart(of: Futuristic.image("6"), from: frameSplit, to: 1)
    private static func turnedPart(of image: UIImage, from: CGFloat, to: CGFloat) -> UIImage {
        guard let cg = image.cgImage else { return UIImage() }
        let left = Int(CGFloat(cg.width) * from), right = Int(CGFloat(cg.width) * to)
        guard right > left, let part = cg.cropping(to: CGRect(x: left, y: 0, width: right - left, height: cg.height)) else { return UIImage() }
        let width = CGFloat(part.width), height = CGFloat(part.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: height, height: width), format: format).image { context in
            // A quarter anticlockwise: the cut's left edge to the bottom.
            context.cgContext.translateBy(x: 0, y: width)
            context.cgContext.rotate(by: -.pi / 2)
            UIImage(cgImage: part).draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    // MARK: The sort

    private func sortButton(lit: Bool) -> some View {
        return Text("SORT: " + flow.drinkSorts[player].label)
            .font(.custom(Futuristic.fontName, size: Futuristic.fontSize(10) * textScale))
            .foregroundStyle(lit ? DrinkPick.litColour : DrinkPick.lineColour)
            .padding(.horizontal, size.height * 0.015)
            .padding(.vertical, size.height * 0.006)
            .overlay(Capsule().stroke(lit ? DrinkPick.litColour : DrinkPick.lineColour, lineWidth: 1.5))
            .fixedSize()
            .contentShape(Rectangle())
            .onTapGesture { flow.cycleDrinkSort(player) }
            .position(x: boxMiddle, y: size.height * DrinkPick.sortShare)
    }

    // MARK: The bottles

    /// A drink's bottle: its own from the catalog, else its kind's.
    static func bottleImage(_ drink: Greateraid) -> UIImage {
        UIImage(named: drink.bottleArt) ?? UIImage(named: drink.kind == .booster ? "Greateraid" : "Greateraid-Gold") ?? UIImage()
    }

    private func bottles(cursor: Int?) -> some View {
        let drinks = flow.sortedDrinks(player)
        let picked = flow.shownCustomizations[player].drink
        let height = size.height * DrinkPick.bottleHeightShare * bottleScale
        let rows = (drinks.count + DrinkPick.perRow - 1) / DrinkPick.perRow
        let step = height * DrinkPick.bottleStepShare
        // The group centred under the words' box: the bottles' middles across the widest row.
        let span = (CGFloat(min(drinks.count, DrinkPick.perRow) - 1) + CGFloat(max(rows - 1, 0)) * 0.5) * step
        let first = boxMiddle - span / 2
        // The small bottles in the gutter under the figure, one over the other.
        let gutter = DrinkPick.corner(player, size).x
        let random = flow.drinkRandom[player]
        let noPower = picked == nil && !random
        return ZStack(alignment: .topLeading) {
            smallBottle(DrinkPick.noPowerImage, lit: cursor == DrinkPick.noPowerCursor, raised: noPower, height: height,
                        at: CGPoint(x: gutter, y: size.height * DrinkPick.noPowerFootShare)) {
                flow.tapNoPower(player)
            }
            smallBottle(DrinkPick.randomImage, lit: cursor == DrinkPick.randomCursor, raised: random, height: height,
                        at: CGPoint(x: gutter, y: size.height * DrinkPick.randomFootShare)) {
                flow.tapRandom(player)
            }
            ForEach(Array(drinks.enumerated()), id: \.element) { index, drink in
                let row = index / DrinkPick.perRow, column = index % DrinkPick.perRow
                let raised = drink == picked
                let image = DrinkPick.bottleImage(drink)
                let aspect = image.size.width / max(image.size.height, 1)
                let x = first + (CGFloat(column) + CGFloat(row) * 0.5) * step
                let foot = size.height * DrinkPick.bottlesFootShare - CGFloat(row) * size.height * DrinkPick.rowRiseShare
                    - (raised ? size.height * DrinkPick.raiseShare : 0)
                ZStack {
                    // The cursor's bottle outlined in solid teal, as the Greateraid's raised one is in white.
                    if cursor == index {
                        Image(uiImage: DrinkPick.silhouette(drink))
                            .resizable()
                            .frame(width: height * aspect + height * DrinkPick.outlineShare * 2, height: height * (1 + DrinkPick.outlineShare * 2))
                            .colorMultiply(DrinkPick.tealColour)
                    }
                    Image(uiImage: image).resizable().frame(width: height * aspect, height: height)
                }
                .scaleEffect(raised ? DrinkPick.raisedScale : 1, anchor: .bottom)
                .contentShape(Rectangle())
                .onTapGesture { flow.tapDrink(player, drink) }
                .position(x: x, y: foot - height / 2)
                // Front rows over back ones, leftmost over the next; a raised bottle over all.
                .zIndex(raised ? 1000 : Double((rows - row) * 100 - column))
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: raised)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// A small bottle, its foot at `at`: outlined under the cursor, raised when it's the pick.
    private func smallBottle(_ image: UIImage, lit: Bool, raised: Bool, height bottle: CGFloat, at foot: CGPoint,
                             tapped: @escaping () -> Void) -> some View {
        let height = bottle * DrinkPick.smallBottleScale
        let aspect = image.size.width / max(image.size.height, 1)
        return ZStack {
            if lit {
                Image(uiImage: DrinkPick.cachedSilhouette(of: image))
                    .resizable()
                    .frame(width: height * aspect + height * DrinkPick.outlineShare * 2, height: height * (1 + DrinkPick.outlineShare * 2))
                    .colorMultiply(DrinkPick.tealColour)
            }
            Image(uiImage: image).resizable().frame(width: height * aspect, height: height)
        }
        .scaleEffect(raised ? DrinkPick.raisedScale : 1, anchor: .bottom)
        .contentShape(Rectangle())
        .onTapGesture(perform: tapped)
        .position(x: foot.x, y: foot.y - (raised ? size.height * DrinkPick.raiseShare : 0) - height / 2)
        .zIndex(raised ? 1000 : 2000)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: raised)
    }

    /// No Power's bottle: the plain one, emptied grey and dim. Random's: the gold one, a question
    /// mark over it. Stand-ins till they're drawn.
    static let noPowerImage: UIImage = {
        // Each pixel to its own grey, at under half its strength; the clear around it left clear.
        guard let source = UIImage(named: "Greateraid")?.cgImage else { return UIImage() }
        let width = source.width, height = source.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return UIImage() }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for pixel in 0..<(width * height) {
            let at = pixel * 4
            let grey = (Int(pixels[at]) * 2126 + Int(pixels[at + 1]) * 7152 + Int(pixels[at + 2]) * 722) / 10000
            for channel in 0..<3 { pixels[at + channel] = UInt8(Double(grey) * DrinkPick.noPowerStrength) }
            pixels[at + 3] = UInt8(Double(pixels[at + 3]) * DrinkPick.noPowerStrength)
        }
        guard let made = context.makeImage() else { return UIImage() }
        return UIImage(cgImage: made)
    }()
    static let noPowerStrength = 0.45
    static let randomImage: UIImage = {
        let source = UIImage(named: "Greateraid-Gold") ?? UIImage(named: "Greateraid") ?? UIImage()
        return UIGraphicsImageRenderer(size: source.size).image { _ in
            source.draw(at: .zero)
            let mark = NSAttributedString(string: "?", attributes: [
                .font: UIFont.systemFont(ofSize: source.size.height * 0.4, weight: .black),
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black,
                .strokeWidth: -4,
            ])
            let markSize = mark.size()
            mark.draw(at: CGPoint(x: (source.size.width - markSize.width) / 2, y: (source.size.height - markSize.height) / 2))
        }
    }()

    /// A bottle's silhouette in white, a little bigger all round, for its outline: copies of it
    /// round a circle, filled white where they drew.
    static func silhouette(_ drink: Greateraid) -> UIImage {
        if let made = silhouettes[drink] { return made }
        let image = silhouette(of: bottleImage(drink))
        silhouettes[drink] = image
        return image
    }
    static func silhouette(of source: UIImage) -> UIImage {
        let side: CGFloat = 200
        let aspect = source.size.width / max(source.size.height, 1)
        let size = CGSize(width: side * aspect, height: side)
        let pad: CGFloat = 8
        let whole = CGSize(width: size.width + pad * 2, height: size.height + pad * 2)
        let image = UIGraphicsImageRenderer(size: whole).image { context in
            for step in 0..<24 {
                let angle = CGFloat(step) / 24 * 2 * .pi
                source.draw(in: CGRect(origin: CGPoint(x: pad + cos(angle) * pad, y: pad + sin(angle) * pad), size: size))
            }
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: whole), blendMode: .sourceIn)
        }
        return image
    }
    nonisolated(unsafe) private static var silhouettes: [Greateraid: UIImage] = [:]
    /// The small bottles' outlines, made once each.
    static func cachedSilhouette(of image: UIImage) -> UIImage {
        let key = ObjectIdentifier(image)
        if let made = imageSilhouettes[key] { return made }
        let made = silhouette(of: image)
        imageSilhouettes[key] = made
        return made
    }
    nonisolated(unsafe) private static var imageSilhouettes: [ObjectIdentifier: UIImage] = [:]
}
