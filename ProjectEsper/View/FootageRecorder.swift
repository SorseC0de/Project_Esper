import AVFoundation
import CoreVideo
import IOSurface
import Metal
import QuartzCore

/// One scene's video: every drawn frame copied off the drawable into an H.264 file, a sixtieth
/// of a second apart whatever the draw rate, the sim having stepped once for each. The sound is
/// not recorded: the sounds played are logged by frame and mixed in by `Tools/highlights.py`.
final class FootageRecorder {
    let url: URL
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let frames: AVAssetWriterInputPixelBufferAdaptor
    private let device: MTLDevice
    private let queue = DispatchQueue(label: "FootageRecorder")
    private var finished = false
    private var framesWritten = 0
    private var framesDropped = 0
    /// Frames captured so far, the next frame's number: its time in the video is this over 60.
    private(set) var framesCaptured = 0
    var videoTime: Double { Double(framesCaptured) / 60 }

    init(url: URL, size: CGSize, device: MTLDevice) throws {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let width = Int(size.width), height = Int(size.height)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 30_000_000,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        video.expectsMediaDataInRealTime = true
        frames = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        writer.add(video)
        self.device = device
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "FootageRecorder", code: 1) }
        writer.startSession(atSourceTime: .zero)
    }

    /// The frame on `drawable` copied into the file once `commands` has drawn it: the copy goes
    /// straight onto the pixel buffer's IOSurface through a texture of our own (no texture cache,
    /// whose textures the simulator freed under the drawing's autorelease pool).
    func capture(_ drawable: MTLTexture, with commands: MTLCommandBuffer) {
        guard !finished, let pool = frames.pixelBufferPool else { return }
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess, let pixelBuffer else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        guard drawable.width == width, drawable.height == height, let surface = CVPixelBufferGetIOSurface(pixelBuffer) else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderWrite
        guard let target = device.makeTexture(descriptor: descriptor, iosurface: surface.takeUnretainedValue(), plane: 0),
              let blit = commands.makeBlitCommandEncoder() else { return }
        blit.copy(from: drawable, to: target)
        blit.endEncoding()
        let time = CMTime(value: CMTimeValue(framesCaptured), timescale: 60)
        framesCaptured += 1
        commands.addCompletedHandler { [weak self] _ in
            // The target texture kept alive till the copy's done.
            _ = target
            self?.queue.async { self?.append(pixelBuffer, at: time) }
        }
    }

    private func append(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard !finished, writer.status == .writing else { framesDropped += 1; return }
        // Not ready: waited for, so no frame of the fixed clock goes missing.
        var waited = 0
        while !video.isReadyForMoreMediaData, waited < 200 {
            Thread.sleep(forTimeInterval: 0.005)
            waited += 1
        }
        if video.isReadyForMoreMediaData, frames.append(pixelBuffer, withPresentationTime: time) {
            framesWritten += 1
        } else {
            framesDropped += 1
        }
    }

    /// How it's going, for the scene's log.
    var stats: String {
        queue.sync { "frames \(framesWritten) dropped \(framesDropped) writer \(writer.status.rawValue) \(writer.error.map { "error \($0.localizedDescription)" } ?? "")" }
    }

    /// The file closed; `then` once it's done, with a line on what went in and whether the file's whole.
    func finish(then: @escaping (String, Bool) -> Void) {
        queue.async { [self] in
            guard !finished else { return }
            finished = true
            guard writer.status == .writing else {
                then("\(url.lastPathComponent): writer status \(writer.status.rawValue) \(writer.error.map { "error \($0.localizedDescription)" } ?? "")", false)
                return
            }
            video.markAsFinished()
            writer.finishWriting { [self] in
                let line = "\(url.lastPathComponent): \(framesWritten) frames (\(framesDropped) dropped)"
                    + (writer.error.map { ", error \($0.localizedDescription)" } ?? "")
                then(line, writer.status == .completed && framesWritten > 0)
            }
        }
    }
}
