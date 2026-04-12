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
    func recentFileRowUsesTrailingButtonBorderGlowInsteadOfFullCardGlow() throws {
        let source = normalizeWhitespace(try contentViewSource())

        #expect(!source.contains(normalizeWhitespace("""
        private struct RecentFileRow: View {
        """)) || !source.contains(normalizeWhitespace("""
        .overlay {
            SidebarHoverGlow(
                isVisible: isHovering,
                style: .rounded(20)
            )
        }
        """)))

        #expect(source.contains("private var actionBorderGradient: LinearGradient"))
        #expect(source.contains(normalizeWhitespace("""
        Circle()
            .strokeBorder(actionBorderGradient, lineWidth: isHovering ? 1.2 : 0.9)
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
