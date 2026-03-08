import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("usage: generate_dmg_background.swift <output-path>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let size = NSSize(width: 800, height: 500)
let image = NSImage(size: size)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("failed to create graphics context\n", stderr)
    exit(1)
}

let backgroundRect = CGRect(origin: .zero, size: size)
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.16, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.11, green: 0.15, blue: 0.30, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.42, alpha: 1.0).cgColor,
    ] as CFArray,
    locations: [0.0, 0.48, 1.0]
)!

context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size.height),
    end: CGPoint(x: size.width, y: 0),
    options: []
)

context.saveGState()
context.setFillColor(NSColor(calibratedRed: 0.38, green: 0.61, blue: 1.0, alpha: 0.10).cgColor)
context.fillEllipse(in: CGRect(x: 40, y: 280, width: 260, height: 260))
context.setFillColor(NSColor(calibratedRed: 0.67, green: 0.46, blue: 1.0, alpha: 0.09).cgColor)
context.fillEllipse(in: CGRect(x: 470, y: 120, width: 230, height: 230))
context.restoreGState()

func strokePath(_ points: [CGPoint], color: NSColor, width: CGFloat) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: first)
    for point in points.dropFirst() {
        path.line(to: point)
    }
    path.lineWidth = width
    color.setStroke()
    path.stroke()
}

strokePath(
    [
        CGPoint(x: 48, y: 470),
        CGPoint(x: 180, y: 470),
        CGPoint(x: 235, y: 450),
        CGPoint(x: 380, y: 450),
        CGPoint(x: 450, y: 425),
        CGPoint(x: 620, y: 425),
        CGPoint(x: 740, y: 455),
    ],
    color: NSColor.white.withAlphaComponent(0.13),
    width: 2.0
)

strokePath(
    [
        CGPoint(x: 56, y: 185),
        CGPoint(x: 140, y: 185),
        CGPoint(x: 205, y: 160),
        CGPoint(x: 360, y: 160),
        CGPoint(x: 455, y: 205),
        CGPoint(x: 600, y: 205),
        CGPoint(x: 730, y: 175),
    ],
    color: NSColor(calibratedRed: 0.56, green: 0.80, blue: 1.0, alpha: 0.16),
    width: 2.4
)

let title = NSAttributedString(
    string: "Drag iData to Applications",
    attributes: [
        .font: NSFont.systemFont(ofSize: 31, weight: .bold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.95),
    ]
)

let subtitle = NSAttributedString(
    string: "Native macOS shell for large-table workflows with VisiData",
    attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.72),
    ]
)

title.draw(at: CGPoint(x: 48, y: 82))
subtitle.draw(at: CGPoint(x: 50, y: 52))

let footer = NSAttributedString(
    string: "Open the app from /Applications. Sparkle handles future updates in-place.",
    attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.50),
    ]
)
footer.draw(at: CGPoint(x: 50, y: 54))

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to encode PNG\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL)
