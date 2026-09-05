import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: render_app_icon OUTPUT.png\n".utf8))
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 3,
    hasAlpha: false,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("could not create app icon canvas\n".utf8))
    exit(1)
}
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let canvas = NSRect(origin: .zero, size: size)
NSGradient(colors: [
    NSColor(red: 0.95, green: 0.31, blue: 0.37, alpha: 1),
    NSColor(red: 0.14, green: 0.48, blue: 0.87, alpha: 1)
])!.draw(in: canvas, angle: -35)

let cardRect = NSRect(x: 112, y: 154, width: 800, height: 716)
NSColor.white.withAlphaComponent(0.93).setFill()
NSBezierPath(roundedRect: cardRect, xRadius: 112, yRadius: 112).fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 210, weight: .heavy),
    .foregroundColor: NSColor(red: 0.16, green: 0.32, blue: 0.60, alpha: 1),
    .paragraphStyle: paragraph
]
"中 A".draw(in: NSRect(x: 140, y: 470, width: 744, height: 260), withAttributes: titleAttributes)

let playPath = NSBezierPath()
playPath.move(to: NSPoint(x: 420, y: 270))
playPath.line(to: NSPoint(x: 420, y: 430))
playPath.line(to: NSPoint(x: 620, y: 350))
playPath.close()
NSColor(red: 0.93, green: 0.25, blue: 0.32, alpha: 1).setFill()
playPath.fill()
NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not render app icon\n".utf8))
    exit(1)
}

try pngData.write(to: outputURL, options: .atomic)
