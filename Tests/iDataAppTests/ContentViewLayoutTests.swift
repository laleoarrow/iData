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
            RecentFileActionButton(
                symbol: isPinned ? "pin.fill" : "pin",
        """)))
        #expect(source.contains(normalizeWhitespace("""
        .overlay(alignment: .trailing) {
            RecentFileActionButton(
                symbol: "xmark",
        """)))
        #expect(source.contains(".offset(x: -46)"))
        #expect(source.contains(".offset(x: -14)"))
        #expect(!source.contains(normalizeWhitespace("""
        .overlay(alignment: .trailing) {
            HStack(spacing: 8) {
        """)))
    }

    @Test
    func sidebarHoverGlowStaysInsideButtonBounds() throws {
        let source = try contentViewSource()
        let glowSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "struct SidebarHoverGlow: View {",
            end: "private struct SidebarHoverTrackingRegion: NSViewRepresentable {"
        ))

        #expect(source.contains("struct SidebarHoverGlow"))
        #expect(glowSection.contains("Color(red: 1.0, green: 0.86, blue: 0.26)"))
        #expect(glowSection.contains("Color(red: 0.23, green: 0.58, blue: 1.0)"))
        #expect(!glowSection.contains(".scaleEffect(1.08)"))
        #expect(!glowSection.contains(".scaleEffect(1.16)"))
        #expect(!glowSection.contains(".scaleEffect(1.18)"))
        #expect(!glowSection.contains(".strokeBorder("))
        #expect(glowSection.contains(".clipShape(shape)"))
    }

    @Test
    func recentFileRowsUseSingleBorderWithoutHoverGlowOverlay() throws {
        let source = try contentViewSource()
        let expandedRow = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct RecentFileRow: View {",
            end: "private struct RecentFileActionButton: View {"
        ))
        let collapsedRow = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct CollapsedRecentFileRow: View {",
            end: "private struct SidebarCollapseToggleButton: View {"
        ))

        #expect(expandedRow.contains(".strokeBorder(borderColor)"))
        #expect(expandedRow.contains(".background(backgroundStyle"))
        #expect(!expandedRow.contains("SidebarHoverGlow("))
        #expect(collapsedRow.contains(".strokeBorder(borderColor)"))
        #expect(collapsedRow.contains(".background(backgroundStyle"))
        #expect(!collapsedRow.contains("SidebarHoverGlow("))
    }

    @Test
    func sidebarFooterIconsUseSingleLayerStableHoverSurface() throws {
        let source = try contentViewSource()
        let normalized = normalizeWhitespace(source)
        let footerSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SidebarFooterActionIcon: View {",
            end: "enum SidebarHoverGlowStyle: Equatable {"
        ))

        #expect(normalized.contains("private struct SidebarFooterActionIcon: View"))
        #expect(normalized.contains(normalizeWhitespace("""
        SettingsLink {
            SidebarFooterActionIcon(symbol: "gearshape.fill", motionEnabled: motionEnabled)
        }
        """)))
        #expect(!normalized.contains(normalizeWhitespace("""
        SidebarFooterIcon(symbol: "gearshape.fill")
            .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.05, hoverYOffset: -1, glowStyle: .circle)
        """)))
        #expect(footerSection.contains(normalizeWhitespace("""
        .foregroundStyle(isHovering ? Color.accentColor : Color.secondary)
        """)))
        #expect(footerSection.contains(".background(Color.white.opacity(isHovering ? 0.12 : 0.05), in: Circle())"))
        #expect(footerSection.contains(".onHover { hovering in"))
        #expect(!footerSection.contains("LinearGradient("))
        #expect(!footerSection.contains("Color(red: 1.0"))
        #expect(!footerSection.contains("SidebarHoverTrackingRegion"))
    }

    @Test
    func circularIconButtonsUseReducedMotionAwareHoverAnimation() throws {
        let source = try contentViewSource()
        let helperSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private enum HoverAnimatedCircleSymbolKind",
            end: "enum SidebarHoverGlowStyle: Equatable {"
        ))
        let inputOrb = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct InputMethodQuickSwitchOrbButton: View {",
            end: "private struct SessionInfoHintPanel: View {"
        ))

        #expect(helperSection.contains("case \"gearshape.fill\", \"gearshape\": return .gearSpin"))
        #expect(helperSection.contains("case \"globe\": return .globeSpin"))
        #expect(helperSection.contains("case \"questionmark.circle\", \"questionmark.circle.fill\": return .helpBounce"))
        #expect(helperSection.contains("return Double(spinCycle) * 360"))
        #expect(helperSection.contains(".rotation3DEffect( .degrees(depthRotationDegrees), axis: (x: 0, y: 1, z: 0), perspective: motionKind == .globeSpin ? 0.44 : 0 )"))
        #expect(helperSection.contains("return motionKind == .helpBounce ? 1.1 : 1.06"))
        #expect(helperSection.contains(".symbolEffect(.bounce, value: feedbackCycle)"))
        #expect(helperSection.contains("guard hovering && motionEnabled else"))
        #expect(helperSection.contains("spinCycle += 1"))
        #expect(helperSection.contains("feedbackCycle += 1"))
        #expect(helperSection.contains(".animation(motionEnabled ? .spring(response: 0.22"))

        #expect(inputOrb.contains("HoverAnimatedCircleSymbol( symbol: \"globe\""))
        #expect(inputOrb.contains("@Environment(\\.idataAnimationsEnabled) private var idataAnimationsEnabled"))
        #expect(inputOrb.contains("@Environment(\\.accessibilityReduceMotion) private var accessibilityReduceMotion"))
        #expect(inputOrb.contains(".animation(motionEnabled ? .easeOut(duration: 0.18) : nil, value: isHovering)"))
    }

    @Test
    func chineseSessionHintsUseShortNativeCopy() throws {
        let source = try contentViewSource()
        let hintSection = try extractSection(
            from: source,
            start: "private var sessionInfoHints: [String] {",
            end: "var body: some View {"
        )

        #expect(hintSection.contains("\"先按 z，再按 ?。这不是组合键。\""))
        #expect(hintSection.contains("\"搜索后按 Enter；再用 n/N 看下一个结果。\""))
        #expect(!hintSection.contains("提示："))
        #expect(!hintSection.contains("不是同时按"))
        #expect(!hintSection.contains("再实践一遍"))
    }

    @Test
    func collapsedSidebarHeaderUsesCenteredIconButtonWithoutChevron() throws {
        let source = try contentViewSource()
        let normalized = normalizeWhitespace(source)
        let sidebarHeaderSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SidebarHeaderCard: View {",
            end: "private struct SidebarFooter: View {"
        ))

        #expect(normalized.contains(normalizeWhitespace("""
        SidebarView(model: model)
            .frame(width: sidebarWidth)
            .frame(maxHeight: .infinity)
        """)))
        #expect(normalized.contains(".clipped()"))
        #expect(sidebarHeaderSection.contains(normalizeWhitespace("""
        if model.isSidebarCollapsed {
            collapsedExpandButton
                .frame(maxWidth: .infinity, alignment: .center)
                .transition(.opacity)
        """)))
        #expect(sidebarHeaderSection.contains("ZStack { Circle()"))
        #expect(sidebarHeaderSection.contains("appIcon"))
        #expect(sidebarHeaderSection.contains(".frame(width: 54, height: 54)"))
        #expect(sidebarHeaderSection.contains("model.setSidebarCollapsed(false)"))
        #expect(!sidebarHeaderSection.contains("Image(systemName: \"chevron.right\")"))
        #expect(!sidebarHeaderSection.contains(".offset(x: 3)"))
        #expect(!sidebarHeaderSection.contains("CommandKeyMonitor"))
        #expect(!sidebarHeaderSection.contains("model.clearRecentFiles() } else"))
        #expect(!sidebarHeaderSection.contains("SidebarHoverTrackingRegion"))
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
            end: "private struct SessionInfoHintPanel: View {"
        ))

        #expect(normalizedCard.contains(".strokeBorder(Color.white.opacity(isHovering ? 0.16 : 0.10), lineWidth: 1)"))
        #expect(!normalizedCard.contains(normalizeWhitespace("""
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
        #expect(sessionSection.contains("headerActionButton("))
        #expect(sessionSection.contains("english: \"Open…\", chinese: \"打开…\""))
        #expect(sessionSection.contains("english: \"Reopen\", chinese: \"重新打开\""))
        #expect(sessionSection.contains("english: \"Show in Finder\", chinese: \"在 Finder 中显示\""))
        #expect(sessionSection.contains("english: \"Copy Path\", chinese: \"复制路径\""))
        #expect(!sessionSection.contains("ToolbarItemGroup"))
        #expect(!sessionSection.contains(".toolbar {"))
    }

    @Test
    func sessionInfoHintUsesFloatingDismissibleNotice() throws {
        let source = try contentViewSource()
        let sessionSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SessionDetailView: View {",
            end: "private struct SessionHeaderActions: View {"
        ))
        let hintSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SessionInfoHintPanel: View {",
            end: "private struct TutorialCoachOverlay: View {"
        ))

        #expect(sessionSection.contains("private var sessionHeader: some View"))
        #expect(sessionSection.contains("sessionPathLabel"))
        #expect(sessionSection.contains("SessionInfoHintPanel("))
        #expect(sessionSection.contains("canCycle: sessionInfoHints.count > 1"))
        #expect(sessionSection.contains("onPrevious: { moveSessionHint(by: -1) }"))
        #expect(sessionSection.contains("onNext: { moveSessionHint(by: 1) }"))
        #expect(sessionSection.contains("onDismiss: { isSessionInfoHintDismissed = true }"))
        #expect(sessionSection.contains(".transition(.move(edge: .top).combined(with: .opacity))"))
        #expect(!sessionSection.contains("private var sessionHint"))
        #expect(!sessionSection.contains(".frame(maxWidth: 560, alignment: .leading)"))
        #expect(hintSection.contains("keyboard.fill"))
        #expect(hintSection.contains("VisiData shortcut tip"))
        #expect(hintSection.contains("VisiData 快捷键提示"))
        #expect(hintSection.contains("Color.clear.background(.ultraThinMaterial)"))
        #expect(hintSection.contains("LinearGradient("))
        #expect(hintSection.contains("RoundedRectangle(cornerRadius: 16, style: .continuous)"))
        #expect(hintSection.contains("SessionHintControlButton("))
        #expect(hintSection.contains("systemImage: \"chevron.up\""))
        #expect(hintSection.contains("systemImage: \"chevron.down\""))
        #expect(hintSection.contains("systemImage: \"xmark\""))
        #expect(hintSection.contains("hoverTint: Color.red.opacity(0.72)"))
        #expect(hintSection.contains(".disabled(!canCycle)"))
        #expect(hintSection.contains(".shadow(color: hoverTint.opacity(isHovering && isEnabled ? 0.32 : 0), radius: 10, y: 0)"))
        #expect(hintSection.contains(".scaleEffect(isHovering && isEnabled ? 1.06 : 1)"))
        #expect(hintSection.contains("action: onDismiss"))
    }

    @Test
    func terminalAndFloatingPanelsUseSingleVisibleRoundedBorder() throws {
        let source = try contentViewSource()
        let sessionSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SessionDetailView: View {",
            end: "private struct SessionHeaderActions: View {"
        ))
        let statusCard = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct StatusAndInputCard: View {",
            end: "private struct OrbButtonStyle: ButtonStyle {"
        ))
        let tutorialOverlay = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct TutorialCoachOverlay: View {",
            end: "private struct CommandShortcutBadge: View {"
        ))

        #expect(sessionSection.contains("EmbeddedTerminalView(session: session)"))
        #expect(sessionSection.contains(".clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))"))
        #expect(sessionSection.contains(".background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))"))
        #expect(sessionSection.contains(".strokeBorder(Color.white.opacity(0.08))"))
        #expect(!sessionSection.contains("cornerRadius: 24"))
        #expect(!sessionSection.contains(".inset(by: 1) .strokeBorder"))

        #expect(statusCard.contains(".strokeBorder(Color.white.opacity(isHovering ? 0.16 : 0.10), lineWidth: 1)"))
        #expect(!statusCard.contains(".inset(by: 1) .strokeBorder"))
        #expect(!statusCard.contains("RoundedRectangle(cornerRadius: 16, style: .continuous) .inset(by: 1) .fill"))

        #expect(tutorialOverlay.contains(".strokeBorder(Color.white.opacity(0.18), lineWidth: 1)"))
        #expect(!tutorialOverlay.contains(".inset(by: 1) .strokeBorder"))
    }

    @Test
    func rootWindowAllowsNarrowOperationalLayout() throws {
        let source = normalizeWhitespace(try contentViewSource())

        #expect(source.contains(".frame(minWidth: 860, minHeight: 580)"))
    }

    @Test
    func sidebarSharesRootBackgroundWithoutIndependentPanel() throws {
        let source = try contentViewSource()
        let normalized = normalizeWhitespace(source)
        let sidebarSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SidebarView: View {",
            end: "private struct SidebarHeaderCard: View {"
        ))
        let railSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct FloatingSidebarRail<Content: View>: View {",
            end: "private let sidebarRecentFilesCoordinateSpace"
        ))

        #expect(normalized.contains(".background(detailBackground.ignoresSafeArea())"))
        #expect(!normalized.contains("Divider() .overlay(Color.white.opacity(0.04))"))
        #expect(sidebarSection.contains("Color.clear"))
        #expect(sidebarSection.contains("FloatingSidebarRail {"))
        #expect(!sidebarSection.contains("SidebarPanelEdgeBlend"))
        #expect(!sidebarSection.contains("SidebarAmbientGlow"))
        #expect(sidebarSection.contains(".padding(.vertical, 12)"))
        #expect(railSection.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)"))
        #expect(railSection.contains(".background(Color.clear)"))
        #expect(!railSection.contains(".fill(.ultraThinMaterial)"))
        #expect(!railSection.contains(".fill(detailBackground)"))
        #expect(!railSection.contains("SidebarRailBottomFade"))
        #expect(!railSection.contains(".strokeBorder("))
        #expect(!railSection.contains(".shadow(color:"))
        #expect(!normalized.contains("private struct SidebarAmbientGlow"))
    }

    @Test
    func welcomeAndSessionPagesUseRootWindowBackgroundOnly() throws {
        let source = try contentViewSource()
        let welcomeSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct WelcomeDetailView: View {",
            end: "private var heroCard: some View {"
        ))
        let sessionSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SessionDetailView: View {",
            end: "private func pickRandomSessionHint() {"
        ))

        #expect(welcomeSection.contains("ScrollView {"))
        #expect(sessionSection.contains("VStack(alignment: .leading, spacing: 10)"))
        #expect(sessionSection.contains(".padding(.top, 16)"))
        #expect(sessionSection.contains(".ignoresSafeArea(.container, edges: .top)"))
        #expect(!welcomeSection.contains(".background(detailBackground.ignoresSafeArea())"))
        #expect(!sessionSection.contains(".background(detailBackground.ignoresSafeArea())"))
    }

    @Test
    func sidebarUsesLeftScrollPositionLineInsteadOfNativeRightScroller() throws {
        let source = try contentViewSource()
        let sidebarSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SidebarView: View {",
            end: "private struct SidebarHeaderCard: View {"
        ))
        let positionLineSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SidebarScrollPositionLine: View {",
            end: "private struct HiddenScrollIndicatorsConfigurator: NSViewRepresentable {"
        ))
        let scrollBridgeSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct HiddenScrollIndicatorsConfigurator: NSViewRepresentable {",
            end: "private struct SidebarHeaderCard: View {"
        ))

        #expect(sidebarSection.contains("@State private var recentFilesScrollMetrics = SidebarScrollMetrics()"))
        #expect(sidebarSection.contains("@State private var recentFilesFrame: CGRect = .zero"))
        #expect(sidebarSection.contains("ScrollView(.vertical, showsIndicators: false)"))
        #expect(sidebarSection.contains("VStack(spacing: model.isSidebarCollapsed ? 12 : 10)"))
        #expect(!sidebarSection.contains("LazyVStack(spacing: model.isSidebarCollapsed ? 12 : 10)"))
        #expect(sidebarSection.contains("HiddenScrollIndicatorsConfigurator()"))
        #expect(sidebarSection.contains("ZStack(alignment: .topLeading)"))
        #expect(sidebarSection.contains(".coordinateSpace(name: sidebarCoordinateSpace)"))
        #expect(sidebarSection.contains("SidebarScrollFramePreferenceKey.self"))
        #expect(sidebarSection.contains("SidebarScrollPositionLine("))
        #expect(sidebarSection.contains("SidebarScrollMetricsPreferenceKey.self"))
        #expect(sidebarSection.contains("SidebarScrollViewportHeightPreferenceKey.self"))
        #expect(!sidebarSection.contains(".overlay(alignment: .trailing) { SidebarScrollPositionLine"))
        #expect(positionLineSection.contains("Color.accentColor.opacity(0.94)"))
        #expect(positionLineSection.contains(".frame(width: 4, height: thumbHeight)"))
        #expect(positionLineSection.contains(".shadow(color: Color.accentColor.opacity(0.48)"))
        #expect(positionLineSection.contains(".allowsHitTesting(false)"))
        #expect(scrollBridgeSection.contains("scrollView.hasVerticalScroller = false"))
        #expect(scrollBridgeSection.contains("scrollView.hasHorizontalScroller = false"))
        #expect(scrollBridgeSection.contains("scrollView.verticalScroller = nil"))
        #expect(scrollBridgeSection.contains("scheduleScrollIndicatorHiding(from:"))
        #expect(scrollBridgeSection.contains("nearestLeftAlignedScrollViewInWindow()"))
        #expect(scrollBridgeSection.contains("leftSidebarScrollViewsInWindow()"))
        #expect(scrollBridgeSection.contains("descendantScrollViews()"))
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
        let statusSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var systemStatusSection: some View {",
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

        for section in [firstRunSection, tutorialSection, statusSection, quickTipsSection, formatsSection] {
            #expect(section.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        }
    }

    @Test
    func systemStatusUsesASingleLayerReadOnlyCard() throws {
        let source = try contentViewSource()
        let statusSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private var systemStatusSection: some View {",
            end: "private var quickTipsCard: some View {"
        ))

        #expect(statusSection.contains("System Status"))
        #expect(statusSection.contains("系统状态"))
        #expect(statusSection.contains("ViewThatFits(in: .horizontal)"))
        #expect(statusSection.contains("Divider()"))
        #expect(statusSection.contains("private func systemStatusItem"))
        #expect(statusSection.contains("icon: \"terminal\""))
        #expect(statusSection.contains("icon: \"arrow.triangle.2.circlepath\""))
        #expect(statusSection.contains(".font(.title3.weight(.semibold))"))
        #expect(statusSection.contains(".font(.body)"))
        #expect(statusSection.contains(".frame(minHeight: 104, alignment: .top)"))
        #expect(statusSection.components(separatedBy: ".glassCard()").count == 2)
        #expect(!statusSection.contains(".quietInteractiveSurface("))
        #expect(!statusSection.contains("RoundedRectangle("))
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
            end: "private struct SidebarCollapseToggleButton: View {"
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
            end: "private struct SidebarCollapseToggleButton: View {"
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

    @Test
    func collapsedRecentFileRowUsesFixedCircularButtonHitTarget() throws {
        let source = try contentViewSource()
        let collapsedRow = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct CollapsedRecentFileRow: View {",
            end: "private struct SidebarCollapseToggleButton: View {"
        ))

        #expect(collapsedRow.contains("HStack { Spacer(minLength: 0) Button(action: openAction) {"))
        #expect(collapsedRow.contains(".frame(width: 46, height: 46) .frame(width: 54, height: 54) .contentShape(Circle())"))
        #expect(collapsedRow.contains(".buttonStyle(.plain)"))
        #expect(collapsedRow.contains(".background(backgroundStyle, in: Circle())"))
        #expect(collapsedRow.contains(".frame(maxWidth: .infinity)"))
        #expect(!collapsedRow.contains(".frame(maxWidth: .infinity) .contentShape(Circle())"))
    }

    @Test
    func collapsedSidebarButtonsKeepStableActions() throws {
        let source = try contentViewSource()
        let sidebarHeaderSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SidebarHeaderCard: View {",
            end: "private struct SidebarFooter: View {"
        ))
        let collapsedRow = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct CollapsedRecentFileRow: View {",
            end: "private struct SidebarCollapseToggleButton: View {"
        ))

        #expect(sidebarHeaderSection.contains("private var collapsedExpandButton: some View"))
        #expect(sidebarHeaderSection.contains("model.setSidebarCollapsed(false)"))
        #expect(!sidebarHeaderSection.contains("CommandKeyMonitor"))
        #expect(collapsedRow.contains("Button(action: openAction)"))
        #expect(collapsedRow.contains(".contextMenu {"))
        #expect(collapsedRow.contains("Button(role: .destructive)"))
        #expect(collapsedRow.contains("togglePinAction()"))
        #expect(!collapsedRow.contains("CommandKeyMonitor"))
        #expect(!source.contains("collapsedRecentFilePrimaryAction"))
    }

    @Test
    func sidebarModeChangesAnimateWidthContentAndFooterLayout() throws {
        let source = try contentViewSource()
        let normalized = normalizeWhitespace(source)
        let sidebarSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SidebarView: View {",
            end: "private struct SidebarHeaderCard: View {"
        ))
        let headerSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SidebarHeaderCard: View {",
            end: "private struct SidebarFooter: View {"
        ))
        let footerSection = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct SidebarFooter: View {",
            end: "private struct EmptySidebarState: View {"
        ))

        #expect(normalized.contains(".animation(sidebarLayoutAnimation, value: model.isSidebarCollapsed)"))
        #expect(sidebarSection.contains(".animation(listAnimation, value: model.isSidebarCollapsed)"))
        #expect(sidebarSection.contains(".transition(sidebarModeTransition)"))
        #expect(headerSection.contains(".animation(layoutAnimation, value: model.isSidebarCollapsed)"))
        #expect(footerSection.contains("AnyLayout(VStackLayout(spacing: 18))"))
        #expect(footerSection.contains("AnyLayout(HStackLayout(spacing: 18))"))
        #expect(footerSection.contains(".animation(layoutAnimation, value: model.isSidebarCollapsed)"))
    }

    @Test
    func glassAndHoverEffectsStayBehindReadableContent() throws {
        let source = try contentViewSource()
        let normalized = normalizeWhitespace(source)
        let statusCard = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct StatusAndInputCard: View {",
            end: "private struct OrbButtonStyle: ButtonStyle {"
        ))
        let orbButton = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct InputMethodQuickSwitchOrbButton: View {",
            end: "private struct SessionInfoHintPanel: View {"
        ))
        let quietSurface = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct QuietInteractiveSurfaceModifier: ViewModifier {",
            end: "extension View {"
        ))
        let sweepShimmer = normalizeWhitespace(try extractSection(
            from: source,
            start: "private struct AppSweepShimmer: View {",
            end: "struct VersionPill: View {"
        ))

        #expect(normalized.contains(".background { detailBackground.ignoresSafeArea() AppSweepShimmer(active: motionEnabled)"))
        #expect(!normalized.contains(".overlay { AppSweepShimmer(active: motionEnabled)"))
        #expect(!sweepShimmer.contains("TimelineView(.animation"))
        #expect(statusCard.contains(".background { ZStack { cardTint"))
        #expect(!statusCard.contains(".overlay { RoundedRectangle(cornerRadius: 16, style: .continuous) .inset(by: 1) .fill("))
        #expect(orbButton.contains(".background( ZStack { Circle() .fill(.ultraThinMaterial)"))
        #expect(!orbButton.contains(".overlay { Circle() .inset(by: 1) .fill("))
        #expect(quietSurface.contains(".background { SidebarHoverGlow("))
        #expect(!quietSurface.contains(".overlay { SidebarHoverGlow("))
    }
}

private func contentViewSource(filePath: StaticString = #filePath) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(filePath)")
    let repositoryRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try [
        "Sources/iData/ContentView.swift",
        "Sources/iData/ContentViewSharedUI.swift",
    ]
    .map { relativePath in
        let sourceURL = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
    .joined(separator: "\n")
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
