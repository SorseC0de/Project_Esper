// Renders an SVG with macOS's own renderer into a PNG of the given size, cropped to what's
// drawn, and prints the crop as "x y width height" in the render's pixels from the top left.
// Used by import_customize.py: swiftc render_svg.swift -o render_svg; render_svg in.svg out.png 2560 1440
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 5, let image = NSImage(contentsOf: URL(fileURLWithPath: arguments[1])),
      let width = Int(arguments[3]), let height = Int(arguments[4]) else {
    FileHandle.standardError.write("usage: render_svg in.svg out.png width height\n".data(using: .utf8)!)
    exit(1)
}
let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                              hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
NSGraphicsContext.restoreGraphicsState()

let pixels = canvas.bitmapData!
var left = width, top = height, right = -1, bottom = -1
for y in 0..<height {
    for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 0 {
        left = min(left, x); right = max(right, x)
        top = min(top, y); bottom = max(bottom, y)
    }
}
guard right >= 0 else {
    FileHandle.standardError.write("nothing drawn in \(arguments[1])\n".data(using: .utf8)!)
    exit(1)
}
let crop = NSRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
let cropped = canvas.cgImage!.cropping(to: crop)!
let output = NSBitmapImageRep(cgImage: cropped)
try! output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
print(left, top, right - left + 1, bottom - top + 1)
