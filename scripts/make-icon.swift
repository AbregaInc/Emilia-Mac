import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let n = CGFloat(pixels)
        NSColor(red: 1, green: 0.48, blue: 0.26, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: n * 0.06, y: n * 0.06, width: n * 0.88, height: n * 0.88), xRadius: n * 0.2, yRadius: n * 0.2).fill()
        let font = NSFont(name: "Georgia-Bold", size: n * 0.83) ?? .systemFont(ofSize: n * 0.83, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(red: 0.075, green: 0.08, blue: 0.075, alpha: 1)]
        let text = "e" as NSString
        let width = text.size(withAttributes: attributes).width
        text.draw(at: NSPoint(x: (n - width) / 2, y: n * 0.035), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
