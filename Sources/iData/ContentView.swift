import AppKit
import SwiftUI

func localizedText(_ isChinese: Bool, english: String, chinese: String) -> String {
    isChinese ? chinese : english
}

func appShellLanguage() -> AppModel.AppResolvedLanguage {
    AppModel.resolvedLanguage(defaults: .standard, preferredLanguagesProvider: { Locale.preferredLanguages })
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdaterController
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    private let expandedSidebarWidth: CGFloat = 292
    private let collapsedSidebarWidth: CGFloat = 92

    private var sidebarWidth: CGFloat {
        model.isSidebarCollapsed ? collapsedSidebarWidth : expandedSidebarWidth
    }

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var sidebarLayoutAnimation: Animation? {
        motionEnabled
            ? .spring(response: 0.44, dampingFraction: 0.90, blendDuration: 0.18)
            : nil
    }

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity)

            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            detailBackground.ignoresSafeArea()
            AppSweepShimmer(active: motionEnabled)
                .ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            if let notice = model.externalHandoffNotice {
                ExternalHandoffNoticeBanner(
                    isChinese: isChinese,
                    notice: notice,
                    motionEnabled: motionEnabled,
                    onReturn: { model.returnExternalHandoffToIData() },
                    onDismiss: { model.dismissExternalHandoffNotice() }
                )
                .padding(.top, 18)
                .padding(.trailing, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(minWidth: 860, minHeight: 580)
        .animation(sidebarLayoutAnimation, value: model.isSidebarCollapsed)
        .animation(motionEnabled ? .spring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.12) : nil, value: model.externalHandoffNotice)
        .dropDestination(for: URL.self) { items, _ in
            model.handleDroppedFiles(items)
        }
        .sheet(isPresented: $model.isHelpPresented) {
            HelpView(model: model)
        }
        .sheet(isPresented: $model.isTutorialHubPresented) {
            TutorialHubView(model: model)
        }
        .environment(\EnvironmentValues.idataAnimationsEnabled, model.animationsEnabled)
    }

    @ViewBuilder
    private var detailContent: some View {
        if let session = model.displayedSession {
            SessionStageView(model: model, updater: updater, session: session)
        } else {
            WelcomeDetailView(model: model, updater: updater)
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var hoveredRecentFilePath: String?
    @State private var recentFilesScrollMetrics = SidebarScrollMetrics()
    @State private var recentFilesFrame: CGRect = .zero
    @State private var recentFilesViewportHeight: CGFloat = 0

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var listAnimation: Animation? {
        motionEnabled
            ? .spring(response: 0.32, dampingFraction: 0.90, blendDuration: 0.14)
            : nil
    }

    private var sidebarModeTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: .leading))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            FloatingSidebarRail {
                VStack(alignment: .leading, spacing: model.isSidebarCollapsed ? 14 : 16) {
                    SidebarHeaderCard(model: model)

                    if model.recentFiles.isEmpty {
                        if model.isSidebarCollapsed {
                            EmptySidebarRailState(
                                isChinese: model.effectiveLanguage == .chinese,
                                openAction: { model.openDocument() }
                            )
                            .transition(sidebarModeTransition)
                        } else {
                            EmptySidebarState(
                                isChinese: model.effectiveLanguage == .chinese,
                                openAction: { model.openDocument() },
                                tutorialAction: { model.presentTutorialHub() }
                            )
                            .transition(sidebarModeTransition)
                        }
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: model.isSidebarCollapsed ? 12 : 10) {
                                ForEach(model.recentFiles, id: \.standardizedFileURL.path) { fileURL in
                                    Group {
                                        if model.isSidebarCollapsed {
                                            CollapsedRecentFileRow(
                                                fileURL: fileURL,
                                                isActive: model.activeSession?.currentFileURL?.standardizedFileURL == fileURL.standardizedFileURL,
                                                isPinned: model.isPinnedRecentFile(fileURL),
                                                isHovering: recentFileHoverBinding(for: fileURL),
                                                isChinese: model.effectiveLanguage == .chinese,
                                                openAction: { model.openExternalFile(fileURL) },
                                                togglePinAction: { model.togglePinnedRecentFile(fileURL) },
                                                removeAction: { model.removeRecentFile(fileURL) }
                                            )
                                            .id("collapsed-\(fileURL.standardizedFileURL.path)")
                                            .transition(sidebarModeTransition)
                                        } else {
                                            RecentFileRow(
                                                fileURL: fileURL,
                                                isActive: model.activeSession?.currentFileURL?.standardizedFileURL == fileURL.standardizedFileURL,
                                                isPinned: model.isPinnedRecentFile(fileURL),
                                                isHovering: recentFileHoverBinding(for: fileURL),
                                                isChinese: model.effectiveLanguage == .chinese,
                                                openAction: { model.openExternalFile(fileURL) },
                                                togglePinAction: { model.togglePinnedRecentFile(fileURL) },
                                                removeAction: { model.removeRecentFile(fileURL) }
                                            )
                                            .id("expanded-\(fileURL.standardizedFileURL.path)")
                                            .transition(sidebarModeTransition)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, model.isSidebarCollapsed ? 0 : 2)
                            .padding(.bottom, 6)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: SidebarScrollMetricsPreferenceKey.self,
                                        value: SidebarScrollMetrics(
                                            contentHeight: proxy.size.height,
                                            contentMinY: proxy.frame(in: .named(sidebarRecentFilesCoordinateSpace)).minY
                                        )
                                    )
                                }
                            )
                        }
                        .coordinateSpace(name: sidebarRecentFilesCoordinateSpace)
                        .scrollIndicators(.hidden)
                        .background(HiddenScrollIndicatorsConfigurator())
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: SidebarScrollViewportHeightPreferenceKey.self,
                                    value: proxy.size.height
                                )
                            }
                        )
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: SidebarScrollFramePreferenceKey.self,
                                    value: proxy.frame(in: .named(sidebarCoordinateSpace))
                                )
                            }
                        )
                        .animation(listAnimation, value: model.recentFiles)
                        .onPreferenceChange(SidebarScrollMetricsPreferenceKey.self) { metrics in
                            recentFilesScrollMetrics = metrics
                        }
                        .onPreferenceChange(SidebarScrollFramePreferenceKey.self) { frame in
                            recentFilesFrame = frame
                        }
                        .onPreferenceChange(SidebarScrollViewportHeightPreferenceKey.self) { height in
                            recentFilesViewportHeight = height
                        }
                        .onHover { hovering in
                            if !hovering {
                                hoveredRecentFilePath = nil
                            }
                        }
                        .onChange(of: model.recentFiles.map { $0.standardizedFileURL.path }) { _, _ in
                            hoveredRecentFilePath = nil
                        }
                    }

                    Spacer(minLength: 0)

                    SidebarFooter(model: model)
                }
                .padding(model.isSidebarCollapsed
                    ? EdgeInsets(top: 14, leading: 8, bottom: 14, trailing: 8)
                    : EdgeInsets(top: 16, leading: 14, bottom: 16, trailing: 14))
            }
            .padding(.vertical, 12)
            .padding(.leading, model.isSidebarCollapsed ? 10 : 14)
            .padding(.trailing, model.isSidebarCollapsed ? 6 : 10)

            if !model.recentFiles.isEmpty {
                SidebarScrollPositionLine(
                    metrics: recentFilesScrollMetrics,
                    viewportHeight: recentFilesViewportHeight,
                    motionEnabled: motionEnabled
                )
                .offset(
                    x: model.isSidebarCollapsed ? 16 : 22,
                    y: recentFilesFrame.minY + 5
                )
            }
        }
        .coordinateSpace(name: sidebarCoordinateSpace)
        .clipped()
        .animation(listAnimation, value: model.isSidebarCollapsed)
        .onChange(of: model.isSidebarCollapsed) { _, _ in
            hoveredRecentFilePath = nil
        }
    }

    private func recentFileHoverBinding(for fileURL: URL) -> Binding<Bool> {
        let hoverKey = fileURL.standardizedFileURL.path
        return Binding(
            get: { hoveredRecentFilePath == hoverKey },
            set: { isHovering in
                if isHovering {
                    hoveredRecentFilePath = hoverKey
                } else if hoveredRecentFilePath == hoverKey {
                    hoveredRecentFilePath = nil
                }
            }
        )
    }
}

private struct FloatingSidebarRail<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.clear)
    }
}

private let sidebarCoordinateSpace = "iDataSidebar"
private let sidebarRecentFilesCoordinateSpace = "iDataSidebarRecentFilesScroll"

private struct SidebarScrollMetrics: Equatable {
    var contentHeight: CGFloat = 0
    var contentMinY: CGFloat = 0
}

private struct SidebarScrollMetricsPreferenceKey: PreferenceKey {
    static let defaultValue = SidebarScrollMetrics()

    static func reduce(value: inout SidebarScrollMetrics, nextValue: () -> SidebarScrollMetrics) {
        value = nextValue()
    }
}

private struct SidebarScrollViewportHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SidebarScrollFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct SidebarScrollPositionLine: View {
    let metrics: SidebarScrollMetrics
    let viewportHeight: CGFloat
    let motionEnabled: Bool

    private var isScrollable: Bool {
        metrics.contentHeight > viewportHeight + 2
    }

    private var trackHeight: CGFloat {
        max(44, viewportHeight - 10)
    }

    private var thumbHeight: CGFloat {
        guard isScrollable else {
            return trackHeight
        }
        let ratio = viewportHeight / max(metrics.contentHeight, 1)
        return min(trackHeight, max(42, trackHeight * ratio))
    }

    private var scrollProgress: CGFloat {
        guard isScrollable else {
            return 0
        }
        let maxOffset = max(metrics.contentHeight - viewportHeight, 1)
        return min(max(-metrics.contentMinY / maxOffset, 0), 1)
    }

    private var thumbOffset: CGFloat {
        (trackHeight - thumbHeight) * scrollProgress
    }

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Color.white.opacity(0.07))
                .frame(width: 2, height: trackHeight)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.78),
                            Color.accentColor.opacity(0.94),
                            Color.accentColor.opacity(0.58),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: thumbHeight)
                .shadow(color: Color.accentColor.opacity(0.48), radius: 9, x: 0, y: 0)
                .offset(y: thumbOffset)
        }
        .frame(width: 10, height: trackHeight)
        .opacity(isScrollable ? 1 : 0)
        .animation(motionEnabled ? .easeOut(duration: 0.18) : nil, value: scrollProgress)
        .animation(motionEnabled ? .easeOut(duration: 0.18) : nil, value: thumbHeight)
        .allowsHitTesting(false)
    }
}

private struct HiddenScrollIndicatorsConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleScrollIndicatorHiding(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleScrollIndicatorHiding(from: nsView)
    }

    private func scheduleScrollIndicatorHiding(from view: NSView) {
        for delay in [0.0, 0.05, 0.25, 0.75] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                hideScrollIndicators(from: view)
            }
        }
    }

    private func hideScrollIndicators(from view: NSView) {
        let directScrollView = view.nearestEnclosingScrollView() ?? view.nearestLeftAlignedScrollViewInWindow()
        let scrollViews = ([directScrollView].compactMap { $0 } + view.leftSidebarScrollViewsInWindow())
        var hiddenScrollViewIDs = Set<ObjectIdentifier>()

        for scrollView in scrollViews where hiddenScrollViewIDs.insert(ObjectIdentifier(scrollView)).inserted {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScroller = nil
            scrollView.horizontalScroller = nil
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
        }
    }
}

private extension NSView {
    func nearestEnclosingScrollView() -> NSScrollView? {
        var candidate: NSView? = self
        while let current = candidate {
            if let scrollView = current as? NSScrollView {
                return scrollView
            }
            candidate = current.superview
        }
        return nil
    }

    func nearestLeftAlignedScrollViewInWindow() -> NSScrollView? {
        guard let contentView = window?.contentView else {
            return nil
        }

        let sourceRect = convert(bounds, to: nil).insetBy(dx: -4, dy: -4)
        let scrollViews = contentView.descendantScrollViews()
        let intersecting = scrollViews.filter { scrollView in
            scrollView.convert(scrollView.bounds, to: nil).intersects(sourceRect)
        }

        if let nearestIntersecting = intersecting.min(by: { lhs, rhs in
            let lhsRect = lhs.convert(lhs.bounds, to: nil)
            let rhsRect = rhs.convert(rhs.bounds, to: nil)
            return abs(lhsRect.midX - sourceRect.midX) < abs(rhsRect.midX - sourceRect.midX)
        }) {
            return nearestIntersecting
        }

        return scrollViews
            .filter { scrollView in
                scrollView.convert(scrollView.bounds, to: nil).midX < 360
            }
            .min { lhs, rhs in
                lhs.convert(lhs.bounds, to: nil).minX < rhs.convert(rhs.bounds, to: nil).minX
            }
    }

    func leftSidebarScrollViewsInWindow() -> [NSScrollView] {
        guard let contentView = window?.contentView else {
            return []
        }

        return contentView.descendantScrollViews().filter { scrollView in
            let frame = scrollView.convert(scrollView.bounds, to: nil)
            return frame.minX < 320 && frame.maxX < 340 && frame.height > 80
        }
    }

    func descendantScrollViews() -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let scrollView = self as? NSScrollView {
            result.append(scrollView)
        }
        for subview in subviews {
            result.append(contentsOf: subview.descendantScrollViews())
        }
        return result
    }
}

private struct SidebarHeaderCard: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isHoveringCollapsedIcon = false

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var layoutAnimation: Animation? {
        motionEnabled
            ? .spring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.14)
            : nil
    }

    private var expandedDetailsTransition: AnyTransition {
        guard motionEnabled else {
            return .identity
        }

        return .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.12).delay(0.20)),
            removal: .identity
        )
    }

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.isSidebarCollapsed {
                collapsedExpandButton
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
            } else {
                appIcon

                expandedDetails
                    .padding(.leading, 60)
                    .transition(expandedDetailsTransition)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .padding(.horizontal, model.isSidebarCollapsed ? 0 : 2)
        .padding(.vertical, model.isSidebarCollapsed ? 0 : 4)
        .animation(layoutAnimation, value: model.isSidebarCollapsed)
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("iData")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Spacer(minLength: 0)

                if !model.recentFiles.isEmpty {
                    Button(localizedText(isChinese, english: "Clear All", chinese: "清空全部")) {
                        model.clearRecentFiles()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.02, hoverYOffset: -1)
                    .help(localizedText(isChinese, english: "Clear all recent file records", chinese: "清除所有最近文件记录"))
                }

                SidebarCollapseToggleButton(
                    isChinese: isChinese,
                    motionEnabled: motionEnabled,
                    action: { model.setSidebarCollapsed(true) }
                )
            }

            Text(localizedText(
                isChinese,
                english: "Native shell for large-table workflows with VisiData",
                chinese: "在原生 macOS 中轻松查看超大表格"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var collapsedExpandButton: some View {
        Button {
            model.setSidebarCollapsed(false)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isHoveringCollapsedIcon ? 0.08 : 0))
                    .overlay(
                        Circle()
                            .strokeBorder(
                                Color.white.opacity(isHoveringCollapsedIcon ? 0.14 : 0),
                                lineWidth: 1
                            )
                    )

                appIcon
            }
            .frame(width: 54, height: 54)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(localizedText(isChinese, english: "Expand sidebar", chinese: "展开侧边栏"))
        .accessibilityLabel(localizedText(isChinese, english: "Expand sidebar", chinese: "展开侧边栏"))
        .onHover { hovering in
            isHoveringCollapsedIcon = hovering
        }
        .animation(motionEnabled ? .easeOut(duration: 0.18) : nil, value: isHoveringCollapsedIcon)
    }

    private var appIcon: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 48, height: 48)
            .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
            .allowsHitTesting(false)
    }
}

private struct SidebarFooter: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var layoutAnimation: Animation? {
        motionEnabled
            ? .spring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.14)
            : nil
    }

    private var footerLayout: AnyLayout {
        if model.isSidebarCollapsed {
            return AnyLayout(VStackLayout(spacing: 18))
        }
        return AnyLayout(HStackLayout(spacing: 18))
    }

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    var body: some View {
        footerLayout {
            SettingsLink {
                SidebarFooterActionIcon(symbol: "gearshape.fill", motionEnabled: motionEnabled)
            }
            .buttonStyle(.plain)
            .help(localizedText(isChinese, english: "Settings", chinese: "设置"))

            Button {
                model.isHelpPresented = true
            } label: {
                SidebarFooterActionIcon(symbol: "questionmark.circle", motionEnabled: motionEnabled)
            }
            .buttonStyle(.plain)
            .help(localizedText(isChinese, english: "Help", chinese: "帮助"))

            Button {
                model.presentTutorialHub()
            } label: {
                SidebarFooterActionIcon(symbol: "graduationcap.fill", motionEnabled: motionEnabled)
            }
            .buttonStyle(.plain)
            .help(localizedText(isChinese, english: "Tutorial", chinese: "教程"))
        }
        .frame(
            maxWidth: .infinity,
            alignment: model.isSidebarCollapsed ? .center : .leading
        )
        .foregroundStyle(.secondary)
        .animation(layoutAnimation, value: model.isSidebarCollapsed)
    }
}

private struct EmptySidebarState: View {
    let isChinese: Bool
    let openAction: () -> Void
    let tutorialAction: () -> Void
    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(localizedText(isChinese, english: "No recent files yet", chinese: "暂无最近文件"), systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.headline)

            Text(localizedText(
                isChinese,
                english: "Open a table or drag one into the window. Recent items stay here for one-click reopening.",
                chinese: "打开一个表格，或直接把文件拖进窗口。最近文件会保留在这里，方便一键重新打开。"
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    openAction()
                } label: {
                    Label(localizedText(isChinese, english: "Open File", chinese: "打开文件"), systemImage: "tablecells")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    tutorialAction()
                } label: {
                    Label(localizedText(isChinese, english: "Tutorial", chinese: "教程"), systemImage: "graduationcap.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .quietInteractiveSurface(
            enabled: idataAnimationsEnabled && !accessibilityReduceMotion,
            hoverScale: 1.008,
            hoverYOffset: -1,
            shadowOpacity: 0.08,
            shadowRadius: 12
        )
    }
}

private struct EmptySidebarRailState: View {
    let isChinese: Bool
    let openAction: () -> Void
    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button(action: openAction) {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.14), in: Circle())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(localizedText(isChinese, english: "Open a table", chinese: "打开一个表格"))
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .quietInteractiveSurface(
            enabled: idataAnimationsEnabled && !accessibilityReduceMotion,
            hoverScale: 1.008,
            hoverYOffset: -1,
            shadowOpacity: 0.08,
            shadowRadius: 12
        )
    }
}

private struct RecentFileRow: View {
    let fileURL: URL
    let isActive: Bool
    let isPinned: Bool
    @Binding var isHovering: Bool
    let isChinese: Bool
    let openAction: () -> Void
    let togglePinAction: () -> Void
    let removeAction: () -> Void

    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var motionEnabled: Bool {
        idataAnimationsEnabled && !accessibilityReduceMotion
    }

    var body: some View {
        Button(action: openAction) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(fileURL.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(fileURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .padding(.trailing, 70)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor)
        )
        .overlay(alignment: .trailing) {
            RecentFileActionButton(
                symbol: isPinned ? "pin.fill" : "pin",
                foregroundStyle: isPinned ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary),
                backgroundFill: isPinned ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.08),
                isVisible: isHovering,
                action: togglePinAction
            )
            .offset(x: -46)
            .help(isPinned
                ? localizedText(isChinese, english: "Unpin from top", chinese: "取消置顶")
                : localizedText(isChinese, english: "Pin to top", chinese: "置顶"))
        }
        .overlay(alignment: .trailing) {
            RecentFileActionButton(
                symbol: "xmark",
                foregroundStyle: AnyShapeStyle(.secondary),
                backgroundFill: Color.white.opacity(0.08),
                isVisible: isHovering,
                action: removeAction
            )
            .offset(x: -14)
            .help(localizedText(isChinese, english: "Remove from recent files", chinese: "从最近文件中移除"))
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            Button {
                openAction()
            } label: {
                Label(localizedText(isChinese, english: "Open", chinese: "打开"), systemImage: "arrow.right.circle")
            }

            Button {
                togglePinAction()
            } label: {
                Label(
                    isPinned
                        ? localizedText(isChinese, english: "Unpin", chinese: "取消置顶")
                        : localizedText(isChinese, english: "Pin to Top", chinese: "置顶"),
                    systemImage: isPinned ? "pin.slash" : "pin"
                )
            }

            Divider()

            Button(role: .destructive) {
                removeAction()
            } label: {
                Label(localizedText(isChinese, english: "Remove from Recents", chinese: "从最近文件中移除"), systemImage: "trash")
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(motionEnabled ? .easeOut(duration: 0.18) : nil, value: isHovering)
    }

    private var backgroundStyle: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.22),
                        Color.white.opacity(0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        if isHovering {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.accentColor.opacity(0.10),
                        Color.white.opacity(0.05),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(.thinMaterial)
    }

    private var borderColor: Color {
        if isActive {
            return Color.accentColor.opacity(0.34)
        }

        if isHovering {
            return Color.white.opacity(0.12)
        }

        return Color.white.opacity(0.06)
    }
}

private struct RecentFileActionButton: View {
    let symbol: String
    let foregroundStyle: AnyShapeStyle
    let backgroundFill: Color
    let isVisible: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(foregroundStyle)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(backgroundFill.opacity(isVisible ? (isHovering ? 1 : 0.88) : 0))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(isVisible ? (isHovering ? 0.26 : 0.14) : 0), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.16), value: isVisible)
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .onHover { hovering in
            isHovering = isVisible && hovering
        }
    }
}

private struct CollapsedRecentFileRow: View {
    let fileURL: URL
    let isActive: Bool
    let isPinned: Bool
    @Binding var isHovering: Bool
    let isChinese: Bool
    let openAction: () -> Void
    let togglePinAction: () -> Void
    let removeAction: () -> Void

    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var motionEnabled: Bool {
        idataAnimationsEnabled && !accessibilityReduceMotion
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            Button(action: openAction) {
                Text(AppModel.collapsedRecentFileBadgeText(for: fileURL))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .frame(width: 46, height: 46)
                .frame(width: 54, height: 54)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(localizedText(
                isChinese,
                english: "Open \(fileURL.lastPathComponent) — right-click for more actions",
                chinese: "打开 \(fileURL.lastPathComponent)；右键查看更多操作"
            ))
            .background(backgroundStyle, in: Circle())
            .overlay(
                Circle()
                    .strokeBorder(borderColor)
            )
            .contentShape(Circle())
            .contextMenu {
                Button {
                    openAction()
                } label: {
                    Label(localizedText(isChinese, english: "Open", chinese: "打开"), systemImage: "arrow.right.circle")
                }

                Button {
                    togglePinAction()
                } label: {
                    Label(
                        isPinned
                            ? localizedText(isChinese, english: "Unpin", chinese: "取消置顶")
                            : localizedText(isChinese, english: "Pin to Top", chinese: "置顶"),
                        systemImage: isPinned ? "pin.slash" : "pin"
                    )
                }

                Divider()

                Button(role: .destructive) {
                    removeAction()
                } label: {
                    Label(localizedText(isChinese, english: "Remove from Recents", chinese: "从最近文件中移除"), systemImage: "trash")
                }
            }
            .onHover { hovering in
                isHovering = hovering
            }
            .animation(motionEnabled ? .easeOut(duration: 0.18) : nil, value: isHovering)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var backgroundStyle: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.18),
                        Color.white.opacity(0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        if isHovering {
            return AnyShapeStyle(.regularMaterial)
        }

        return AnyShapeStyle(.thinMaterial)
    }

    private var borderColor: Color {
        if isActive {
            return Color.accentColor.opacity(0.30)
        }

        return Color.white.opacity(isHovering ? 0.14 : 0.08)
    }
}

private struct SidebarCollapseToggleButton: View {
    let isChinese: Bool
    let motionEnabled: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(
                        colors: isHovering
                            ? [
                                Color.white.opacity(0.16),
                                Color.accentColor.opacity(0.14),
                                Color.white.opacity(0.05),
                            ]
                            : [
                                Color.white.opacity(0.10),
                                Color.accentColor.opacity(0.10),
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(isHovering ? 0.18 : 0.10))
                )
                .background {
                    SidebarHoverGlow(
                        isVisible: isHovering,
                        style: .rounded(10)
                    )
                }
        }
        .buttonStyle(.plain)
        .help(localizedText(isChinese, english: "Collapse sidebar", chinese: "收起侧边栏"))
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(motionEnabled ? .easeOut(duration: 0.18) : nil, value: isHovering)
    }
}

private struct SidebarFooterIcon: View {
    let symbol: String
    let isHovering: Bool
    let motionEnabled: Bool

    var body: some View {
        HoverAnimatedCircleSymbol(
            symbol: symbol,
            font: .system(size: 18, weight: .semibold),
            motionEnabled: motionEnabled,
            isHovering: isHovering
        )
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }
}

private struct SidebarFooterActionIcon: View {
    let symbol: String
    let motionEnabled: Bool

    @State private var isHovering = false

    var body: some View {
        SidebarFooterIcon(symbol: symbol, isHovering: isHovering, motionEnabled: motionEnabled)
            .foregroundStyle(isHovering ? Color.accentColor : Color.secondary)
            .frame(width: 36, height: 36)
            .background(Color.white.opacity(isHovering ? 0.12 : 0.05), in: Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(isHovering ? 0.18 : 0.08), lineWidth: 1)
            )
            .contentShape(Circle())
            .animation(motionEnabled ? .easeOut(duration: 0.18) : nil, value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

private enum HoverAnimatedCircleSymbolKind: Equatable {
    case gearSpin
    case globeSpin
    case helpBounce
    case tiltRight
    case none

    static func forSymbol(_ symbol: String) -> HoverAnimatedCircleSymbolKind {
        switch symbol {
        case "gearshape.fill", "gearshape":
            return .gearSpin
        case "globe":
            return .globeSpin
        case "questionmark.circle", "questionmark.circle.fill":
            return .helpBounce
        case "graduationcap.fill":
            return .tiltRight
        default:
            return .none
        }
    }

    var usesSpin: Bool {
        self == .gearSpin || self == .globeSpin
    }
}

private struct HoverAnimatedCircleSymbol: View {
    let symbol: String
    let font: Font
    let motionEnabled: Bool
    let isHovering: Bool

    @State private var spinCycle = 0
    @State private var feedbackCycle = 0

    private var motionKind: HoverAnimatedCircleSymbolKind {
        HoverAnimatedCircleSymbolKind.forSymbol(symbol)
    }

    private var planarRotationDegrees: Double {
        guard motionEnabled else {
            return 0
        }

        switch motionKind {
        case .gearSpin:
            return Double(spinCycle) * 360
        case .helpBounce:
            return isHovering ? -6 : 0
        case .tiltRight:
            return isHovering ? 7 : 0
        case .globeSpin, .none:
            return 0
        }
    }

    private var depthRotationDegrees: Double {
        guard motionEnabled, motionKind == .globeSpin else {
            return 0
        }
        return Double(spinCycle) * 360
    }

    private var spinAnimation: Animation? {
        guard motionEnabled else {
            return nil
        }

        switch motionKind {
        case .gearSpin:
            return .easeInOut(duration: 0.58)
        case .globeSpin:
            return .easeInOut(duration: 0.72)
        case .helpBounce, .tiltRight, .none:
            return nil
        }
    }

    private var hoverScale: CGFloat {
        guard motionEnabled, isHovering else {
            return 1
        }
        return motionKind == .helpBounce ? 1.1 : 1.06
    }

    var body: some View {
        Image(systemName: symbol)
            .font(font)
            .rotationEffect(.degrees(planarRotationDegrees))
            .rotation3DEffect(
                .degrees(depthRotationDegrees),
                axis: (x: 0, y: 1, z: 0),
                perspective: motionKind == .globeSpin ? 0.44 : 0
            )
            .scaleEffect(hoverScale)
            .symbolEffect(.bounce, value: feedbackCycle)
            .animation(motionEnabled ? .spring(response: 0.22, dampingFraction: 0.72, blendDuration: 0.06) : nil, value: isHovering)
            .animation(spinAnimation, value: spinCycle)
            .onChange(of: isHovering) { _, hovering in
                guard hovering && motionEnabled else {
                    return
                }
                if motionKind.usesSpin {
                    spinCycle += 1
                }
                if motionKind == .helpBounce {
                    feedbackCycle += 1
                }
            }
    }
}

enum SidebarHoverGlowStyle: Equatable {
    case none
    case rounded(CGFloat)
    case circle
}

struct SidebarHoverGlow: View {
    let isVisible: Bool
    let style: SidebarHoverGlowStyle

    private let haloYellow = Color(red: 1.0, green: 0.86, blue: 0.26)
    private let haloBlue = Color(red: 0.23, green: 0.58, blue: 1.0)

    var body: some View {
        Group {
            switch style {
            case .none:
                EmptyView()
            case let .rounded(cornerRadius):
                glow(for: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            case .circle:
                glow(for: Circle())
            }
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: isVisible)
        .allowsHitTesting(false)
    }

    private func glow<S: InsettableShape>(for shape: S) -> some View {
        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            haloYellow.opacity(0.12),
                            haloBlue.opacity(0.10),
                            Color.white.opacity(0.04),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            shape.inset(by: 1)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            haloYellow.opacity(0.10),
                            .clear,
                        ],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 42
                    )
                )

        }
        .clipShape(shape)
    }
}

private struct SidebarHoverTrackingRegion: NSViewRepresentable {
    let isEnabled: Bool
    @Binding var isHovering: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isHovering: $isHovering)
    }

    func makeNSView(context: Context) -> HoverTrackingView {
        let view = HoverTrackingView()
        view.hoverDidChange = context.coordinator.updateHoverState
        view.isTrackingEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: HoverTrackingView, context: Context) {
        nsView.hoverDidChange = context.coordinator.updateHoverState
        nsView.isTrackingEnabled = isEnabled
        nsView.syncHoverState()
    }

    final class Coordinator {
        @Binding private var isHovering: Bool

        init(isHovering: Binding<Bool>) {
            _isHovering = isHovering
        }

        func updateHoverState(_ hovering: Bool) {
            guard isHovering != hovering else {
                return
            }
            isHovering = hovering
        }
    }
}

private final class HoverTrackingView: NSView {
    var hoverDidChange: ((Bool) -> Void)?
    var isTrackingEnabled = true {
        didSet {
            guard oldValue != isTrackingEnabled else {
                return
            }
            refreshTrackingArea()
            syncHoverState()
        }
    }

    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingArea()
    }

    override func layout() {
        super.layout()
        syncHoverState()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncHoverState()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        hoverDidChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoverDidChange?(false)
    }

    func syncHoverState() {
        guard isTrackingEnabled, let window else {
            hoverDidChange?(false)
            return
        }

        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        hoverDidChange?(bounds.insetBy(dx: -0.5, dy: -0.5).contains(location))
    }

    private func refreshTrackingArea() {
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
            self.trackingAreaRef = nil
        }

        guard isTrackingEnabled else {
            return
        }

        let trackingAreaRef = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .inVisibleRect,
                .activeInActiveApp,
                .enabledDuringMouseDrag,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingAreaRef)
        self.trackingAreaRef = trackingAreaRef
    }
}

private struct AppSweepShimmer: View {
    let active: Bool

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [
                    .clear,
                    Color.white.opacity(0.045),
                    Color.accentColor.opacity(0.075),
                    .clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: max(180, proxy.size.width * 0.22))
            .rotationEffect(.degrees(20))
            .blur(radius: 16)
            .offset(x: proxy.size.width * 0.34, y: -proxy.size.height * 0.18)
            .blendMode(.plusLighter)
            .opacity(active ? 1 : 0)
        }
        .allowsHitTesting(false)
    }
}

private struct SessionStageView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdaterController
    @ObservedObject var session: VisiDataSessionController
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var isSessionReady: Bool {
        AppModel.shouldDisplaySessionDetail(
            hasCurrentFile: session.currentFileURL != nil,
            isRunning: session.isRunning,
            hasError: session.errorMessage != nil
        )
    }

    var body: some View {
        Group {
            if isSessionReady {
                SessionDetailView(model: model, session: session)
            } else {
                WelcomeDetailView(model: model, updater: updater)
            }
        }
        .animation(motionEnabled ? .easeInOut(duration: 0.22) : nil, value: isSessionReady)
    }
}

private struct HelpView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var motionEnabled: Bool {
        !accessibilityReduceMotion
    }

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    private var onboardingTips: [QuickTip] {
        [
            QuickTip(
                keys: localizedText(isChinese, english: "Open… / Drag File", chinese: "打开… / 拖拽文件"),
                title: localizedText(isChinese, english: "Open Data", chinese: "打开数据"),
                detail: localizedText(
                    isChinese,
                    english: "Use the toolbar or drag a file into the main window. iData forwards the real file into embedded VisiData.",
                    chinese: "用工具栏打开文件，或直接拖入窗口。iData 会将文件交由内嵌的 VisiData 处理。"
                )
            ),
            QuickTip(
                keys: localizedText(isChinese, english: "Recent + Pin", chinese: "最近文件 + 置顶"),
                title: localizedText(isChinese, english: "Keep Key Files", chinese: "保留关键文件"),
                detail: localizedText(
                    isChinese,
                    english: "Click a recent item to reopen it. Pin important files so they stay fixed at the top of the sidebar.",
                    chinese: "点击最近文件即可重新打开。把重要文件置顶后，它们会固定显示在侧边栏顶部。"
                )
            ),
            QuickTip(
                keys: "⌘,",
                title: localizedText(isChinese, english: "Settings", chinese: "设置"),
                detail: localizedText(
                    isChinese,
                    english: "Adjust the `vd` path, automatic update behavior, or run a manual update check.",
                    chinese: "可以调整 `vd` 路径、自动更新行为，或手动检查更新。"
                )
            ),
        ]
    }

    private var softwareTips: [QuickTip] {
        [
            QuickTip(
                keys: ".csv / .tsv / .ma",
                title: localizedText(isChinese, english: "Direct Open", chinese: "直接打开"),
                detail: localizedText(
                    isChinese,
                    english: "Most regular text-like table files open directly, including unusual bioinformatics suffixes such as `.ma`.",
                    chinese: "大多数常规文本类表格文件都能直接打开，包括 `.ma` 这类生信里常见但不标准的后缀。"
                )
            ),
            QuickTip(
                keys: ".gz / .bgz",
                title: localizedText(isChinese, english: "Stream Compression", chinese: "流式解压"),
                detail: localizedText(
                    isChinese,
                    english: "Compressed files are streamed into VisiData without extracting them to disk first.",
                    chinese: "压缩文件无需先解压，直接流式送入 VisiData 处理。"
                )
            ),
            QuickTip(
                keys: "Excel",
                title: localizedText(isChinese, english: "About `.xlsx`", chinese: "关于 `.xlsx`"),
                detail: localizedText(
                    isChinese,
                    english: "VisiData can read Excel, but that depends on the Python environment having the required loader installed. If Excel fails, install the missing VisiData dependency in the same Python environment as `vd`.",
                    chinese: "VisiData 支持 Excel，但需要 `vd` 所在 Python 环境中安装相应依赖。若 Excel 打不开，请在该环境中补装缺失依赖。"
                )
            ),
        ]
    }

    private var visiDataTips: [QuickTip] {
        [
            QuickTip(keys: "← ↑ ↓ → / h j k l", title: localizedText(isChinese, english: "Move", chinese: "移动"), detail: localizedText(isChinese, english: "Navigate cells and columns without leaving the keyboard.", chinese: "不离开键盘也能在单元格和列之间快速移动。")),
            QuickTip(keys: "/ ? n N", title: localizedText(isChinese, english: "Search", chinese: "搜索"), detail: localizedText(isChinese, english: "Search forward or backward, then jump through matches.", chinese: "支持向前或向后搜索，并在匹配结果间跳转。")),
            QuickTip(keys: "[ ]", title: localizedText(isChinese, english: "Sort", chinese: "排序"), detail: localizedText(isChinese, english: "Sort the current column ascending or descending.", chinese: "对当前列执行升序或降序排序。")),
            QuickTip(keys: "s t u", title: localizedText(isChinese, english: "Select", chinese: "选择"), detail: localizedText(isChinese, english: "Select, toggle, or unselect rows for later commands.", chinese: "选择、切换或取消选择行，供后续命令使用。")),
            QuickTip(keys: "z?", title: localizedText(isChinese, english: "Command Help", chinese: "命令帮助"), detail: localizedText(isChinese, english: "Discover sheet-specific commands and see what VisiData can do on the current data.", chinese: "查看当前数据表可用的专属命令，快速了解 VisiData 还能做什么。")),
            QuickTip(keys: "q", title: localizedText(isChinese, english: "Back / Quit Sheet", chinese: "返回 / 退出表"), detail: localizedText(isChinese, english: "Go back from a derived sheet or quit the session when you are done.", chinese: "从派生表返回上一层，或在完成后退出当前会话。")),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                helpHero
                helpSection(title: localizedText(isChinese, english: "Using iData", chinese: "如何使用 iData"), tips: onboardingTips)
                helpSection(title: localizedText(isChinese, english: "File Loading Notes", chinese: "文件加载说明"), tips: softwareTips)
                helpSection(title: localizedText(isChinese, english: "Common VisiData Shortcuts", chinese: "常用 VisiData 快捷键"), tips: visiDataTips)
            }
            .padding(28)
        }
        .frame(width: 700, height: 620)
        .background(detailBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private func helpSection(title: String, tips: [QuickTip]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            ForEach(tips) { tip in
                HStack(alignment: .top, spacing: 14) {
                    Text(tip.keys)
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .frame(minWidth: 155, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(tip.title)
                            .font(.headline)
                        Text(tip.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
    }

    private var helpHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 20, y: 8)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(localizedText(isChinese, english: "iData Help", chinese: "iData 帮助"))
                            .font(.system(size: 34, weight: .bold, design: .rounded))

                        Spacer(minLength: 0)

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.10), in: Circle())
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                        .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.03, hoverYOffset: -1)
                        .help(localizedText(isChinese, english: "Close Help", chinese: "关闭帮助"))
                        .keyboardShortcut(.cancelAction)
                    }

                    Text(localizedText(
                        isChinese,
                        english: "iData is a native macOS shell around real VisiData. The outer app handles opening files, history, updates, and settings; the main table view remains genuine VisiData, so normal VisiData commands still apply inside the session.",
                        chinese: "iData 是 VisiData 的原生 macOS 封装。外层负责文件管理、历史记录、更新与设置；主表格区域运行的是真正的 VisiData，你熟悉的所有命令依然有效。"
                    ))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        StatusPill(title: localizedText(isChinese, english: "Native macOS shell", chinese: "原生 macOS 界面"), tint: .white.opacity(0.12), icon: "macwindow")
                        StatusPill(title: localizedText(isChinese, english: "Real VisiData core", chinese: "VisiData 驱动"), tint: Color.accentColor.opacity(0.20), icon: "terminal")
                    }
                }
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    Color.white.opacity(0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10))
        )
        .shadow(color: .black.opacity(0.10), radius: 26, y: 10)
    }
}

private struct TutorialHubView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                ForEach(model.tutorialChapters, id: \.id) { chapter in
                    chapterCard(chapter)
                }
            }
            .padding(28)
        }
        .frame(width: 760, height: 640)
        .background(
            ZStack {
                detailBackground
                RadialGradient(
                    colors: [
                        Color.accentColor.opacity(0.22),
                        Color.clear,
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 380
                )
            }
            .ignoresSafeArea()
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isChinese ? "教程清单" : "Tutorial Checklist")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text(isChinese ? "选择一个章节开始练习。每次开始都会从第 1 步进入，完成的章节会自动打勾。" : "Choose a chapter to practice. Each launch starts from Step 1, and completed chapters remain checked.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                StatusPill(
                    title: isChinese ? "示例数据驱动" : "Sample-data driven",
                    tint: .white.opacity(0.12),
                    icon: "tablecells"
                )
                StatusPill(
                    title: model.appLanguageBadgeText,
                    tint: Color.accentColor.opacity(0.22),
                    icon: "character.book.closed"
                )
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12))
        )
        .shadow(color: .black.opacity(0.14), radius: 22, y: 8)
    }

    @ViewBuilder
    private func chapterCard(_ chapter: AppModel.TutorialChapter) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: chapter.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(chapter.title)
                            .font(.headline)

                        if chapter.isCompleted {
                            Label(isChinese ? "已完成" : "Completed", systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.22), in: Capsule())
                        }
                    }

                    Text(chapter.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(chapter.isCompleted ? (isChinese ? "再练一遍" : "Practice Again") : (isChinese ? "开始" : "Start")) {
                    model.startTutorial(chapterID: chapter.id)
                }
                .buttonStyle(.borderedProminent)
                .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.01, hoverYOffset: -1)
            }

            VStack(spacing: 7) {
                ForEach(chapter.steps, id: \.id) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: step.index < chapter.completedStepCount ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(step.index < chapter.completedStepCount ? Color.green : Color.secondary.opacity(0.6))
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.subheadline.weight(.semibold))
                            Text(step.command)
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10))
        )
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }
}

private struct WelcomeDetailView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdaterController
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var customAssociationInput = ""
    @State private var tutorialPreviewChapterIndex: Int = 0
    @State private var tutorialCarouselTimer: Timer?

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var currentPreviewChapter: AppModel.TutorialChapter? {
        let chapters = model.tutorialChapters
        guard !chapters.isEmpty else { return nil }
        let index = tutorialPreviewChapterIndex % chapters.count
        return chapters[index]
    }

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    private var showsFirstRunEmptyState: Bool {
        model.recentFiles.isEmpty && model.lastOpenedFile == nil
    }

    private var quickTips: [QuickTip] {
        [
            QuickTip(keys: "← ↑ ↓ → / h j k l", title: localizedText(isChinese, english: "Move", chinese: "移动"), detail: localizedText(isChinese, english: "Navigate rows and columns quickly without leaving the keyboard.", chinese: "不离开键盘也能快速移动行和列。")),
            QuickTip(keys: "/ ? n N", title: localizedText(isChinese, english: "Search", chinese: "搜索"), detail: localizedText(isChinese, english: "Search forward or backward in the current sheet, then jump to next or previous match.", chinese: "在当前工作表中向前或向后搜索，然后跳到下一个或上一个匹配项。")),
            QuickTip(keys: "s t u", title: localizedText(isChinese, english: "Select Rows", chinese: "选择行"), detail: localizedText(isChinese, english: "Select, toggle, or unselect rows before profiling or exporting.", chinese: "在统计分析或导出之前，先选择、切换或取消选择行。")),
            QuickTip(keys: "[ ]", title: localizedText(isChinese, english: "Sort", chinese: "排序"), detail: localizedText(isChinese, english: "Sort the current column ascending or descending.", chinese: "对当前列执行升序或降序排序。")),
            QuickTip(keys: "Ctrl + H", title: localizedText(isChinese, english: "Help", chinese: "帮助"), detail: localizedText(isChinese, english: "Open the command and help menu to discover any VisiData action.", chinese: "打开命令与帮助菜单，查看 VisiData 的可用操作。"))
        ]
    }

    private var normalizedCustomAssociationExtension: String {
        AppModel.associationExtension(for: customAssociationInput)
    }

    private var canSubmitCustomAssociation: Bool {
        AppModel.canSetAssociationExtensionInput(customAssociationInput) && !model.isSettingFormatDefault
    }

    private var isSettingCustomAssociation: Bool {
        guard model.isSettingFormatDefault else {
            return false
        }
        return AppModel.associationExtension(for: model.settingFormatExtension ?? "") == normalizedCustomAssociationExtension
            && !normalizedCustomAssociationExtension.isEmpty
    }

    private var isCustomAssociationDefault: Bool {
        guard !normalizedCustomAssociationExtension.isEmpty else {
            return false
        }
        return model.formatAssociationStatus[normalizedCustomAssociationExtension]
            ?? model.checkFormatAssociation(forExtension: normalizedCustomAssociationExtension)
    }

    private var customAssociationActionTitle: String {
        if isCustomAssociationDefault {
            return localizedText(isChinese, english: "Restore Previous Default", chinese: "恢复之前默认应用")
        }
        return localizedText(isChinese, english: "Set Default to iData", chinese: "设为 iData 默认打开")
    }

    private var customAssociationActionIcon: String {
        isCustomAssociationDefault ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill"
    }

    private var displayedFormatExtensions: [String] {
        AppModel.formatPanelFormats.map(\.fileExtension)
    }

    private var orderedSupportedFormats: [(format: AppModel.SupportedFormat, isDefault: Bool)] {
        let snapshot = AppModel.formatPanelFormats.enumerated().map { index, format in
            let lookupExtension = AppModel.associationExtension(for: format.fileExtension)
            let isDefault = model.formatAssociationStatus[lookupExtension]
                ?? model.formatAssociationStatus[format.fileExtension]
                ?? false
            return (index: index, format: format, isDefault: isDefault)
        }

        return snapshot.map { (format: $0.format, isDefault: $0.isDefault) }
    }

    private func refreshDisplayedFormatAssociationStatus() {
        model.refreshFormatAssociationStatuses(forExtensions: displayedFormatExtensions)
    }

    private let repositoryURL = URL(string: "https://github.com/laleoarrow/iData")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heroCard
                if showsFirstRunEmptyState {
                    firstRunEmptyStateCard
                }
                quickTipsCard
                tutorialEntryCard
                systemStatusSection
                formatsCard

                if let errorMessage = model.errorMessage {
                    MessageCard(
                        title: localizedText(isChinese, english: "Launch Error", chinese: "启动错误"),
                        message: errorMessage,
                        color: .red.opacity(0.14)
                    )
                } else if let statusMessage = model.statusMessage {
                    MessageCard(
                        title: localizedText(isChinese, english: "Status", chinese: "状态"),
                        message: statusMessage,
                        color: .green.opacity(0.14)
                    )
                }
            }
            .padding(28)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: 18, y: 8)

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
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if showsHeroMetadataRow {
                        HStack(spacing: 10) {
                            if case .missing = model.visiDataDependencyState {
                                dependencyPill
                            }

                            if let lastOpenedFile = model.lastOpenedFile {
                                StatusPill(title: isChinese ? "最近打开: \(lastOpenedFile.lastPathComponent)" : "Last: \(lastOpenedFile.lastPathComponent)", tint: .white.opacity(0.10))
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    model.openDocument()
                } label: {
                    Label(isChinese ? "打开文件" : "Open File", systemImage: "tablecells")
                }
                .buttonStyle(.borderedProminent)
                .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.012, hoverYOffset: -1.5)

                if case .missing = model.visiDataDependencyState {
                    Button {
                        model.runVisiDataOneClickSetup()
                    } label: {
                        Label(isChinese ? "安装 VisiData" : "Install VisiData", systemImage: "shippingbox")
                    }
                    .buttonStyle(.borderedProminent)
                    .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.012, hoverYOffset: -1.5)
                }

                Button {
                    model.presentTutorialHub()
                } label: {
                    Label(isChinese ? "开始教程" : "Start Tutorial", systemImage: "graduationcap.fill")
                }
                .buttonStyle(.bordered)
                .quietInteractiveSurface(enabled: motionEnabled)

                Button {
                    updater.checkForUpdates()
                } label: {
                    Label(isChinese ? "检查更新" : "Check for Updates", systemImage: "arrow.trianglehead.clockwise")
                }
                .buttonStyle(.bordered)
                .quietInteractiveSurface(enabled: motionEnabled)

                SettingsLink {
                    Label(isChinese ? "偏好设置" : "Preferences", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .quietInteractiveSurface(enabled: motionEnabled)

                if let fileURL = model.lastOpenedFile {
                    Button {
                        model.revealInFinder(fileURL)
                    } label: {
                        Label(isChinese ? "所在位置" : "Show Last File", systemImage: "finder")
                    }
                    .buttonStyle(.bordered)
                    .quietInteractiveSurface(enabled: motionEnabled)
                }

                Link(destination: repositoryURL) {
                    Label("GitHub", systemImage: "link")
                }
                .buttonStyle(.bordered)
                .quietInteractiveSurface(enabled: motionEnabled)
                .help(isChinese ? "如果你喜欢 iData 就给个 Star 吧 ✨" : "Give a star if you like iData ✨")
            }

            Text(isChinese ? "提示: 拖拽支持的表格文件到此窗口可直接打开。" : "Tip: drag a supported table file into this window to open it directly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(isChinese ? "大多数数据文件会交由引擎直接处理。原生支持读取 `.gz` / `.bgz` 等压缩流，无需预先解压。" : "Most data files are delegated to the underlying engine. Compressed `.gz` / `.bgz` files are streamed natively without extracting.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    Color.white.opacity(0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10))
        )
        .shadow(color: .black.opacity(0.10), radius: 26, y: 10)
    }

    private var firstRunEmptyStateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "tablecells")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedText(isChinese, english: "Start with a table", chinese: "先打开一份数据"))
                        .font(.headline)
                    Text(localizedText(
                        isChinese,
                        english: "Choose the path that matches this file: inspect it in iData, learn with a sample, or review small-file handoff.",
                        chinese: "按文件目的选择下一步：在 iData 中查看、用示例练习，或确认小文件转交设置。"
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    firstRunActionButton(
                        title: localizedText(isChinese, english: "Open First Table", chinese: "打开第一份表格"),
                        symbol: "tablecells",
                        prominent: true,
                        action: { model.openDocument() }
                    )

                    firstRunActionButton(
                        title: localizedText(isChinese, english: "Try Sample Tutorial", chinese: "试用示例教程"),
                        symbol: "graduationcap.fill",
                        prominent: false,
                        action: { model.presentTutorialHub() }
                    )

                    SettingsLink {
                        Label(localizedText(isChinese, english: "Review Handoff Settings", chinese: "查看转交设置"), systemImage: "arrow.triangle.branch")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .quietInteractiveSurface(enabled: motionEnabled)
                }

                VStack(alignment: .leading, spacing: 10) {
                    firstRunActionButton(
                        title: localizedText(isChinese, english: "Open First Table", chinese: "打开第一份表格"),
                        symbol: "tablecells",
                        prominent: true,
                        action: { model.openDocument() }
                    )

                    firstRunActionButton(
                        title: localizedText(isChinese, english: "Try Sample Tutorial", chinese: "试用示例教程"),
                        symbol: "graduationcap.fill",
                        prominent: false,
                        action: { model.presentTutorialHub() }
                    )

                    SettingsLink {
                        Label(localizedText(isChinese, english: "Review Handoff Settings", chinese: "查看转交设置"), systemImage: "arrow.triangle.branch")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .quietInteractiveSurface(enabled: motionEnabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private func firstRunActionButton(
        title: String,
        symbol: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(action: action) {
                Label(title, systemImage: symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .quietInteractiveSurface(enabled: motionEnabled)
        } else {
            Button(action: action) {
                Label(title, systemImage: symbol)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .quietInteractiveSurface(enabled: motionEnabled)
        }
    }

    private var showsReadyDependencyPillInTitleRow: Bool {
        if case .available = model.visiDataDependencyState {
            return true
        }

        return false
    }

    private var showsHeroMetadataRow: Bool {
        if case .missing = model.visiDataDependencyState {
            return true
        }

        return model.lastOpenedFile != nil
    }

    private var tutorialEntryCard: some View {
        let chapters = model.tutorialChapters
        let chapter = currentPreviewChapter

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(isChinese ? "交互式教程" : "Interactive Tutorial")
                        .font(.headline)

                    Text(isChinese ? "用示例数据学习 VisiData，并在会话内跟随引导完成练习。" : "Learn VisiData with a sample dataset and a guided in-session coach.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    model.presentTutorialHub()
                } label: {
                    Label(isChinese ? "开始" : "Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.accentColor)
                .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.012, hoverYOffset: -1)
            }

            if let chapter {
                // Chapter sub-header
                HStack(spacing: 8) {
                    Image(systemName: chapter.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(chapter.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .id(chapter.id + "-header")
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                VStack(spacing: 9) {
                    ForEach(Array(chapter.steps.prefix(4)), id: \.id) { step in
                        tutorialPreviewRow(step)
                    }
                }
                .id(chapter.id + "-steps")
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }

            // Page indicator dots
            if chapters.count > 1 {
                HStack(spacing: 6) {
                    Spacer()
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { index, _ in
                        Circle()
                            .fill(Color.white.opacity(index == (tutorialPreviewChapterIndex % chapters.count) ? 0.8 : 0.25))
                            .frame(width: 6, height: 6)
                            .scaleEffect(index == (tutorialPreviewChapterIndex % chapters.count) ? 1.15 : 1)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    tutorialPreviewChapterIndex = index
                                }
                                restartCarouselTimer()
                            }
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .animation(.easeInOut(duration: 0.4), value: tutorialPreviewChapterIndex)
        .onAppear { startCarouselTimer() }
        .onDisappear { tutorialCarouselTimer?.invalidate() }
    }

    private func startCarouselTimer() {
        tutorialCarouselTimer?.invalidate()
        tutorialCarouselTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { _ in
            Task { @MainActor in
                let chapters = model.tutorialChapters
                guard chapters.count > 1 else { return }
                tutorialPreviewChapterIndex = (tutorialPreviewChapterIndex + 1) % chapters.count
            }
        }
    }

    private func restartCarouselTimer() {
        startCarouselTimer()
    }

    @ViewBuilder
    private func tutorialPreviewRow(_ step: AppModel.TutorialStep) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(step.index + 1)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.22), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                Text(step.command)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dependencyPill: some View {
        switch model.visiDataDependencyState {
        case .available:
            return AnyView(StatusPill(title: localizedText(isChinese, english: "VisiData Ready", chinese: "VisiData 已就绪"), tint: .green.opacity(0.20), icon: "checkmark.circle.fill"))
        case .missing:
            return AnyView(StatusPill(title: localizedText(isChinese, english: "Install VisiData", chinese: "安装 VisiData"), tint: .orange.opacity(0.22), icon: "exclamationmark.triangle.fill"))
        }
    }

    private var systemStatusSection: some View {
        let runtimeDetail = localizedText(
            isChinese,
            english: "\(model.visiDataDependencySummary) Automatic format detection enabled. Compressed .gz/.bgz streams are natively supported.",
            chinese: "\(model.visiDataDependencySummary) 格式自动识别已启用，且原生支持读取 .gz / .bgz 等各类压缩数据流。"
        )

        return VStack(alignment: .leading, spacing: 20) {
            Text(localizedText(isChinese, english: "System Status", chinese: "系统状态"))
                .font(.title3.weight(.semibold))

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 36) {
                    systemStatusItem(
                        title: localizedText(isChinese, english: "Runtime", chinese: "运行环境"),
                        icon: "terminal",
                        detail: runtimeDetail
                    )

                    Divider()
                        .padding(.vertical, 6)

                    systemStatusItem(
                        title: localizedText(isChinese, english: "Updates", chinese: "更新"),
                        icon: "arrow.triangle.2.circlepath",
                        detail: updater.statusMessage
                    )
                }
                .frame(minHeight: 104, alignment: .top)

                VStack(alignment: .leading, spacing: 18) {
                    systemStatusItem(
                        title: localizedText(isChinese, english: "Runtime", chinese: "运行环境"),
                        icon: "terminal",
                        detail: runtimeDetail
                    )

                    Divider()

                    systemStatusItem(
                        title: localizedText(isChinese, english: "Updates", chinese: "更新"),
                        icon: "arrow.triangle.2.circlepath",
                        detail: updater.statusMessage
                    )
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func systemStatusItem(title: String, icon: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickTipsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(localizedText(isChinese, english: "VisiData Quick Start", chinese: "VisiData 快速上手"))
                        .font(.headline)

                    Text(localizedText(
                        isChinese,
                        english: "These are common starter shortcuts. All normal VisiData commands still work inside the embedded session.",
                        chinese: "这里列出的是常见入门快捷键。内嵌会话里其余标准 VisiData 命令仍然都可以正常使用。"
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 9) {
                ForEach(quickTips) { tip in
                    quickTipPreviewRow(tip)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.20),
                    Color.white.opacity(0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10))
        )
    }

    @ViewBuilder
    private func quickTipPreviewRow(_ tip: QuickTip) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(tip.keys)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08), in: Capsule())
                .frame(minWidth: 155, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(tip.title)
                    .font(.subheadline.weight(.semibold))
                Text(tip.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var formatsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(localizedText(isChinese, english: "Supported Formats", chinese: "支持的格式"))
                    .font(.headline)
                
                Button {
                    refreshDisplayedFormatAssociationStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(6)
                        .background(Color.accentColor.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help(localizedText(isChinese, english: "Refresh system defaults", chinese: "从系统刷新默认设置状态"))
                
                Spacer()
                
                SettingsLink {
                    Label(localizedText(isChinese, english: "Handoff Rules", chinese: "设置转交规则"), systemImage: "gearshape.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.accentColor)
                .quietInteractiveSurface(enabled: motionEnabled)
            }

            Text(localizedText(
                isChinese,
                english: "A concise set of common formats is shown below. iData still forwards most regular files directly to VisiData.",
                chinese: "下面仅展示常见格式的精简集合。iData 仍会把大多数常规文件直接转交给 VisiData。"
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(localizedText(
                isChinese,
                english: "Tap a chip to toggle default handling: set iData, then tap again to restore another app.",
                chinese: "点击格式卡片可切换默认处理：先设为 iData，再点一次恢复到其他应用。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(orderedSupportedFormats, id: \.format.fileExtension) { entry in
                    FormatChip(
                        title: entry.format.localizedDisplayName(for: model.effectiveLanguage),
                        extensionText: entry.format.fileExtension,
                        isDefault: entry.isDefault,
                        isLoading: model.isSettingFormatDefault && model.settingFormatExtension == entry.format.fileExtension,
                        isChinese: isChinese,
                        onTap: {
                            model.setFormatAsDefault(forExtension: entry.format.fileExtension)
                        }
                    )
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 10) {
                Text(localizedText(isChinese, english: "Custom Suffix", chinese: "自定义后缀"))
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 10) {
                    TextField(".vcf / vcf / my.ext", text: $customAssociationInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.subheadline, design: .monospaced))
                        .autocorrectionDisabled()
                        .onSubmit {
                            if canSubmitCustomAssociation {
                                model.setFormatAsDefault(forExtension: customAssociationInput)
                            }
                        }

                    Button {
                        model.setFormatAsDefault(forExtension: customAssociationInput)
                    } label: {
                        Label(customAssociationActionTitle, systemImage: customAssociationActionIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(.accentColor)
                    .disabled(!canSubmitCustomAssociation)
                    .quietInteractiveSurface(enabled: motionEnabled)
                }

                if !normalizedCustomAssociationExtension.isEmpty {
                    HStack(spacing: 8) {
                        Text(localizedText(
                            isChinese,
                            english: "Suffix: .\(normalizedCustomAssociationExtension)",
                            chinese: "后缀：.\(normalizedCustomAssociationExtension)"
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if isSettingCustomAssociation {
                            ProgressView()
                                .controlSize(.small)
                            Text(localizedText(isChinese, english: "Setting...", chinese: "正在设置..."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if isCustomAssociationDefault {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text(localizedText(isChinese, english: "Default: iData", chinese: "默认应用：iData"))
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                } else {
                    Text(localizedText(
                        isChinese,
                        english: "Enter a suffix to set its default handler to iData.",
                        chinese: "输入一个后缀，把它的默认打开方式设为 iData。"
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear {
            refreshDisplayedFormatAssociationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshDisplayedFormatAssociationStatus()
        }
        .onChange(of: normalizedCustomAssociationExtension) { _, newValue in
            guard !newValue.isEmpty else {
                return
            }
            model.refreshFormatAssociationStatuses(forExtensions: [newValue])
        }
    }
}

private struct SessionDetailView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var session: VisiDataSessionController
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @StateObject private var inputSourceMonitor = InputSourceMonitor()
    @State private var sessionInfoHintIndex = 0
    @State private var isSessionInfoHintDismissed = false

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    private var shouldShowSessionInfoHint: Bool {
        !model.isTutorialActive
            && session.currentFileURL != nil
            && !sessionInfoHint.isEmpty
            && !isSessionInfoHintDismissed
    }

    private var sessionInfoHint: String {
        let pool = sessionInfoHints
        guard !pool.isEmpty else {
            return ""
        }
        return pool[wrappedSessionInfoHintIndex(in: pool)]
    }

    private var sessionInfoHints: [String] {
        if isChinese {
            return [
                "先按 z，再按 ?。这不是组合键。",
                "搜索后按 Enter；再用 n/N 看下一个结果。",
                "方向键和 hjkl 都能移动，用顺手的就行。",
                "当前列排序：] 升序，[ 降序。",
                "不确定快捷键时，先打开教程看一眼。",
            ]
        }

        return [
            "Tip: `z?` is sequential, press `z` then `?`, not simultaneously.",
            "Tip: After `/` search input, press Enter once, then use `n` / `N`.",
            "Tip: Arrow keys and `h j k l` both work for movement.",
            "Tip: Sort current column with `]` (asc) and `[` (desc).",
            "Tip: Replaying the tutorial checklist is the fastest way to build muscle memory.",
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sessionHeader
            .animation(motionEnabled ? .easeOut(duration: 0.22) : nil, value: shouldShowSessionInfoHint)

            ZStack(alignment: .topTrailing) {
                EmbeddedTerminalView(session: session)
                    .id(ObjectIdentifier(session))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08))
                    )
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 8)

                if shouldShowSessionInfoHint {
                    SessionInfoHintPanel(
                        isChinese: isChinese,
                        message: sessionInfoHint,
                        motionEnabled: motionEnabled,
                        canCycle: sessionInfoHints.count > 1,
                        onPrevious: { moveSessionHint(by: -1) },
                        onNext: { moveSessionHint(by: 1) },
                        onDismiss: { isSessionInfoHintDismissed = true }
                    )
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if model.isTutorialActive, model.tutorialCurrentStep != nil {
                    TutorialCoachOverlay(model: model)
                        .padding(.top, 62)
                        .padding(.trailing, 16)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(motionEnabled ? .spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12) : nil, value: model.isTutorialActive)
            .animation(motionEnabled ? .spring(response: 0.32, dampingFraction: 0.88, blendDuration: 0.12) : nil, value: shouldShowSessionInfoHint)

            if let errorMessage = model.errorMessage {
                MessageCard(
                    title: localizedText(isChinese, english: "Launch Error", chinese: "启动错误"),
                    message: errorMessage,
                    color: .red.opacity(0.12)
                )
            } else if let errorMessage = session.errorMessage {
                MessageCard(
                    title: localizedText(isChinese, english: "Session Error", chinese: "会话错误"),
                    message: errorMessage,
                    color: .red.opacity(0.12)
                )
            } else if let statusMessage = session.statusMessage ?? model.statusMessage {
                StatusAndInputCard(
                    isChinese: isChinese,
                    statusMessage: statusMessage,
                    inputDisplayName: inputSourceMonitor.displayName,
                    isLikelyEnglish: inputSourceMonitor.isLikelyEnglish,
                    onSwitchToEnglish: {
                        _ = inputSourceMonitor.switchToEnglishInputSource()
                    }
                )
                .frame(maxWidth: .infinity)
                .id("\(statusMessage)-\(inputSourceMonitor.displayName)-\(inputSourceMonitor.isLikelyEnglish)")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            refreshSessionHint()
        }
        .onChange(of: session.currentFileURL?.path) { _, _ in
            refreshSessionHint()
        }
        .onChange(of: isChinese) { _, _ in
            refreshSessionHint()
        }
    }

    private func refreshSessionHint() {
        isSessionInfoHintDismissed = false
        pickRandomSessionHint()
    }

    private func pickRandomSessionHint() {
        let pool = sessionInfoHints
        guard !pool.isEmpty else {
            sessionInfoHintIndex = 0
            return
        }

        if pool.count == 1 {
            sessionInfoHintIndex = 0
            return
        }

        let currentIndex = wrappedSessionInfoHintIndex(in: pool)
        let nextIndex = pool.indices.randomElement() ?? 0
        if nextIndex == currentIndex, let alternativeIndex = pool.indices.first(where: { $0 != currentIndex }) {
            sessionInfoHintIndex = alternativeIndex
        } else {
            sessionInfoHintIndex = nextIndex
        }
    }

    private func moveSessionHint(by offset: Int) {
        let pool = sessionInfoHints
        guard !pool.isEmpty else {
            sessionInfoHintIndex = 0
            return
        }

        let currentIndex = wrappedSessionInfoHintIndex(in: pool)
        sessionInfoHintIndex = (currentIndex + offset + pool.count) % pool.count
        isSessionInfoHintDismissed = false
    }

    private func wrappedSessionInfoHintIndex(in pool: [String]) -> Int {
        guard !pool.isEmpty else {
            return 0
        }
        return ((sessionInfoHintIndex % pool.count) + pool.count) % pool.count
    }

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(session.currentFileURL?.lastPathComponent ?? localizedText(isChinese, english: "VisiData Session", chinese: "VisiData 会话"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let fileURL = session.currentFileURL {
                    SessionHeaderActions(
                        isChinese: isChinese,
                        fileURL: fileURL,
                        canReopen: model.lastOpenedFile != nil,
                        motionEnabled: motionEnabled,
                        openAction: { model.openDocument() },
                        reopenAction: { model.reopenLastFile() },
                        revealAction: { model.revealInFinder(fileURL) },
                        copyAction: { model.copyPathToPasteboard(fileURL) }
                    )
                    .layoutPriority(1)
                }
            }

            sessionPathLabel
        }
    }

    private var sessionPathLabel: some View {
        Text(session.currentFileURL?.path ?? localizedText(isChinese, english: "No file loaded", chinese: "尚未加载文件"))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

}

private struct SessionHeaderActions: View {
    let isChinese: Bool
    let fileURL: URL
    let canReopen: Bool
    let motionEnabled: Bool
    let openAction: () -> Void
    let reopenAction: () -> Void
    let revealAction: () -> Void
    let copyAction: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                headerActionButton(
                    title: localizedText(isChinese, english: "Open…", chinese: "打开…"),
                    systemImage: "folder",
                    action: openAction
                )
                .keyboardShortcut("o")

                headerActionButton(
                    title: localizedText(isChinese, english: "Reopen", chinese: "重新打开"),
                    systemImage: "arrow.clockwise",
                    action: reopenAction
                )
                .disabled(!canReopen)

                headerActionButton(
                    title: localizedText(isChinese, english: "Show in Finder", chinese: "在 Finder 中显示"),
                    systemImage: "finder",
                    action: revealAction
                )

                headerActionButton(
                    title: localizedText(isChinese, english: "Copy Path", chinese: "复制路径"),
                    systemImage: "doc.on.doc",
                    action: copyAction
                )
            }
            .fixedSize(horizontal: true, vertical: false)

            Menu {
                Button {
                    openAction()
                } label: {
                    Label(localizedText(isChinese, english: "Open…", chinese: "打开…"), systemImage: "folder")
                }
                .keyboardShortcut("o")

                Button {
                    reopenAction()
                } label: {
                    Label(localizedText(isChinese, english: "Reopen", chinese: "重新打开"), systemImage: "arrow.clockwise")
                }
                .disabled(!canReopen)

                Divider()

                Button {
                    revealAction()
                } label: {
                    Label(localizedText(isChinese, english: "Show in Finder", chinese: "在 Finder 中显示"), systemImage: "finder")
                }

                Button {
                    copyAction()
                } label: {
                    Label(localizedText(isChinese, english: "Copy Path", chinese: "复制路径"), systemImage: "doc.on.doc")
                }
            } label: {
                Label(localizedText(isChinese, english: "Actions", chinese: "操作"), systemImage: "ellipsis.circle")
            }
            .buttonStyle(.bordered)
            .help(localizedText(
                isChinese,
                english: "Actions for \(fileURL.lastPathComponent)",
                chinese: "\(fileURL.lastPathComponent) 的操作"
            ))
        }
    }

    private func headerActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .quietInteractiveSurface(enabled: motionEnabled)
    }
}

func statusPanelUsesRunningTint(for statusMessage: String) -> Bool {
    let normalized = statusMessage.lowercased()
    return normalized.contains("running visidata")
        || normalized.contains("正在用 visidata")
        || normalized.contains("正在运行 visidata")
        || normalized.contains("运行 visidata")
}

private struct ExternalHandoffNoticeBanner: View {
    let isChinese: Bool
    let notice: AppModel.ExternalHandoffNotice
    let motionEnabled: Bool
    let onReturn: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false

    private var title: String {
        switch notice.state {
        case .opening:
            return localizedText(
                isChinese,
                english: "Opening in \(notice.applicationName)",
                chinese: "正在用 \(notice.applicationName) 打开"
            )
        case .opened:
            return localizedText(
                isChinese,
                english: "Opened in \(notice.applicationName)",
                chinese: "已用 \(notice.applicationName) 打开"
            )
        case .failed:
            return localizedText(
                isChinese,
                english: "\(notice.applicationName) did not respond",
                chinese: "\(notice.applicationName) 没有响应"
            )
        }
    }

    private var detail: String {
        switch notice.state {
        case .opening:
            return localizedText(
                isChinese,
                english: "\(notice.fileURL.lastPathComponent) is being handed off. You can still open it in iData.",
                chinese: "\(notice.fileURL.lastPathComponent) 正在转交。你仍可改用 iData 打开。"
            )
        case .opened:
            return localizedText(
                isChinese,
                english: "\(notice.fileURL.lastPathComponent) is with \(notice.applicationName). Open in iData to continue analysis.",
                chinese: "\(notice.fileURL.lastPathComponent) 已交给 \(notice.applicationName)。需要继续分析时可改用 iData 打开。"
            )
        case .failed:
            return localizedText(
                isChinese,
                english: "Open \(notice.fileURL.lastPathComponent) in iData or choose another app in Settings.",
                chinese: "可在 iData 中打开 \(notice.fileURL.lastPathComponent)，或到设置中选择其他应用。"
            )
        }
    }

    private var iconName: String {
        switch notice.state {
        case .opening:
            return "arrowshape.turn.up.right.fill"
        case .opened:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconTint: Color {
        switch notice.state {
        case .opening:
            return Color.accentColor
        case .opened:
            return Color.green
        case .failed:
            return Color.yellow
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 36, height: 36)
                .background(iconTint.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onReturn()
            } label: {
                Label(localizedText(isChinese, english: "Open in iData", chinese: "用 iData 打开"), systemImage: "arrow.uturn.backward.circle.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help(localizedText(isChinese, english: "Open this file in iData", chinese: "在 iData 中打开此文件"))

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help(localizedText(isChinese, english: "Dismiss", chinese: "关闭提示"))
        }
        .padding(12)
        .frame(width: 420, alignment: .leading)
        .background {
            ZStack {
                Color.clear.background(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.accentColor.opacity(0.14),
                        Color.black.opacity(0.04),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(isHovering ? 0.24 : 0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 22, y: 8)
        .shadow(color: Color.accentColor.opacity(isHovering ? 0.18 : 0.08), radius: 28, y: 0)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(motionEnabled ? .easeOut(duration: 0.18) : nil, value: isHovering)
    }
}

private struct StatusAndInputCard: View {
    let isChinese: Bool
    let statusMessage: String
    let inputDisplayName: String
    let isLikelyEnglish: Bool
    let onSwitchToEnglish: () -> Void

    @State private var isHovering = false

    private var statusBadgeTitle: String {
        if isLikelyEnglish {
            return isChinese ? "英文" : "English"
        }
        return isChinese ? "非英文" : "Not English"
    }

    private var statusBadgeIcon: String {
        isLikelyEnglish ? "a.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var statusBadgeTint: Color {
        isLikelyEnglish ? Color.green.opacity(0.24) : Color.yellow.opacity(0.24)
    }

    private var cardTint: Color {
        statusPanelUsesRunningTint(for: statusMessage) ? Color.green.opacity(0.09) : Color.white.opacity(0.06)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(isChinese ? "状态" : "Status")
                    .font(.subheadline.weight(.semibold))

                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                StatusPill(
                    title: statusBadgeTitle,
                    tint: statusBadgeTint,
                    icon: statusBadgeIcon
                )

                Text(inputDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 220, alignment: .trailing)
            }

            InputMethodQuickSwitchOrbButton(
                isChinese: isChinese,
                onTap: onSwitchToEnglish
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                cardTint
                LinearGradient(
                    colors: [
                        Color.white.opacity(isHovering ? 0.07 : 0.05),
                        Color.accentColor.opacity(isHovering ? 0.08 : 0),
                        Color.black.opacity(0.04),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(isHovering ? 0.16 : 0.10), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .animation(.easeOut(duration: 0.18), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct OrbButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.25 : 0))
            }
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct InputMethodQuickSwitchOrbButton: View {
    let isChinese: Bool
    let onTap: () -> Void

    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isHovering = false

    private var motionEnabled: Bool {
        idataAnimationsEnabled && !accessibilityReduceMotion
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            HoverAnimatedCircleSymbol(
                symbol: "globe",
                font: .system(size: 16, weight: .semibold),
                motionEnabled: motionEnabled,
                isHovering: isHovering
            )
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: 42, height: 42)
                .background(
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.26),
                                        Color.white.opacity(0.05),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Circle()
                            .inset(by: 1)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.86, blue: 0.26).opacity(0.18),
                                        Color(red: 0.23, green: 0.58, blue: 1.0).opacity(0.16),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .opacity(isHovering ? 1 : 0)
                    }
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.44),
                                    Color.white.opacity(0.10),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .overlay {
                    Circle()
                        .inset(by: 1)
                        .strokeBorder(Color.white.opacity(isHovering ? 0.22 : 0), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 12, y: 3)
        }
        .buttonStyle(OrbButtonStyle())
        .help(isChinese ? "切换到英文输入法" : "Switch to English input")
        .animation(motionEnabled ? .easeOut(duration: 0.18) : nil, value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct SessionInfoHintPanel: View {
    let isChinese: Bool
    let message: String
    let motionEnabled: Bool
    let canCycle: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedText(isChinese, english: "VisiData shortcut tip", chinese: "VisiData 快捷键提示"))
                    .font(.headline)
                    .lineLimit(1)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                SessionHintControlButton(
                    systemImage: "chevron.up",
                    helpText: localizedText(isChinese, english: "Previous tip", chinese: "上一条提示"),
                    motionEnabled: motionEnabled,
                    action: onPrevious
                )
                .disabled(!canCycle)

                SessionHintControlButton(
                    systemImage: "chevron.down",
                    helpText: localizedText(isChinese, english: "Next tip", chinese: "下一条提示"),
                    motionEnabled: motionEnabled,
                    action: onNext
                )
                .disabled(!canCycle)
            }

            SessionHintControlButton(
                systemImage: "xmark",
                helpText: localizedText(isChinese, english: "Dismiss", chinese: "关闭提示"),
                motionEnabled: motionEnabled,
                hoverTint: Color.red.opacity(0.72),
                action: onDismiss
            )
        }
        .padding(12)
        .frame(width: 440, alignment: .leading)
        .background {
            ZStack {
                Color.clear.background(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.accentColor.opacity(0.12),
                        Color.black.opacity(0.04),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(isHovering ? 0.22 : 0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
        .shadow(color: Color.accentColor.opacity(isHovering ? 0.16 : 0.06), radius: 24, y: 0)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(motionEnabled ? .easeOut(duration: 0.18) : nil, value: isHovering)
        .help(isChinese ? "随机提示" : "Random tip")
    }
}

private struct SessionHintControlButton: View {
    let systemImage: String
    let helpText: String
    let motionEnabled: Bool
    var hoverTint: Color = Color.accentColor
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isEnabled ? Color.white.opacity(0.92) : Color.secondary.opacity(0.55))
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(Color.white.opacity(isHovering && isEnabled ? 0.14 : 0.08))
                }
                .overlay(
                    Circle()
                        .strokeBorder(isHovering && isEnabled ? hoverTint.opacity(0.38) : Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: hoverTint.opacity(isHovering && isEnabled ? 0.32 : 0), radius: 10, y: 0)
                .scaleEffect(isHovering && isEnabled ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(motionEnabled ? .easeOut(duration: 0.16) : nil, value: isHovering)
    }
}

private struct TutorialCoachOverlay: View {
    @ObservedObject var model: AppModel
    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var motionEnabled: Bool {
        idataAnimationsEnabled && !accessibilityReduceMotion
    }

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(isChinese ? "教程引导" : "Tutorial Coach", systemImage: "graduationcap.fill")
                    .font(.headline)

                Spacer(minLength: 0)

                Button {
                    model.setTutorialCoachExpanded(!model.isTutorialCoachExpanded)
                } label: {
                    Image(systemName: model.isTutorialCoachExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help(model.isTutorialCoachExpanded ? (isChinese ? "收起引导层" : "Collapse tutorial coach") : (isChinese ? "展开引导层" : "Expand tutorial coach"))

                Button {
                    model.finishTutorial()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help(isChinese ? "退出教程" : "Exit tutorial")
            }

            Text(model.tutorialProgressText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.isTutorialCoachExpanded, let chapter = model.tutorialCurrentChapter, let step = model.tutorialCurrentStep {
                VStack(alignment: .leading, spacing: 10) {
                    Text(step.title)
                        .font(.title3.weight(.bold))

                    Text(step.instruction)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(step.command)
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())

                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                HStack(spacing: 8) {
                    ForEach(chapter.steps, id: \.id) { item in
                        Button {
                            model.jumpToTutorialStep(item.index)
                        } label: {
                            Circle()
                                .fill(item.index == model.tutorialStepIndex ? Color.accentColor : Color.white.opacity(0.22))
                                .frame(width: 8, height: 8)
                        }
                        .buttonStyle(.plain)
                        .help(localizedText(
                            isChinese,
                            english: "Jump to step \(item.index + 1)",
                            chinese: "跳到第 \(item.index + 1) 步"
                        ))
                    }
                }

                HStack(spacing: 8) {
                    Button(isChinese ? "上一步" : "Back") {
                        model.rewindTutorialStep()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.tutorialStepIndex == 0)
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                    .help(isChinese ? "快捷键：⌘←" : "Shortcut: ⌘←")

                    CommandShortcutBadge(text: "⌘←")

                    Spacer(minLength: 0)

                    if model.isTutorialLastStep {
                        Button(isChinese ? "完成" : "Finish") {
                            model.completeTutorial()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.rightArrow, modifiers: [.command])
                        .help(isChinese ? "快捷键：⌘→" : "Shortcut: ⌘→")
                    } else {
                        Button(isChinese ? "下一步" : "Next") {
                            model.advanceTutorialStep()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.rightArrow, modifiers: [.command])
                        .help(isChinese ? "快捷键：⌘→" : "Shortcut: ⌘→")
                    }

                    CommandShortcutBadge(text: "⌘→")
                }
            }
        }
        .frame(width: 340, alignment: .leading)
        .padding(16)
        .background(
            ZStack {
                Color.clear
                    .background(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.accentColor.opacity(0.12),
                        Color.blue.opacity(0.10),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
        .shadow(color: Color.accentColor.opacity(0.16), radius: 26, y: 0)
        .quietInteractiveSurface(
            enabled: motionEnabled,
            hoverScale: 1.004,
            hoverYOffset: -0.5,
            shadowOpacity: 0.06,
            shadowRadius: 8
        )
        .animation(motionEnabled ? .easeOut(duration: 0.22) : nil, value: model.tutorialStepIndex)
        .animation(motionEnabled ? .easeOut(duration: 0.22) : nil, value: model.isTutorialCoachExpanded)
    }
}

private struct CommandShortcutBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .fixedSize()
            .lineLimit(1)
            .minimumScaleFactor(1)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.10))
        )
    }
}

private let detailBackground = LinearGradient(
    colors: [
        Color.accentColor.opacity(0.12),
        Color(nsColor: .windowBackgroundColor).opacity(0.8),
        Color.black.opacity(0.04),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
