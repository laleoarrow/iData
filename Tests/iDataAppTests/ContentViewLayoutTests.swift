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
        let sidebar = try extractSection(from: source, start: "private struct SidebarView: View {", end: "private struct SidebarHeaderCard")

        #expect(sidebar.contains("ScrollView(.vertical)"))
        #expect(sidebar.contains(".scrollIndicators(.automatic)"))
        #expect(sidebar.contains(".background(Color.clear)"))
        #expect(sidebar.contains("Color.primary.opacity(0.055)"))
        #expect(!sidebar.contains("controlBackgroundColor"))
        #expect(!sidebar.contains("SidebarScrollPositionLine("))
        #expect(!sidebar.contains("HiddenScrollIndicatorsConfigurator()"))
    }

    @Test
    func unreachableSidebarLegacyDeclarationsStayRemoved() throws {
        let source = try contentViewSource()
        let declarations = [
            "@State private var recentFilesScrollMetrics",
            "@State private var recentFilesMinY",
            "@State private var recentFilesViewportHeight",
            "private var listAnimation",
            "private struct FloatingSidebarRail",
            "private let sidebarCoordinateSpace",
            "private let sidebarRecentFilesCoordinateSpace",
            "private struct SidebarScrollMetrics:",
            "private struct SidebarScrollMetricsPreferenceKey",
            "private struct SidebarScrollViewportHeightPreferenceKey",
            "private struct SidebarScrollMinYPreferenceKey",
            "private struct SidebarScrollPositionLine",
            "private struct HiddenScrollIndicatorsConfigurator",
            "func nearestEnclosingScrollView()",
            "func nearestLeftAlignedScrollViewInWindow()",
            "func leftSidebarScrollViewsInWindow()",
            "func descendantScrollViews()",
            "private struct RecentFileActionButton",
            "private struct SidebarFooterIcon",
            "private struct SidebarHoverTrackingRegion",
            "private final class HoverTrackingView",
            "private struct AppSweepShimmer",
        ]

        for declaration in declarations {
            #expect(!source.contains(declaration))
        }
    }

    @Test
    func recentRowsKeepOneActionMenuAndEventDrivenHoverGlow() throws {
        let source = try contentViewSource()
        let row = try extractSection(from: source, start: "private struct RecentFileRow: View {", end: "private struct CollapsedRecentFileRow")
        let collapsedRow = try extractSection(from: source, start: "private struct CollapsedRecentFileRow: View {", end: "private struct SidebarCollapseToggleButton")

        #expect(row.contains("Menu {"))
        #expect(row.contains(".menuStyle(.borderlessButton)"))
        #expect(row.contains("Color.accentColor.opacity(0.14)"))
        #expect(row.contains("SidebarHoverGlow(isVisible: true, style: .rounded(8))"))
        #expect(row.contains(".onHover { hovering in"))
        #expect(row.contains("guard hovering != isHovering"))
        #expect(!row.contains("onContinuousHover"))
        #expect(!row.contains(".shadow("))
        #expect(!row.contains("private var backgroundStyle"))
        #expect(!row.contains("private var borderColor"))
        #expect(!collapsedRow.contains("private var backgroundStyle"))
        #expect(!collapsedRow.contains("private var borderColor"))
    }

    @Test
    func welcomeFocusesOnOpeningData() throws {
        let source = try contentViewSource()
        let welcome = try extractSection(from: source, start: "private struct WelcomeDetailView: View {", end: "private struct SessionDetailView")
        let body = try extractSection(from: welcome, start: "var body: some View {", end: "private func heroCard")

        #expect(body.contains("heroCard"))
        #expect(body.contains("quickTipsCard"))
        #expect(body.contains("systemStatusSection"))
        #expect(body.contains("let dependencyState = model.visiDataDependencyState"))
        #expect(body.components(separatedBy: "model.visiDataDependencyState").count - 1 == 1)
        #expect(body.contains("heroCard(dependencyState: dependencyState)"))
        #expect(body.contains("systemStatusSection(dependencyState: dependencyState)"))
        #expect(welcome.contains("heroPrimaryActions(dependencyState: dependencyState)"))
        #expect(welcome.contains("if case .missing = dependencyState"))
        #expect(!body.contains("tutorialEntryCard"))
        #expect(!body.contains("formatsCard"))
        #expect(welcome.contains("打开数据"))
        #expect(welcome.contains("选择表格，直接进入 VisiData。"))
    }

    @Test
    func welcomeUsesOnePrimaryActionAndAnOverflowMenu() throws {
        let source = try contentViewSource()
        let welcome = try extractSection(from: source, start: "private struct WelcomeDetailView: View {", end: "private struct SessionDetailView")

        #expect(welcome.contains("Label(isChinese ? \"打开…\" : \"Open…\", systemImage: \"tablecells\")"))
        #expect(welcome.contains(".quietInteractiveSurface(enabled: motionEnabled, glowStyle: .prominentRounded(8))"))
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
        let coach = try extractSection(from: source, start: "private struct TutorialCoachOverlay: View", end: "private struct CommandShortcutBadge")

        #expect(tutorial.contains("NavigationSplitView"))
        #expect(tutorial.contains("List(model.tutorialChapters, selection: $selectedChapterID)"))
        #expect(tutorial.contains("private var selectedChapter"))
        #expect(tutorial.contains("开始练习"))
        #expect(tutorial.contains("if let errorMessage = model.tutorialErrorMessage"))
        #expect(tutorial.contains("→ 表示依次按"))
        #expect(tutorial.contains("| 表示任选"))
        #expect(!tutorial.contains("完成后会自动标记"))
        #expect(coach.contains("model.cancelTutorial()"))
        #expect(coach.components(separatedBy: "returnFocusToTable()").count - 1 == 6)
        #expect(coach.contains(".disabled(item.index > max(model.tutorialStepIndex, chapter.completedStepCount))"))
        #expect(coach.contains("做完了，下一步"))
        #expect(coach.contains("做完了，完成本章"))
        #expect(source.contains(".sheet(isPresented: $model.isTutorialHubPresented, onDismiss:"))
        #expect(source.contains("model.displayedSession?.focusTerminalDisplay()"))
    }

    @Test
    func unreachableDetailAndSharedUIDeclarationsStayRemoved() throws {
        let source = try contentViewSource()
        let sharedSource = try sharedUISource()
        let help = try extractSection(from: source, start: "private struct HelpView: View {", end: "private enum HelpTopic")
        let tutorial = try extractSection(from: source, start: "private struct TutorialHubView: View {", end: "private struct WelcomeDetailView")

        for declaration in [
            "private var helpHero",
            "private var header: some View",
            "private func chapterCard(",
            "@State private var customAssociationInput",
            "private var normalizedCustomAssociationExtension",
            "private var canSubmitCustomAssociation",
            "private var isSettingCustomAssociation",
            "private var isCustomAssociationDefault",
            "private var customAssociationActionTitle",
            "private var customAssociationActionIcon",
            "private var displayedFormatExtensions",
            "private var orderedSupportedFormats",
            "private func refreshDisplayedFormatAssociationStatus",
            "private var heroSecondaryActions",
            "private var showsReadyDependencyPillInTitleRow",
            "private var showsHeroMetadataRow",
            "private var tutorialEntryCard",
            "private var dependencyPill",
            "private func systemStatusItem",
            "private var formatsCard",
            "private struct TutorialEntryCard",
        ] {
            #expect(!source.contains(declaration))
        }

        #expect(!help.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(!help.contains("private var motionEnabled"))
        #expect(!tutorial.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(!tutorial.contains("private var motionEnabled"))

        for declaration in [
            "struct GlassCardModifier",
            "func glassCard()",
            "struct VersionPill",
            "struct StatusPill",
        ] {
            #expect(!sharedSource.contains(declaration))
        }

        #expect(sharedSource.contains("struct FormatChip"))
        #expect(sharedSource.contains("struct MessageCard"))
    }

    @Test
    func activeHelpAndSessionHintsUseVerifiedVisiDataBindings() throws {
        let source = try contentViewSource()

        #expect(source.contains("z → Ctrl+H"))
        #expect(source.contains("当前列排序：[ 升序，] 降序。"))
        #expect(source.contains("Sort the current column with `[` (asc) and `]` (desc)."))
        #expect(!source.contains("先按 z，再按 ?"))
        #expect(!source.contains("当前列排序：] 升序，[ 降序。"))
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
        let root = try extractSection(from: source, start: "struct ContentView: View {", end: "private struct SidebarView")
        let notice = try extractSection(from: source, start: "private struct ExternalHandoffNoticeBanner", end: "private struct StatusAndInputCard")
        let status = try extractSection(from: source, start: "private struct StatusAndInputCard", end: "private struct OrbButtonStyle")

        #expect(root.contains(".transition(.move(edge: .top).combined(with: .opacity))"))
        #expect(root.contains("value: model.externalHandoffNotice"))
        #expect(notice.contains(".frame(width: 380"))
        #expect(notice.contains("cornerRadius: 10"))
        #expect(!notice.contains("LinearGradient("))
        #expect(status.contains(".padding(.vertical, 8)"))
        #expect(!status.contains(".onHover"))
    }

    @Test
    func sharedMessageCardDoesNotAddDecorativeShadow() throws {
        let source = try sharedUISource()
        let message = try extractSuffix(from: source, start: "struct MessageCard: View {")

        #expect(!message.contains(".shadow("))
    }

    @Test
    func interactiveHoverGlowUpdatesOnlyAtPointerBoundaries() throws {
        let sharedSource = try sharedUISource()
        let modifier = try extractSection(
            from: sharedSource,
            start: "private struct QuietInteractiveSurfaceModifier",
            end: "extension View"
        )
        let contentSource = try contentViewSource()
        let glow = try extractSection(
            from: contentSource,
            start: "struct SidebarHoverGlow: View",
            end: "private struct SessionStageView"
        )

        #expect(modifier.contains("@State private var isHovering = false"))
        #expect(modifier.contains("if enabled && isHovering"))
        #expect(modifier.contains("SidebarHoverGlow("))
        #expect(modifier.contains(".transition(.opacity)"))
        #expect(modifier.contains(".onHover { hovering in"))
        #expect(modifier.contains("guard nextHoverState != isHovering"))
        #expect(!modifier.contains("onContinuousHover"))
        #expect(!modifier.contains(".scaleEffect("))
        #expect(!modifier.contains(".offset("))
        #expect(!modifier.contains(".shadow("))

        #expect(glow.contains("LinearGradient("))
        #expect(glow.contains(".strokeBorder("))
        #expect(!glow.contains("GeometryReader"))
        #expect(!glow.contains("RadialGradient("))
        #expect(!glow.contains(".blur("))
        #expect(!glow.contains(".shadow("))
        #expect(!glow.contains("TimelineView"))
    }

    @Test
    func sidebarControlsRestoreShapeMatchedHoverGlowWithoutContinuousTracking() throws {
        let source = try contentViewSource()
        let header = try extractSection(
            from: source,
            start: "private struct SidebarHeaderCard: View",
            end: "private struct SidebarFooter: View"
        )
        let collapsedRow = try extractSection(
            from: source,
            start: "private struct CollapsedRecentFileRow: View",
            end: "private struct SidebarCollapseToggleButton"
        )
        let collapseButton = try extractSection(
            from: source,
            start: "private struct SidebarCollapseToggleButton: View",
            end: "private struct SidebarFooterActionIcon"
        )

        #expect(header.contains("SidebarHoverGlow(isVisible: true, style: .circle)"))
        #expect(header.contains("guard hovering != isHoveringCollapsedIcon"))
        #expect(collapsedRow.contains("SidebarHoverGlow(isVisible: true, style: .circle)"))
        #expect(collapsedRow.contains("guard hovering != isHovering"))
        #expect(collapseButton.contains("SidebarHoverGlow(isVisible: true, style: .rounded(8))"))
        #expect(collapseButton.contains("guard hovering != isHovering"))

        #expect(!header.contains("onContinuousHover"))
        #expect(!collapsedRow.contains("onContinuousHover"))
        #expect(!collapseButton.contains("onContinuousHover"))
    }

    @Test
    func sidebarFooterKeepsThreeDistinctHoverAnimationsAndConditionalGlow() throws {
        let source = try contentViewSource()
        let footer = try extractSection(
            from: source,
            start: "private struct SidebarFooter: View",
            end: "private struct EmptySidebarState"
        )
        let footerIcon = try extractSection(
            from: source,
            start: "private struct SidebarFooterActionIcon: View",
            end: "private enum HoverAnimatedCircleSymbolKind"
        )
        let animatedSymbol = try extractSection(
            from: source,
            start: "private enum HoverAnimatedCircleSymbolKind",
            end: "struct SidebarHoverGlow: View"
        )

        #expect(footer.contains("SidebarFooterActionIcon(symbol: \"gearshape.fill\""))
        #expect(footer.contains("SidebarFooterActionIcon(symbol: \"questionmark.circle\""))
        #expect(footer.contains("SidebarFooterActionIcon(symbol: \"graduationcap.fill\""))
        #expect(footerIcon.contains("HoverAnimatedCircleSymbol("))
        #expect(footerIcon.contains("SidebarHoverGlow(isVisible: true, style: .circle)"))
        #expect(footerIcon.contains("guard hovering != isHovering"))
        #expect(!footerIcon.contains("onContinuousHover"))
        #expect(!footerIcon.contains(".blur("))
        #expect(!footerIcon.contains(".shadow("))

        #expect(animatedSymbol.contains("case \"gearshape.fill\", \"gearshape\":"))
        #expect(animatedSymbol.contains("return .gearSpin"))
        #expect(animatedSymbol.contains("case \"questionmark.circle\", \"questionmark.circle.fill\":"))
        #expect(animatedSymbol.contains("return .helpBounce"))
        #expect(animatedSymbol.contains("case \"graduationcap.fill\":"))
        #expect(animatedSymbol.contains("return .tiltRight"))
        #expect(animatedSymbol.contains("spinCycle += 1"))
        #expect(animatedSymbol.contains("feedbackCycle += 1"))
        #expect(animatedSymbol.contains("return isHovering ? 7 : 0"))
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

private func extractSuffix(from source: String, start: String) throws -> String {
    guard let startRange = source.range(of: start) else {
        throw NSError(domain: "ContentViewLayoutTests", code: 3)
    }
    return String(source[startRange.lowerBound...])
}
