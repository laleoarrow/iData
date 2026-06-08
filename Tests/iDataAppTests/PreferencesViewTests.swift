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
        #expect(cardSection.contains("PreferencesMenuButton(title: isChinese ? \"操作\" : \"Actions\""))
        #expect(cardSection.contains("testSmallFileHandoff()"))
        #expect(cardSection.contains("Test Handoff"))
        #expect(cardSection.contains("测试转交"))
        #expect(!cardSection.contains(".buttonStyle(.borderedProminent)"))
        #expect(normalized.contains("AppModel.smallFileRoutingThresholdDisplay"))
    }

    @Test
    func settingsUseMenuControlsForGroupedActionsAndOptionSelection() throws {
        let source = try preferencesViewSource()
        let normalized = normalizeWhitespace(source)
        let runtimeSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var runtimeCard: some View {",
            end: "private var smallFileRoutingCard: some View {"
        ))
        let languageSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var appLanguageCard: some View {",
            end: "private var updatesCard: some View {"
        ))
        let updatesSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var updatesCard: some View {",
            end: "private func testSmallFileHandoff()"
        ))

        #expect(normalized.contains("private struct PreferencesMenuButton<Content: View>: View"))
        #expect(runtimeSection.contains("PreferencesMenuButton(title: isChinese ? \"操作\" : \"Actions\""))
        #expect(runtimeSection.contains("Choose Executable"))
        #expect(runtimeSection.contains("Auto Detect"))
        #expect(languageSection.contains("PreferencesMenuButton(title: model.appLanguageOptionTitle(model.appLanguagePreference)"))
        #expect(languageSection.contains("model.appLanguagePreference = option"))
        #expect(!languageSection.contains("Picker("))
        #expect(!source.contains(".pickerStyle(.menu)"))
        #expect(!source.contains(".pickerStyle(.segmented)"))
        #expect(updatesSection.contains("PreferencesMenuButton(title: isChinese ? \"操作\" : \"Actions\""))
        #expect(updatesSection.contains("Check for Updates Now"))
        #expect(updatesSection.contains("Open Releases"))
    }

    @Test
    func actionMenusStayInCardHeadersWithoutFooterWhitespace() throws {
        let source = try preferencesViewSource()
        let smallFileSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var smallFileRoutingCard: some View {",
            end: "private var appLanguageCard: some View {"
        ))
        let runtimeSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var runtimeCard: some View {",
            end: "private var smallFileRoutingCard: some View {"
        ))
        let updatesSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var updatesCard: some View {",
            end: "private func testSmallFileHandoff()"
        ))

        for section in [smallFileSection, runtimeSection, updatesSection] {
            #expect(section.contains("accessory: { PreferencesMenuButton"))
            #expect(!section.contains("HStack { Spacer(minLength: 0) PreferencesMenuButton"))
        }
    }

    @Test
    func preferenceCardsUseRestrainedAccentTintAndCompactCopy() throws {
        let source = try preferencesViewSource()
        let heroSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var preferencesHero: some View {",
            end: "private var animationsCard: some View {"
        ))
        let smallFileSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var smallFileRoutingCard: some View {",
            end: "private var appLanguageCard: some View {"
        ))
        let cardChromeSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct PreferencesCard<Content: View, Accessory: View>: View {",
            end: "private extension PreferencesCard where Accessory == EmptyView {"
        ))

        #expect(heroSection.contains("Color.accentColor.opacity(0.18)"))
        #expect(heroSection.contains("Color.accentColor.opacity(0.08)"))
        #expect(smallFileSection.contains("PreferencesCard(title: isChinese ? \"小文件打开方式\""))
        #expect(smallFileSection.contains("Color.accentColor.opacity(0.16)"))
        #expect(smallFileSection.contains("Finder 交来的小型 CSV / Excel 优先转交"))
        #expect(!smallFileSection.contains("model.smallFileRoutingSummary"))
        #expect(!source.contains("tint: .cyan"))
        #expect(!source.contains("tint: .orange"))
        #expect(!source.contains("tint: .indigo"))
        #expect(!source.contains("tint: .blue"))
        #expect(!source.contains("tint: .green, accessory"))
        #expect(cardChromeSection.contains("let tint: Color"))
        #expect(cardChromeSection.contains(".foregroundStyle(tint)"))
        #expect(cardChromeSection.contains("tint.opacity(0.16)"))
        #expect(cardChromeSection.contains("RoundedRectangle(cornerRadius: 2"))
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
