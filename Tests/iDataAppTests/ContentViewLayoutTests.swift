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

            Text(isChinese ? "以原生体验极速打开超大表格，完美保留 VisiData 的行为、快捷键与处理能力。" : "Open large tables with a native macOS experience while keeping full VisiData behavior, shortcuts, and speed.")
        """)))
    }

    @Test
    func quickStartPanelMatchesTutorialCardStructure() throws {
        let source = normalizeWhitespace(try contentViewSource())

        #expect(source.contains(normalizeWhitespace("""
        private var quickTipsCard: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
        """)))

        #expect(source.contains(normalizeWhitespace("""
        VStack(spacing: 9) {
            ForEach(quickTips) { tip in
                quickTipPreviewRow(tip)
            }
        }
        """)))

        #expect(source.contains(normalizeWhitespace("""
        private func quickTipPreviewRow(_ tip: QuickTip) -> some View {
            HStack(alignment: .top, spacing: 10) {
        """)))

        #expect(source.contains(normalizeWhitespace("""
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.20),
                    Color.white.opacity(0.05),
                ],
        """)))
    }

    @Test
    func sidebarAppIconUsesNativeArtworkWithoutExtraRoundedBackdrop() throws {
        let source = normalizeWhitespace(try contentViewSource())

        #expect(source.contains(normalizeWhitespace("""
        private var appIcon: some View {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
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
    func sidebarHoverGlowStaysInsideButtonBounds() throws {
        let source = try contentViewSource()
        let glowSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SidebarHoverGlow: View {",
            end: "private struct SidebarHoverTrackingRegion: NSViewRepresentable {"
        ))

        #expect(source.contains("private struct SidebarHoverGlow"))
        #expect(glowSection.contains("Color(red: 1.0, green: 0.86, blue: 0.26)"))
        #expect(glowSection.contains("Color(red: 0.23, green: 0.58, blue: 1.0)"))
        #expect(!glowSection.contains(".scaleEffect(1.08)"))
        #expect(!glowSection.contains(".scaleEffect(1.16)"))
        #expect(!glowSection.contains(".scaleEffect(1.18)"))
        #expect(glowSection.contains(".clipShape(shape)"))
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
    func sidebarFooterIconsUseSingleLayerStableHoverSurface() throws {
        let source = try contentViewSource()
        let normalized = normalizeWhitespace(source)
        let footerSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SidebarFooterActionIcon: View {",
            end: "private struct SidebarAmbientGlow: View {"
        ))

        #expect(normalized.contains("private struct SidebarFooterActionIcon: View"))
        #expect(normalized.contains(normalizeWhitespace("""
        SettingsLink {
            SidebarFooterActionIcon(symbol: "gearshape.fill")
        }
        """)))
        #expect(!normalized.contains(normalizeWhitespace("""
        SidebarFooterIcon(symbol: "gearshape.fill")
            .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.05, hoverYOffset: -1, glowStyle: .circle)
        """)))
        #expect(footerSection.contains(normalizeWhitespace("""
        Circle()
            .inset(by: 1)
            .fill(
        """)))
        #expect(footerSection.contains(".onHover { hovering in"))
        #expect(!footerSection.contains("SidebarHoverTrackingRegion"))
    }

    @Test
    func collapsedSidebarHeaderHoverStaysInsideSidebarBounds() throws {
        let source = try contentViewSource()
        let normalized = normalizeWhitespace(source)
        let sidebarHeaderSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SidebarHeaderCard: View {",
            end: "private struct CollapsedSidebarHeaderIconButton<Content: View>: View {"
        ))
        let collapsedHeaderSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct CollapsedSidebarHeaderIconButton<Content: View>: View {",
            end: "private struct SidebarFooter: View {"
        ))

        #expect(normalized.contains(normalizeWhitespace("""
        SidebarView(model: model)
            .frame(width: sidebarWidth)
            .frame(maxHeight: .infinity)
        """)))
        #expect(normalized.contains(".clipped()"))
        #expect(normalized.contains("private struct CollapsedSidebarHeaderIconButton<Content: View>: View"))
        #expect(sidebarHeaderSection.contains(normalizeWhitespace("""
        if model.isSidebarCollapsed {
            collapsedBody
        } else {
            expandedBody
                .padding(16)
        """)))
        #expect(collapsedHeaderSection.contains("Circle()"))
        #expect(collapsedHeaderSection.contains("if isHovering { Circle()"))
        #expect(collapsedHeaderSection.contains(".frame(width: 54, height: 54)"))
        #expect(!collapsedHeaderSection.contains("Color.white.opacity(0.04)"))
        #expect(!collapsedHeaderSection.contains("Color.white.opacity(0.02)"))
        #expect(!collapsedHeaderSection.contains("RoundedRectangle(cornerRadius: 14"))
        #expect(!collapsedHeaderSection.contains("SidebarHoverTrackingRegion"))
    }

    @Test
    func statusPanelHoverHighlightsStayInsideMatchingShapes() throws {
        let source = try contentViewSource()
        let normalizedCard = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct StatusAndInputCard: View {",
            end: "private struct InputMethodQuickSwitchOrbButton: View {"
        ))
        let normalizedOrb = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct InputMethodQuickSwitchOrbButton: View {",
            end: "private struct SessionInfoHintRow: View {"
        ))

        #expect(normalizedCard.contains(normalizeWhitespace("""
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .inset(by: 1)
            .fill(
        """)))
        #expect(!normalizedCard.contains(".quietInteractiveSurface("))
        #expect(!normalizedCard.contains("SidebarHoverTrackingRegion"))
        #expect(normalizedCard.contains(".onHover { hovering in"))
        #expect(normalizedOrb.contains(normalizeWhitespace("""
        Circle()
            .inset(by: 1)
            .fill(
        """)))
        #expect(!normalizedOrb.contains("SidebarHoverTrackingRegion"))
        #expect(normalizedOrb.contains(".onHover { hovering in"))
    }

    @Test
    func externalHandoffNoticeFloatsAboveRootShellWithReturnAction() throws {
        let source = normalizeWhitespace(try contentViewSource())

        #expect(source.contains(normalizeWhitespace("""
        .overlay(alignment: .topTrailing) {
            if let notice = model.externalHandoffNotice {
                ExternalHandoffNoticeBanner(
        """)))
        #expect(source.contains("onReturn: { model.returnExternalHandoffToIData() }"))
        #expect(source.contains("onDismiss: { model.dismissExternalHandoffNotice() }"))
        #expect(source.contains("private struct ExternalHandoffNoticeBanner: View {"))
    }

    @Test
    func externalHandoffNoticeUsesStatefulCopyAndClearReturnLabel() throws {
        let source = try contentViewSource()
        let bannerSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct ExternalHandoffNoticeBanner: View {",
            end: "private struct StatusAndInputCard: View {"
        ))

        #expect(bannerSection.contains("switch notice.state"))
        #expect(bannerSection.contains("Open in iData"))
        #expect(bannerSection.contains("用 iData 打开"))
        #expect(bannerSection.contains("did not respond"))
        #expect(bannerSection.contains("没有响应"))
    }

    @Test
    func sessionHeaderActionsCollapseBeforeClipping() throws {
        let source = try contentViewSource()
        let sessionSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SessionDetailView: View {",
            end: "private struct ExternalHandoffNoticeBanner: View {"
        ))

        #expect(sessionSection.contains("private struct SessionHeaderActions: View"))
        #expect(sessionSection.contains("ViewThatFits(in: .horizontal)"))
        #expect(sessionSection.contains("Menu {"))
        #expect(sessionSection.contains("Label(localizedText(isChinese, english: \"Actions\", chinese: \"操作\")"))
    }

    @Test
    func rootWindowAllowsNarrowOperationalLayout() throws {
        let source = normalizeWhitespace(try contentViewSource())

        #expect(source.contains(".frame(minWidth: 860, minHeight: 580)"))
    }

    @Test
    func handoffRulesButtonUsesSettingsLink() throws {
        let source = try contentViewSource()
        let formatsSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var formatsCard: some View {",
            end: "private struct SessionDetailView: View {"
        ))

        #expect(formatsSection.contains("SettingsLink {"))
        #expect(formatsSection.contains("Handoff Rules"))
        #expect(formatsSection.contains("设置转交规则"))
        #expect(!formatsSection.contains("showSettingsWindow:"))
    }

    @Test
    func emptySidebarStateOffersImmediateActions() throws {
        let source = try contentViewSource()
        let sidebarSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SidebarView: View {",
            end: "private struct SidebarHeaderCard: View {"
        ))
        let emptySection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct EmptySidebarState: View {",
            end: "private struct EmptySidebarRailState: View {"
        ))
        let railSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct EmptySidebarRailState: View {",
            end: "private struct RecentFileRow: View {"
        ))

        #expect(sidebarSection.contains("openAction: { model.openDocument() }"))
        #expect(sidebarSection.contains("tutorialAction: { model.presentTutorialHub() }"))
        #expect(emptySection.contains("Open File"))
        #expect(emptySection.contains("打开文件"))
        #expect(emptySection.contains("Tutorial"))
        #expect(emptySection.contains("教程"))
        #expect(railSection.contains("Button(action: openAction)"))
        #expect(railSection.contains("Open a table"))
        #expect(railSection.contains("打开一个表格"))
    }

    @Test
    func firstRunEmptyStateCreatesClearNextSteps() throws {
        let source = try contentViewSource()
        let welcomeSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct WelcomeDetailView: View {",
            end: "private struct SessionDetailView: View {"
        ))

        #expect(welcomeSection.contains("private var showsFirstRunEmptyState: Bool"))
        #expect(welcomeSection.contains("model.recentFiles.isEmpty && model.lastOpenedFile == nil"))
        #expect(welcomeSection.contains("if showsFirstRunEmptyState { firstRunEmptyStateCard }"))
        #expect(welcomeSection.contains("Start with a table"))
        #expect(welcomeSection.contains("先打开一份数据"))
        #expect(welcomeSection.contains("Open First Table"))
        #expect(welcomeSection.contains("打开第一份表格"))
        #expect(welcomeSection.contains("Review Handoff Settings"))
        #expect(welcomeSection.contains("查看转交设置"))
    }

    @Test
    func welcomePanelsUseConsistentFullWidth() throws {
        let source = try contentViewSource()
        let firstRunSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var firstRunEmptyStateCard: some View {",
            end: "@ViewBuilder\n    private func firstRunActionButton"
        ))
        let tutorialSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var tutorialEntryCard: some View {",
            end: "private func startCarouselTimer()"
        ))
        let summarySection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var summaryCards: some View {",
            end: "private var quickTipsCard: some View {"
        ))
        let quickTipsSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var quickTipsCard: some View {",
            end: "@ViewBuilder\n    private func quickTipPreviewRow"
        ))
        let formatsSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var formatsCard: some View {",
            end: "private struct SessionDetailView: View {"
        ))

        for section in [firstRunSection, tutorialSection, summarySection, quickTipsSection, formatsSection] {
            #expect(section.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        }
    }

    @Test
    func sidebarTracksExactlyOneHoveredRecentFileAtATime() throws {
        let source = normalizeWhitespace(try contentViewSource())

        #expect(source.contains("@State private var hoveredRecentFilePath: String?"))
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
        .onHover { hovering in
            if !hovering {
                hoveredRecentFilePath = nil
            }
        }
        """)))
        #expect(source.contains(normalizeWhitespace("""
        .onChange(of: model.recentFiles.map { $0.standardizedFileURL.path }) { _, _ in
            hoveredRecentFilePath = nil
        }
        """)))
    }

    @Test
    func selectedRecentFileRowDoesNotUsePersistentGlowShadow() throws {
        let source = try contentViewSource()
        let expandedRow = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct RecentFileRow: View {",
            end: "private struct RecentFileActionButton: View {"
        ))
        let collapsedRow = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct CollapsedRecentFileRow: View {",
            end: "enum CollapsedRecentFilePrimaryAction: Equatable {"
        ))

        #expect(!expandedRow.contains(".shadow("))
        #expect(!collapsedRow.contains(".shadow("))
    }

    @Test
    func recentFileRowsUseStableHoverWithoutTrackingBridge() throws {
        let source = try contentViewSource()
        let expandedRow = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct RecentFileRow: View {",
            end: "private struct RecentFileActionButton: View {"
        ))
        let collapsedRow = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct CollapsedRecentFileRow: View {",
            end: "enum CollapsedRecentFilePrimaryAction: Equatable {"
        ))

        #expect(expandedRow.contains(".onHover { hovering in"))
        #expect(!expandedRow.contains("SidebarHoverTrackingRegion"))
        #expect(!expandedRow.contains(".scaleEffect(motionEnabled && isHovering ? 1.012 : 1)"))
        #expect(!expandedRow.contains(".offset(y: motionEnabled && isHovering ? -1 : 0)"))

        #expect(collapsedRow.contains(".onHover { hovering in"))
        #expect(!collapsedRow.contains("SidebarHoverTrackingRegion"))
        #expect(!collapsedRow.contains(".scaleEffect(motionEnabled && isHovering ? 1.02 : 1)"))
        #expect(!collapsedRow.contains(".offset(y: motionEnabled && isHovering ? -1 : 0)"))
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

private func extractSection(from source: String, start: String, end: String) throws -> String {
    guard let startRange = source.range(of: start) else {
        throw NSError(domain: "ContentViewLayoutTests", code: 1)
    }
    guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        throw NSError(domain: "ContentViewLayoutTests", code: 2)
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}
