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
