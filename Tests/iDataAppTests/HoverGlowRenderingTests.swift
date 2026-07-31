import AppKit
import SwiftUI
import Testing
@testable import iData

@MainActor
struct HoverGlowRenderingTests {
    @Test
    func visibleGlowRendersAColoredSurfaceWhileHiddenGlowStaysTransparent() throws {
        let visiblePixel = try centerPixel(isVisible: true)
        let prominentPixel = try centerPixel(isVisible: true, style: .prominentRounded(8))
        let hiddenPixel = try centerPixel(isVisible: false)

        #expect(visiblePixel.alphaComponent > 0.03)
        #expect(visiblePixel.blueComponent > visiblePixel.redComponent)
        #expect(prominentPixel.alphaComponent > visiblePixel.alphaComponent * 1.4)
        #expect(hiddenPixel.alphaComponent < 0.01)
    }

    @Test
    func prominentGlowExtendsBeyondTheButtonEdge() throws {
        let outsidePixel = try prominentOutsidePixel()

        #expect(outsidePixel.alphaComponent > 0.015)
        #expect(outsidePixel.blueComponent > outsidePixel.redComponent)
    }

    private func centerPixel(
        isVisible: Bool,
        style: SidebarHoverGlowStyle = .rounded(8)
    ) throws -> NSColor {
        let renderer = ImageRenderer(
            content: SidebarHoverGlow(
                isVisible: isVisible,
                style: style
            )
            .frame(width: 120, height: 44)
        )
        renderer.scale = 1

        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        return try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
    }

    private func prominentOutsidePixel() throws -> NSColor {
        let renderer = ImageRenderer(
            content: SidebarHoverGlow(
                isVisible: true,
                style: .prominentRounded(8)
            )
            .frame(width: 120, height: 44)
            .padding(8)
        )
        renderer.scale = 1

        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        return try #require(bitmap.colorAt(x: 6, y: bitmap.pixelsHigh / 2))
    }
}
