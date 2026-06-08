import Foundation
import Testing

struct PreferencesViewTests {
    @Test
    func smallFileOpeningSectionIsFirstClassAndActionable() throws {
        let source = try preferencesViewSource()
        let normalized = normalizeWhitespace(source)
        let bodySection = normalizeWhitespace(try extractSection(
            from: source,
            start: "VStack(alignment: .leading, spacing: 18) {",
            end: ".padding(24)"
        ))
        let cardSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var smallFileRoutingCard: some View {",
            end: "private var appLanguageCard: some View {"
        ))

        #expect(bodySection.contains("preferencesHero smallFileRoutingCard animationsCard appLanguageCard"))
        #expect(cardSection.contains("Small-File Opening"))
        #expect(cardSection.contains("小文件打开方式"))
        #expect(cardSection.contains("model.preferredSmallFileApplicationDisplayName"))
        #expect(cardSection.contains("model.testSmallFileHandoff()"))
        #expect(cardSection.contains("Test Handoff"))
        #expect(cardSection.contains("测试转交"))
        #expect(normalized.contains("AppModel.smallFileRoutingThresholdDisplay"))
    }
}

private func preferencesViewSource(filePath: StaticString = #filePath) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(filePath)")
    let repositoryRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let preferencesViewURL = repositoryRoot.appendingPathComponent("Sources/iData/PreferencesView.swift")
    return try String(contentsOf: preferencesViewURL, encoding: .utf8)
}

private func normalizeWhitespace(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func extractSection(from source: String, start: String, end: String) throws -> String {
    guard let startRange = source.range(of: start) else {
        throw NSError(domain: "PreferencesViewTests", code: 1)
    }
    guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        throw NSError(domain: "PreferencesViewTests", code: 2)
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}
