import AppKit
import Foundation

guard CommandLine.arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: render_title_card OUTPUT.png HEXCOLOR LABEL\n".utf8))
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let hex = CommandLine.arguments[2].trimmingCharacters(in: CharacterSet(charactersIn: "#"))
let label = CommandLine.arguments[3]

guard hex.count == 6, let rgb = UInt64(hex, radix: 16) else {
    FileHandle.standardError.write(Data("invalid RGB hex color\n".utf8))
    exit(2)
}

let red = CGFloat((rgb >> 16) & 0xFF) / 255
let green = CGFloat((rgb >> 8) & 0xFF) / 255
let blue = CGFloat(rgb & 0xFF) / 255
let canvasSize = NSSize(width: 1280, height: 720)
let image = NSImage(size: canvasSize)

image.lockFocus()
NSColor(red: red, green: green, blue: blue, alpha: 1).setFill()
NSRect(origin: .zero, size: canvasSize).fill()

let panelRect = NSRect(x: 100, y: 230, width: 1080, height: 260)
NSColor.black.withAlphaComponent(0.25).setFill()
NSBezierPath(roundedRect: panelRect, xRadius: 36, yRadius: 36).fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 72, weight: .bold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]
let textRect = NSRect(x: 120, y: 315, width: 1040, height: 100)
label.draw(in: textRect, withAttributes: attributes)
image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not render title card\n".utf8))
    exit(1)
}

try pngData.write(to: outputURL, options: .atomic)
