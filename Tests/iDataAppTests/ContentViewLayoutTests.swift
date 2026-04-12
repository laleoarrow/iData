import Foundation
import Testing

struct ContentViewLayoutTests {
    @Test
    func heroHeaderKeepsTitleInlineWithVersionAndDependencyPills() throws {
        let source = normalizeWhitespace(try contentViewSource())

        #expect(source.contains(normalizeWhitespace("""
        HStack(alignment: .center, spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
        """)))

        #expect(source.contains(normalizeWhitespace("""
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text("iData")
                    .font(.title2)
                    .fontWeight(.semibold)

                VersionPill(model: model, tint: .white.opacity(0.14), icon: "shippingbox")

                if showsReadyDependencyPillInTitleRow {
                    dependencyPill
                }
            }

            Text(isChinese ? "在原生 macOS 壳中打开超大表格文件，同时保留 VisiData 完整的行为、快捷键和运行速度。" : "Open large tables in a native macOS shell while keeping real VisiData behavior, shortcuts, and speed.")
        """)))
    }

    @Test
    func expandedRecentFileRowUsesFullCardPrimaryHitTarget() throws {
        let source = normalizeWhitespace(try contentViewSource())

        #expect(source.contains(normalizeWhitespace("""
        Button(action: openAction) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(fileURL.lastPathComponent)
        """)))

        #expect(source.contains(".padding(.trailing, 70)"))
        #expect(source.contains(normalizeWhitespace("""
        .overlay(alignment: .trailing) {
            HStack(spacing: 8) {
        """)))
    }

    @Test
    func sidebarHoverGlowUsesAppKitTrackingBridgeWithYellowBlueGradient() throws {
        let source = try contentViewSource()

        #expect(source.contains("private struct SidebarHoverTrackingRegion: NSViewRepresentable"))
        #expect(source.contains("private struct SidebarHoverGlow"))
        #expect(source.contains("Color(red: 1.0, green: 0.86, blue: 0.26)"))
        #expect(source.contains("Color(red: 0.23, green: 0.58, blue: 1.0)"))
    }

    @Test
    func recentFileRowUsesFullCardGlowInsteadOfTrailingButtonGlow() throws {
        let source = normalizeWhitespace(try contentViewSource())

        #expect(source.contains(normalizeWhitespace("""
        .overlay {
            SidebarHoverGlow(
                isVisible: isHovering,
                style: .rounded(20)
            )
        }
        """)))

        #expect(!source.contains("private var actionBorderGradient: LinearGradient"))
        #expect(source.contains("private struct RecentFileActionButton: View"))
    }

    @Test
    func sidebarTracksExactlyOneHoveredRecentFileAtATime() throws {
        let source = normalizeWhitespace(try contentViewSource())

        #expect(source.contains("@State private var hoveredRecentFilePath: String?"))
        #expect(source.contains("@State private var isHoveringRecentFileList = false"))
        #expect(source.contains(normalizeWhitespace("""
        private func recentFileHoverBinding(for fileURL: URL) -> Binding<Bool> {
            let hoverKey = fileURL.standardizedFileURL.path
        """)))
        #expect(source.contains(normalizeWhitespace("""
        if isHovering {
            hoveredRecentFilePath = hoverKey
        } else if hoveredRecentFilePath == hoverKey {
            hoveredRecentFilePath = nil
        }
        """)))
        #expect(source.contains(normalizeWhitespace("""
        .onChange(of: isHoveringRecentFileList) { _, newValue in
            if !newValue {
                hoveredRecentFilePath = nil
            }
        }
        """)))
    }

    @Test
    func selectedRecentFileRowDoesNotUsePersistentGlowShadow() throws {
        let source = normalizeWhitespace(try contentViewSource())

        #expect(source.contains(normalizeWhitespace("""
        .shadow(
            color: .black.opacity(motionEnabled && isHovering ? 0.10 : 0),
            radius: motionEnabled && isHovering ? 12 : 0,
            y: motionEnabled && isHovering ? 5 : 0
        )
        """)))
        #expect(!source.contains(normalizeWhitespace("""
        .shadow(color: .black.opacity(isActive ? 0.16 : 0.08), radius: isActive ? 16 : 10, y: 6)
        """)))
        #expect(!source.contains(normalizeWhitespace("""
        .shadow(color: .black.opacity(isActive ? 0.16 : 0.08), radius: isActive ? 14 : 8, y: 4)
        """)))
    }
}

private func contentViewSource(filePath: StaticString = #filePath) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(filePath)")
    let repositoryRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentViewURL = repositoryRoot.appendingPathComponent("Sources/iData/ContentView.swift")
    return try String(contentsOf: contentViewURL, encoding: .utf8)
}

private func normalizeWhitespace(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
