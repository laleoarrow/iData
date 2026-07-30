import Foundation
import Testing

struct ContentViewLayoutTests {
    @Test
    func sidebarCollapseAvoidsWindowWideLayoutAnimation() throws {
        let source = try contentViewSource()
        let root = try extractSection(from: source, start: "struct ContentView: View {", end: "private struct SidebarView: View {")

        #expect(root.contains(".frame(width: sidebarWidth)"))
        #expect(root.contains(".frame(minWidth: 680, minHeight: 460)"))
        #expect(!root.contains("value: model.isSidebarCollapsed"))
        #expect(!root.contains("AppSweepShimmer("))
    }

    @Test
    func sidebarUsesNativeScrollingWithoutDecorativeScrollRail() throws {
        let source = try contentViewSource()
        let sidebar = try extractSection(from: source, start: "private struct SidebarView: View {", end: "private struct FloatingSidebarRail")

        #expect(sidebar.contains("ScrollView(.vertical)"))
        #expect(sidebar.contains(".scrollIndicators(.automatic)"))
        #expect(sidebar.contains(".background(Color.clear)"))
        #expect(sidebar.contains("Color.primary.opacity(0.055)"))
        #expect(!sidebar.contains("controlBackgroundColor"))
        #expect(!sidebar.contains("SidebarScrollPositionLine("))
        #expect(!sidebar.contains("HiddenScrollIndicatorsConfigurator()"))
    }

    @Test
    func recentRowsUseFlatSelectionAndOneActionMenu() throws {
        let source = try contentViewSource()
        let row = try extractSection(from: source, start: "private struct RecentFileRow: View {", end: "private struct RecentFileActionButton")

        #expect(row.contains("Menu {"))
        #expect(row.contains(".menuStyle(.borderlessButton)"))
        #expect(row.contains("Color.accentColor.opacity(0.14)"))
        #expect(!row.contains(".shadow("))
        #expect(!row.contains("SidebarHoverGlow("))
    }

    @Test
    func welcomeFocusesOnOpeningData() throws {
        let source = try contentViewSource()
        let welcome = try extractSection(from: source, start: "private struct WelcomeDetailView: View {", end: "private struct TutorialEntryCard")
        let body = try extractSection(from: welcome, start: "var body: some View {", end: "private var heroCard")

        #expect(body.contains("heroCard"))
        #expect(body.contains("quickTipsCard"))
        #expect(body.contains("systemStatusSection"))
        #expect(!body.contains("tutorialEntryCard"))
        #expect(!body.contains("formatsCard"))
        #expect(welcome.contains("打开数据"))
        #expect(welcome.contains("选择表格，直接进入 VisiData。"))
    }

    @Test
    func welcomeUsesOnePrimaryActionAndAnOverflowMenu() throws {
        let source = try contentViewSource()
        let welcome = try extractSection(from: source, start: "private struct WelcomeDetailView: View {", end: "private struct TutorialEntryCard")

        #expect(welcome.contains("Label(isChinese ? \"打开…\" : \"Open…\", systemImage: \"tablecells\")"))
        #expect(welcome.contains("Text(isChinese ? \"更多\" : \"More\")"))
        #expect(welcome.contains(".menuStyle(.button)"))
        #expect(welcome.contains(".buttonStyle(.bordered)"))
        #expect(welcome.contains("quickTipColumn(Array(quickTips.prefix(2)), keyWidth: 94)"))
        #expect(welcome.contains("quickTipColumn(Array(quickTips.dropFirst(2).prefix(2)), keyWidth: 58)"))
        #expect(welcome.contains("ViewThatFits(in: .horizontal)"))
        #expect(welcome.contains(".frame(minWidth: 560)"))
        #expect(welcome.contains("quickTipColumn(Array(quickTips.prefix(4)), keyWidth: 94)"))
        #expect(welcome.contains(".minimumScaleFactor(0.72)"))
        #expect(welcome.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(!welcome.contains("GeometryReader"))
        #expect(!welcome.contains("Spacer(minLength: 18)"))
        #expect(welcome.contains("model.presentTutorialHub()"))
        #expect(welcome.contains("SettingsLink"))
    }

    @Test
    func helpUsesTopicNavigationInsteadOfStackedCards() throws {
        let source = try contentViewSource()
        let help = try extractSection(from: source, start: "private struct HelpView: View {", end: "private enum HelpTopic")

        #expect(help.contains("NavigationSplitView"))
        #expect(help.contains("List(HelpTopic.allCases, selection: $selectedTopic)"))
        #expect(help.contains("helpSection(title: \"\", tips: selectedTips)"))
    }

    @Test
    func tutorialUsesChapterNavigationAndFocusedDetail() throws {
        let source = try contentViewSource()
        let tutorial = try extractSection(from: source, start: "private struct TutorialHubView: View {", end: "private struct WelcomeDetailView")

        #expect(tutorial.contains("NavigationSplitView"))
        #expect(tutorial.contains("List(model.tutorialChapters, selection: $selectedChapterID)"))
        #expect(tutorial.contains("private var selectedChapter"))
        #expect(tutorial.contains("开始练习"))
    }

    @Test
    func sessionTipDoesNotCoverTerminal() throws {
        let source = try contentViewSource()
        let session = try extractSection(from: source, start: "private struct SessionDetailView: View {", end: "private struct SessionHeaderActions")

        let hintRange = try #require(session.range(of: "if shouldShowSessionInfoHint"))
        let terminalRange = try #require(session.range(of: "ZStack(alignment: .topTrailing)"))
        #expect(hintRange.lowerBound < terminalRange.lowerBound)
        #expect(session.contains(".clipShape(RoundedRectangle(cornerRadius: 10"))
        #expect(!session.contains(".shadow(color: .black.opacity(0.18), radius: 24"))
    }

    @Test
    func sessionHeaderKeepsOnlyOpenAndOverflowVisible() throws {
        let source = try contentViewSource()
        let actions = try extractSection(from: source, start: "private struct SessionHeaderActions: View {", end: "func statusPanelUsesRunningTint")

        #expect(actions.contains(".buttonStyle(.borderedProminent)"))
        #expect(actions.contains("Menu {"))
        #expect(actions.contains("Image(systemName: \"ellipsis.circle\")"))
        #expect(!actions.contains("ViewThatFits"))
    }

    @Test
    func externalNoticeAndStatusBarUseCompactChrome() throws {
        let source = try contentViewSource()
        let notice = try extractSection(from: source, start: "private struct ExternalHandoffNoticeBanner", end: "private struct StatusAndInputCard")
        let status = try extractSection(from: source, start: "private struct StatusAndInputCard", end: "private struct OrbButtonStyle")

        #expect(notice.contains(".frame(width: 380"))
        #expect(notice.contains("cornerRadius: 10"))
        #expect(!notice.contains("LinearGradient("))
        #expect(status.contains(".padding(.vertical, 8)"))
        #expect(!status.contains(".onHover"))
    }

    @Test
    func sharedReadOnlyComponentsDoNotAnimateOnHover() throws {
        let source = try sharedUISource()
        let status = try extractSection(from: source, start: "struct StatusPill: View {", end: "struct FormatChip")
        let message = try extractSection(from: source, start: "struct MessageCard: View {", end: "}")

        #expect(!status.contains(".quietInteractiveSurface"))
        #expect(!status.contains(".onHover"))
        #expect(!message.contains(".shadow("))
    }
}

private func contentViewSource(filePath: StaticString = #filePath) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(filePath)")
    let repositoryRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: repositoryRoot.appendingPathComponent("Sources/iData/ContentView.swift"),
        encoding: .utf8
    )
}

private func sharedUISource(filePath: StaticString = #filePath) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(filePath)")
    let repositoryRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: repositoryRoot.appendingPathComponent("Sources/iData/ContentViewSharedUI.swift"),
        encoding: .utf8
    )
}

private func extractSection(from source: String, start: String, end: String) throws -> String {
    guard let startRange = source.range(of: start) else {
        throw NSError(domain: "ContentViewLayoutTests", code: 1)
    }
    guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        throw NSError(domain: "ContentViewLayoutTests", code: 2)
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}
