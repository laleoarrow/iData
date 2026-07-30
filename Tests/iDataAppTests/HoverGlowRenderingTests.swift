import AppKit
import SwiftUI
import Testing
@testable import iData

@MainActor
struct HoverGlowRenderingTests {
    @Test
    func visibleGlowRendersAColoredSurfaceWhileHiddenGlowStaysTransparent() throws {
        let visiblePixel = try centerPixel(isVisible: true)
        let hiddenPixel = try centerPixel(isVisible: false)

        #expect(visiblePixel.alphaComponent > 0.03)
        #expect(visiblePixel.blueComponent > visiblePixel.redComponent)
        #expect(hiddenPixel.alphaComponent < 0.01)
    }

    private func centerPixel(isVisible: Bool) throws -> NSColor {
        let renderer = ImageRenderer(
            content: SidebarHoverGlow(
                isVisible: isVisible,
                style: .rounded(8)
            )
            .frame(width: 120, height: 44)
        )
        renderer.scale = 1

        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        return try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
    }
}
