// A preview tool: not on the TV, which has no computer to save to.
#if !os(tvOS)
import SwiftUI

/// The FloText exporter, an Xcode preview: any word or number lettered as FLO is (`FloText`, the
/// Dex face in FLO's colours), shown as it'll be saved, and saved as a transparent PNG at a big size
/// into `_Graphic Assets/Pixel Art/Assembled/`, named for its text. A tool, not a part of the game.
#Preview("FloText export") {
    FloTextExporter()
}

struct FloTextExporter: View {
    @State private var text = "FLO"
    /// The lettering's cap height in the saved picture, pixels.
    @State private var capHeight: CGFloat = 256
    @State private var status = ""

    /// The word's picture at `capHeight` pixels, one pixel a point.
    private var picture: UIImage? {
        let word = text.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return nil }
        let drawn = Onomatopoeia.picture(word, face: .englishDex, colours: FloTuning.colours, growsLeft: true, height: capHeight).image
        let size = CGSize(width: (drawn.size.width * drawn.scale).rounded(), height: (drawn.size.height * drawn.scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in drawn.draw(in: CGRect(origin: .zero, size: size)) }
    }

    var body: some View {
        VStack(spacing: 16) {
            TextField("Word or number", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            Stepper("CAP HEIGHT \(Int(capHeight)) px", value: $capHeight, in: 32...1024, step: 32)
                .frame(maxWidth: 320)
            if let picture {
                Image(uiImage: picture).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 600, maxHeight: 200)
                    .padding()
                    .background(Color.black)
                Text("\(Int(picture.size.width)) × \(Int(picture.size.height)) px")
            }
            Button("EXPORT PNG") { export() }
                .buttonStyle(.borderedProminent)
                .disabled(picture == nil)
            Text(status).multilineTextAlignment(.center)
        }
        .font(.system(size: 12, weight: .bold, design: .monospaced))
        .padding()
    }

    /// Saved as `flotext_<text>.png` beside the assembled sheets, over any of the same name.
    private func export() {
        guard let picture, let data = picture.pngData() else { return }
        let folder = PlayerGalleryOutput.folder
        let name = "flotext_" + text.trimmingCharacters(in: .whitespaces)
            .map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("\(name).png")
            try data.write(to: file)
            status = "Saved \(file.lastPathComponent) to \(folder.path)"
        } catch {
            status = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
#endif
