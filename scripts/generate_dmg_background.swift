import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("usage: generate_dmg_background.swift <output-path>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let size = NSSize(width: 960, height: 600)
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
context.fillEllipse(in: CGRect(x: 54, y: 340, width: 320, height: 320))
context.setFillColor(NSColor(calibratedRed: 0.67, green: 0.46, blue: 1.0, alpha: 0.09).cgColor)
context.fillEllipse(in: CGRect(x: 550, y: 140, width: 280, height: 280))
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
        CGPoint(x: 240, y: 470),
        CGPoint(x: 310, y: 510),
        CGPoint(x: 470, y: 510),
        CGPoint(x: 530, y: 475),
        CGPoint(x: 720, y: 475),
        CGPoint(x: 820, y: 520),
    ],
    color: NSColor.white.withAlphaComponent(0.13),
    width: 2.0
)

strokePath(
    [
        CGPoint(x: 56, y: 185),
        CGPoint(x: 180, y: 185),
        CGPoint(x: 250, y: 150),
        CGPoint(x: 440, y: 150),
        CGPoint(x: 540, y: 205),
        CGPoint(x: 700, y: 205),
        CGPoint(x: 820, y: 165),
    ],
    color: NSColor(calibratedRed: 0.56, green: 0.80, blue: 1.0, alpha: 0.16),
    width: 2.4
)

let title = NSAttributedString(
    string: "Drag iData to Applications",
    attributes: [
        .font: NSFont.systemFont(ofSize: 36, weight: .bold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.95),
    ]
)

let subtitle = NSAttributedString(
    string: "Native macOS shell for large-table workflows with VisiData",
    attributes: [
        .font: NSFont.systemFont(ofSize: 17, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.72),
    ]
)

title.draw(at: CGPoint(x: 58, y: 78))
subtitle.draw(at: CGPoint(x: 60, y: 48))

let footer = NSAttributedString(
    string: "Open the app from /Applications. Sparkle handles future updates in-place.",
    attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.50),
    ]
)
footer.draw(at: CGPoint(x: 60, y: 22))

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
