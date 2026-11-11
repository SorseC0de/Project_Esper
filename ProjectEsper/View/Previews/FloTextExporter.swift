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

    private var picture: UIImage? { FloTextExporter.picture(text, capHeight: capHeight) }

    /// The word's picture at `capHeight` pixels, one pixel a point.
    static func picture(_ text: String, capHeight: CGFloat) -> UIImage? {
        let word = text.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return nil }
        // Its pixels as drawn, one a point: no second drawing to soften it.
        return Onomatopoeia.savedPicture(word, face: .englishDex, colours: FloTuning.colours, growsLeft: true, height: capHeight)
            .cgImage.map { UIImage(cgImage: $0) }
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
        let name = FloTextExporter.fileName(text)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("\(name).png")
            try data.write(to: file)
            status = "Saved \(file.lastPathComponent) to \(folder.path)"
        } catch {
            status = "Couldn't save: \(error.localizedDescription)"
        }
    }

    static func fileName(_ text: String) -> String {
        "flotext_" + text.trimmingCharacters(in: .whitespaces).map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
    }

    /// Debug builds launched with `debug.exportFloText` set to a list of words: each saved at
    /// 256 px into the app's temporary folder, `FloText/`, then the setting's cleared.
    static func exportIfRequested() {
        #if DEBUG
        guard let words = UserDefaults.standard.stringArray(forKey: "debug.exportFloText") else { return }
        UserDefaults.standard.removeObject(forKey: "debug.exportFloText")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FloText", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for word in words {
            guard let data = picture(word, capHeight: 256)?.pngData() else { continue }
            try? data.write(to: folder.appendingPathComponent("\(fileName(word)).png"))
        }
        try? "done".write(to: folder.appendingPathComponent("done"), atomically: true, encoding: .utf8)
        #endif
    }
}
#endif
