import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("usage: generate_dmg_background.swift <output-path>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let width: CGFloat = 800
let height: CGFloat = 500
let size = NSSize(width: width, height: height)
let image = NSImage(size: size)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("failed to create graphics context\n", stderr)
    exit(1)
}

// 1. Premium Dark Tech Gradient Background
let colorsSpace = CGColorSpaceCreateDeviceRGB()
let gradientColors = [
    NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.08, alpha: 1.0).cgColor,
    NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.22, alpha: 1.0).cgColor,
    NSColor(calibratedRed: 0.12, green: 0.08, blue: 0.25, alpha: 1.0).cgColor
] as CFArray

let backgroundGradient = CGGradient(
    colorsSpace: colorsSpace,
    colors: gradientColors,
    locations: [0.0, 0.6, 1.0]
)!

context.drawLinearGradient(
    backgroundGradient,
    start: CGPoint(x: 0, y: height),
    end: CGPoint(x: width, y: 0),
    options: []
)

// 2. Subtle Glowing Orbs for "Tech" Feel
context.saveGState()
context.setBlendMode(.screen)
let glowGradient1 = CGGradient(colorsSpace: colorsSpace, colors: [
    NSColor(calibratedRed: 0.2, green: 0.5, blue: 1.0, alpha: 0.15).cgColor,
    NSColor(calibratedRed: 0.2, green: 0.5, blue: 1.0, alpha: 0.0).cgColor
] as CFArray, locations: [0.0, 1.0])!

context.drawRadialGradient(
    glowGradient1,
    startCenter: CGPoint(x: 200, y: 250), startRadius: 0,
    endCenter: CGPoint(x: 200, y: 250), endRadius: 200,
    options: []
)

let glowGradient2 = CGGradient(colorsSpace: colorsSpace, colors: [
    NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.9, alpha: 0.12).cgColor,
    NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.9, alpha: 0.0).cgColor
] as CFArray, locations: [0.0, 1.0])!

context.drawRadialGradient(
    glowGradient2,
    startCenter: CGPoint(x: 600, y: 250), startRadius: 0,
    endCenter: CGPoint(x: 600, y: 250), endRadius: 220,
    options: []
)
context.restoreGState()

// 3. Elegant Arrow from App Location (~200,250) to Applications Location (~600,250)
let arrowStart = CGPoint(x: 310, y: 250)
let arrowEnd = CGPoint(x: 490, y: 250)
let control1 = CGPoint(x: 370, y: 300)
let control2 = CGPoint(x: 430, y: 300)

let arrowPath = NSBezierPath()
arrowPath.move(to: arrowStart)
arrowPath.curve(to: arrowEnd, controlPoint1: control1, controlPoint2: control2)

// Arrow style
NSColor.white.withAlphaComponent(0.6).setStroke()
arrowPath.lineWidth = 2.5
// Add a clean dashed/dotted pattern for a tech vibe
let dashPattern: [CGFloat] = [6, 6]
arrowPath.setLineDash(dashPattern, count: 2, phase: 0)
arrowPath.stroke()

// Draw Chevron Head at arrowEnd
let chevronSize: CGFloat = 8.0
let chevronPath = NSBezierPath()
// Calculate tangent angle at the end of the bezier curve (roughly from control2 to arrowEnd)
let dy = arrowEnd.y - control2.y
let dx = arrowEnd.x - control2.x
let angle = atan2(dy, dx)

let pt1 = CGPoint(
    x: arrowEnd.x - chevronSize * cos(angle - .pi / 6),
    y: arrowEnd.y - chevronSize * sin(angle - .pi / 6)
)
let pt2 = CGPoint(
    x: arrowEnd.x - chevronSize * cos(angle + .pi / 6),
    y: arrowEnd.y - chevronSize * sin(angle + .pi / 6)
)

chevronPath.move(to: pt1)
chevronPath.line(to: arrowEnd)
chevronPath.line(to: pt2)
chevronPath.lineWidth = 2.5
chevronPath.setLineDash([], count: 0, phase: 0) // Solid arrowhead
chevronPath.lineCapStyle = .round
chevronPath.lineJoinStyle = .round
NSColor.white.withAlphaComponent(0.8).setStroke()
chevronPath.stroke()

// 4. Minimal, Premium Typography

func drawCenteredText(_ string: String, yPos: CGFloat, font: NSFont, color: NSColor, letterSpacing: CGFloat = 0) {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraphStyle,
        .kern: letterSpacing
    ]
    
    let attrString = NSAttributedString(string: string, attributes: attributes)
    let textSize = attrString.size()
    let xPos = (width - textSize.width) / 2.0
    attrString.draw(at: CGPoint(x: xPos, y: yPos))
}

drawCenteredText(
    "Install iData",
    yPos: 380,
    font: NSFont.systemFont(ofSize: 28, weight: .semibold),
    color: NSColor.white.withAlphaComponent(0.95),
    letterSpacing: 0.5
)

drawCenteredText(
    "Drag to Applications folder",
    yPos: 350,
    font: NSFont.systemFont(ofSize: 15, weight: .regular),
    color: NSColor.white.withAlphaComponent(0.6),
    letterSpacing: 0.2
)

// Subtle app version / footer at the bottom
drawCenteredText(
    "Native macOS shell for VisiData",
    yPos: 50,
    font: NSFont.systemFont(ofSize: 12, weight: .medium),
    color: NSColor.white.withAlphaComponent(0.3)
)

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
