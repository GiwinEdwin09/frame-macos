import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
        (transform as NSAffineTransform).concat()
        let base = NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 216, yRadius: 216)
        NSColor(calibratedRed: 0.075, green: 0.09, blue: 0.10, alpha: 1).setFill()
        base.fill()
        NSColor(calibratedWhite: 0.23, alpha: 1).setStroke()
        base.lineWidth = 5; base.stroke()
        NSColor(calibratedRed: 0.72, green: 0.94, blue: 0.43, alpha: 0.25).setFill()
        NSBezierPath(roundedRect: NSRect(x: 253, y: 282, width: 558, height: 514), xRadius: 72, yRadius: 72).fill()
        NSColor(calibratedRed: 0.72, green: 0.94, blue: 0.43, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 209, y: 228, width: 558, height: 514), xRadius: 72, yRadius: 72).fill()
        NSColor(calibratedRed: 0.075, green: 0.09, blue: 0.10, alpha: 1).setFill()
        let play = NSBezierPath()
        play.move(to: NSPoint(x: 420, y: 354)); play.line(to: NSPoint(x: 420, y: 618)); play.line(to: NSPoint(x: 631, y: 486)); play.close(); play.fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
