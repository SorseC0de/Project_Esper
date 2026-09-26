import EsperSim
import SwiftUI

/// The game and what its scene tells the SwiftUI layer: whether the title is up, whether
/// a screen wants the royal blue ground under it, and what to do when the title's buttons
/// are pressed.
@MainActor
final class FlowState: ObservableObject {
    let scene = GameScene()
    let net = GameCenter()
    @Published var showsTitle = true
    @Published var veiled = false
    /// The UI tuning panel is open.
    @Published var tuningOpen = false
    var startSeries: ((GameMode) -> Void)?

    init() {
        scene.flowState = self
    }
}

/// The title screen, on the royal blue ground with the court just showing through, in the
/// dobo UI pack's pieces: the name; BEST OF 7 and 47 against the computer on royal blue
/// plates, with the VS CPU / VS HUMAN switch under them; MULTIPLAYER on gold, which opens
/// Game Center's matchmaker, with the mode it asks for under it and Game Center's word
/// under that; and the energy colours on a black plate in the upper right corner.
struct TitleOverlay: View {
    @ObservedObject var flow: FlowState
    @ObservedObject var net: GameCenter
    /// This phone's energy colour, kept between launches.
    @AppStorage(EnergyColour.storageKey) private var colour = EnergyColour.orange.rawValue
    /// The mode multiplayer asks for; the host's is played.
    @AppStorage(GameScene.onlineModeKey) private var onlineMode = Int(GameMode.rounds.rawValue)
    /// Offline, whether the computer plays player 2 or a second pad does.
    @AppStorage(GameScene.vsCPUKey) private var vsCPU = true
    @ObservedObject private var tuning = UITuning.shared
    private func scale(_ part: UIPart) -> CGFloat { tuning.scale(.title, part) }

    private var busy: Bool {
        switch net.state {
        case .signingIn, .finding, .connecting, .connected: true
        default: false
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(rgb: EsperPalette.royal.body), Color(rgb: EsperPalette.royal.shadow)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                // The energy colours in the bottom right corner, the UI tuning in the bottom left.
                .overlay(alignment: .bottomTrailing) {
                    colourPicker
                        .padding(.bottom, 20)
                        .padding(.trailing, 24)
                }
                .overlay(alignment: .bottomLeading) {
                    small("UI", picked: flow.tuningOpen) { flow.tuningOpen.toggle() }
                        .padding(.bottom, 20)
                        .padding(.leading, 24)
                }
            VStack(spacing: 22 * scale(.buttons)) {
                Image(uiImage: TitleText.image("PROJECT ESPER", size: 56 * scale(.titles)))
                HStack(spacing: 24 * scale(.buttons)) {
                    plated("BEST OF 7", piece: .buttonBlue, width: 170) {
                        SoundBoard.shared.play(SoundBoard.confirm)
                        flow.startSeries?(.rounds)
                    }
                    plated("47", piece: .buttonBlue, width: 170) {
                        SoundBoard.shared.play(SoundBoard.confirm)
                        flow.startSeries?(.fortySeven)
                    }
                }
                HStack(spacing: 10) {
                    small("VS CPU", picked: vsCPU) {
                        vsCPU = true
                        SoundBoard.shared.play(SoundBoard.navigate)
                    }
                    small("VS HUMAN", picked: !vsCPU) {
                        vsCPU = false
                        SoundBoard.shared.play(SoundBoard.navigate)
                    }
                }
                VStack(spacing: 10) {
                    plated("MULTIPLAYER", piece: .buttonGold, width: 240) {
                        SoundBoard.shared.play(SoundBoard.confirm)
                        net.findMatch()
                    }
                    .opacity(busy ? 0.5 : 1)
                    HStack(spacing: 10) {
                        ForEach(GameMode.allCases, id: \.self) { mode in
                            small(mode == .rounds ? "BEST OF 7" : "47", picked: onlineMode == Int(mode.rawValue)) {
                                onlineMode = Int(mode.rawValue)
                                SoundBoard.shared.play(SoundBoard.navigate)
                            }
                        }
                    }
                    if let caption = net.state.caption {
                        Text(caption)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { net.signIn() }
    }

    /// A lettered button on one of the pack's plates, at the title's tuned sizes.
    private func plated(_ text: String, piece: UIPiece, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(uiImage: TitleText.image(text, size: 26 * scale(.text)))
                .frame(width: width * scale(.buttons), height: 54 * scale(.buttons))
                .background(piece.image)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    /// A small switch: gold when it's the one picked, black otherwise.
    private func small(_ text: String, picked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12 * scale(.text), weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 0, x: 1, y: 1)
                .frame(minWidth: 96 * scale(.buttons), minHeight: 30 * scale(.buttons))
                .padding(.horizontal, 8)
                .background((picked ? UIPiece.buttonGold : UIPiece.buttonBlack).image)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    /// The energy colours as a row of circles on a black plate, the picked one ringed.
    private var colourPicker: some View {
        HStack(spacing: 10) {
            ForEach(EnergyColour.allCases, id: \.self) { choice in
                Button {
                    colour = choice.rawValue
                    SoundBoard.shared.play(SoundBoard.navigate)
                    flow.scene.applySavedColours()
                } label: {
                    Circle()
                        .fill(Color(rgb: choice.glow))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(.white, lineWidth: choice.rawValue == colour ? 3 : 0).padding(-4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(UIPiece.buttonBlack.image)
    }
}

extension Color {
    init(rgb: RGB) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}
