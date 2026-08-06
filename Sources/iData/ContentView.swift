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
        .frame(minWidth: 680, minHeight: 460)
        .animation(motionEnabled ? .spring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.12) : nil, value: model.externalHandoffNotice)
        .dropDestination(for: URL.self) { items, _ in
            model.handleDroppedFiles(items)
        }
        .sheet(isPresented: $model.isHelpPresented) {
            HelpView(model: model)
        }
        .sheet(isPresented: $model.isTutorialHubPresented, onDismiss: {
            if model.isTutorialActive {
                DispatchQueue.main.async {
                    model.displayedSession?.focusTerminalDisplay()
                }
            }
        }) {
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
    @State private var hoveredRecentFilePath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SidebarHeaderCard(model: model)

            if model.recentFiles.isEmpty {
                if model.isSidebarCollapsed {
                    EmptySidebarRailState(
                        isChinese: model.effectiveLanguage == .chinese,
                        openAction: { model.openDocument() }
                    )
                } else {
                    EmptySidebarState(isChinese: model.effectiveLanguage == .chinese)
                }
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(model.recentFiles, id: \.standardizedFileURL.path) { fileURL in
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
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .onHover { hovering in
                    if !hovering {
                        hoveredRecentFilePath = nil
                    }
                }
            }

            Spacer(minLength: 0)
            SidebarFooter(model: model)
        }
        .padding(model.isSidebarCollapsed ? 12 : 16)
        .background(Color.clear)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.055))
                .frame(width: 1)
                .allowsHitTesting(false)
        }
        .clipped()
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

private struct SidebarHeaderCard: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isHoveringCollapsedIcon = false

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.isSidebarCollapsed {
                collapsedExpandButton
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                appIcon

                expandedDetails
                    .padding(.leading, 60)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .padding(.horizontal, model.isSidebarCollapsed ? 0 : 2)
        .padding(.vertical, model.isSidebarCollapsed ? 0 : 4)
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("iData")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Spacer(minLength: 0)

                if !model.recentFiles.isEmpty {
                    Button(localizedText(isChinese, english: "Clear All", chinese: "清空")) {
                        model.clearRecentFiles()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .quietInteractiveSurface(enabled: motionEnabled)
                    .help(localizedText(isChinese, english: "Clear all recent file records", chinese: "清空最近文件"))
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
                chinese: "原生查看大型表格"
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

                if isHoveringCollapsedIcon {
                    SidebarHoverGlow(isVisible: true, style: .circle)
                        .transition(.opacity)
                }

                appIcon
            }
            .frame(width: 54, height: 54)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(localizedText(isChinese, english: "Expand sidebar", chinese: "展开侧边栏"))
        .accessibilityLabel(localizedText(isChinese, english: "Expand sidebar", chinese: "展开侧边栏"))
        .onHover { hovering in
            guard hovering != isHoveringCollapsedIcon else {
                return
            }
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
            .accessibilityLabel(localizedText(isChinese, english: "Settings", chinese: "设置"))
            .help(localizedText(isChinese, english: "Settings", chinese: "设置"))

            Button {
                model.isHelpPresented = true
            } label: {
                SidebarFooterActionIcon(symbol: "questionmark.circle", motionEnabled: motionEnabled)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localizedText(isChinese, english: "Help", chinese: "帮助"))
            .help(localizedText(isChinese, english: "Help", chinese: "帮助"))

            Button {
                model.presentTutorialHub()
            } label: {
                SidebarFooterActionIcon(symbol: "graduationcap.fill", motionEnabled: motionEnabled)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localizedText(isChinese, english: "Tutorial", chinese: "教程"))
            .help(localizedText(isChinese, english: "Tutorial", chinese: "教程"))
        }
        .frame(
            maxWidth: .infinity,
            alignment: model.isSidebarCollapsed ? .center : .leading
        )
        .foregroundStyle(.secondary)
    }
}

private struct EmptySidebarState: View {
    let isChinese: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localizedText(isChinese, english: "No recent files yet", chinese: "暂无最近文件"), systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.headline)

            Text(localizedText(
                isChinese,
                english: "Files you open will appear here.",
                chinese: "打开过的文件会显示在这里。"
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
}

private struct EmptySidebarRailState: View {
    let isChinese: Bool
    let openAction: () -> Void
    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button(action: openAction) {
            VStack {
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
        .accessibilityLabel(localizedText(isChinese, english: "Open File", chinese: "打开文件"))
        .help(localizedText(isChinese, english: "Open a table", chinese: "打开表格"))
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .quietInteractiveSurface(
            enabled: idataAnimationsEnabled && !accessibilityReduceMotion,
            glowStyle: .rounded(10)
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
        HStack(spacing: 8) {
            Button(action: openAction) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(fileURL.lastPathComponent)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(fileURL.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: togglePinAction) {
                    Label(isPinned ? (isChinese ? "取消置顶" : "Unpin") : (isChinese ? "置顶" : "Pin"), systemImage: isPinned ? "pin.slash" : "pin")
                }
                Button(role: .destructive, action: removeAction) {
                    Label(isChinese ? "移除" : "Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "ellipsis")
                    .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isActive ? Color.accentColor.opacity(0.14) : (isHovering ? Color.primary.opacity(0.06) : Color.clear), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if isHovering {
                SidebarHoverGlow(isVisible: true, style: .rounded(8))
                    .transition(.opacity)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .animation(motionEnabled ? .easeOut(duration: 0.16) : nil, value: isHovering)
        .onHover { hovering in
            guard hovering != isHovering else {
                return
            }
            isHovering = hovering
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
            .background(isActive ? Color.accentColor.opacity(0.14) : Color.primary.opacity(isHovering ? 0.08 : 0.04), in: Circle())
            .overlay(
                Circle()
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.30) : Color.primary.opacity(0.08))
            )
            .overlay {
                if isHovering {
                    SidebarHoverGlow(isVisible: true, style: .circle)
                        .transition(.opacity)
                }
            }
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
            .animation(motionEnabled ? .easeOut(duration: 0.16) : nil, value: isHovering)
            .onHover { hovering in
                guard hovering != isHovering else {
                    return
                }
                isHovering = hovering
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
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
                .background(Color.primary.opacity(isHovering ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
                .overlay {
                    if isHovering {
                        SidebarHoverGlow(isVisible: true, style: .rounded(8))
                            .transition(.opacity)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localizedText(isChinese, english: "Collapse sidebar", chinese: "收起侧边栏"))
        .help(localizedText(isChinese, english: "Collapse sidebar", chinese: "收起侧边栏"))
        .animation(motionEnabled ? .easeOut(duration: 0.16) : nil, value: isHovering)
        .onHover { hovering in
            guard hovering != isHovering else {
                return
            }
            isHovering = hovering
        }
    }
}

private struct SidebarFooterActionIcon: View {
    let symbol: String
    let motionEnabled: Bool

    @State private var isHovering = false

    var body: some View {
        HoverAnimatedCircleSymbol(
            symbol: symbol,
            font: .system(size: 17, weight: .semibold),
            motionEnabled: motionEnabled,
            isHovering: isHovering
        )
            .foregroundStyle(isHovering ? Color.accentColor : Color.secondary)
            .frame(width: 36, height: 36)
            .background(Color.primary.opacity(isHovering ? 0.09 : 0.04), in: Circle())
            .overlay {
                if isHovering {
                    SidebarHoverGlow(isVisible: true, style: .circle)
                        .transition(.opacity)
                }
            }
            .contentShape(Circle())
            .animation(motionEnabled ? .easeOut(duration: 0.16) : nil, value: isHovering)
            .onHover { hovering in
                guard hovering != isHovering else {
                    return
                }
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
    case prominentRounded(CGFloat)
    case circle
}

struct SidebarHoverGlow: View {
    let isVisible: Bool
    let style: SidebarHoverGlowStyle

    private var glowGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.09),
                Color(red: 0.24, green: 0.78, blue: 1.0).opacity(0.055),
                Color(red: 0.50, green: 0.42, blue: 1.0).opacity(0.045),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var prominentStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.58),
                Color(red: 0.34, green: 0.84, blue: 1.0).opacity(0.62),
                Color(red: 0.58, green: 0.50, blue: 1.0).opacity(0.48),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Group {
            switch style {
            case .none:
                EmptyView()
            case let .rounded(cornerRadius):
                glow(for: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            case let .prominentRounded(cornerRadius):
                prominentGlow(for: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            case .circle:
                glow(for: Circle())
            }
        }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glow<S: InsettableShape>(for shape: S) -> some View {
        shape
            .fill(glowGradient)
            .overlay {
                shape
                    .inset(by: 0.5)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
    }

    private func prominentGlow<S: InsettableShape>(for shape: S) -> some View {
        shape
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.16),
                        Color(red: 0.24, green: 0.78, blue: 1.0).opacity(0.13),
                        Color(red: 0.50, green: 0.42, blue: 1.0).opacity(0.11),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                shape
                    .inset(by: 0.75)
                    .strokeBorder(prominentStrokeGradient, lineWidth: 1.5)
            }
            .background {
                shape
                    .stroke(prominentStrokeGradient, lineWidth: 8)
                    .opacity(0.26)
            }
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
    @State private var selectedTopic = HelpTopic.iData

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    private var onboardingTips: [QuickTip] {
        [
            QuickTip(
                keys: localizedText(isChinese, english: "Open… / Drag File", chinese: "打开… / 拖入文件"),
                title: localizedText(isChinese, english: "Open Data", chinese: "打开数据"),
                detail: localizedText(
                    isChinese,
                    english: "Use the toolbar or drag a file into the main window. iData forwards the real file into embedded VisiData.",
                    chinese: "点按“打开…”或将文件拖入窗口。"
                )
            ),
            QuickTip(
                keys: localizedText(isChinese, english: "Recent + Pin", chinese: "最近文件 / 置顶"),
                title: localizedText(isChinese, english: "Keep Key Files", chinese: "常用文件"),
                detail: localizedText(
                    isChinese,
                    english: "Click a recent item to reopen it. Pin important files so they stay fixed at the top of the sidebar.",
                    chinese: "点按即可重新打开；置顶后会固定在侧栏顶部。"
                )
            ),
            QuickTip(
                keys: "⌘,",
                title: localizedText(isChinese, english: "Settings", chinese: "设置"),
                detail: localizedText(
                    isChinese,
                    english: "Adjust the `vd` path, automatic update behavior, or run a manual update check.",
                    chinese: "设置 vd 路径和自动更新，也可手动检查更新。"
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
                    chinese: "常见表格可直接打开，也支持 .ma 等非标准扩展名。"
                )
            ),
            QuickTip(
                keys: ".gz / .bgz",
                title: localizedText(isChinese, english: "Stream Compression", chinese: "压缩文件"),
                detail: localizedText(
                    isChinese,
                    english: "Compressed files are streamed into VisiData without extracting them to disk first.",
                    chinese: ".gz / .bgz 无需预先解压。"
                )
            ),
            QuickTip(
                keys: "Excel",
                title: localizedText(isChinese, english: "About `.xlsx`", chinese: "Excel 文件"),
                detail: localizedText(
                    isChinese,
                    english: "VisiData can read Excel, but that depends on the Python environment having the required loader installed. If Excel fails, install the missing VisiData dependency in the same Python environment as `vd`.",
                    chinese: "VisiData 读取 Excel 需要额外依赖；若打开失败，请在 vd 所在环境补装。"
                )
            ),
        ]
    }

    private var visiDataTips: [QuickTip] {
        [
            QuickTip(keys: "← ↑ ↓ →  |  h j k l", title: localizedText(isChinese, english: "Move", chinese: "移动"), detail: localizedText(isChinese, english: "Navigate cells and columns without leaving the keyboard.", chinese: "在行列间移动。")),
            QuickTip(keys: "/  ?  n  Shift+N", title: localizedText(isChinese, english: "Search", chinese: "搜索"), detail: localizedText(isChinese, english: "Search forward or backward, then jump through matches.", chinese: "向前或向后搜索，并跳转匹配项。")),
            QuickTip(keys: "[ ↑  |  ] ↓", title: localizedText(isChinese, english: "Sort", chinese: "排序"), detail: localizedText(isChinese, english: "Sort the current column ascending or descending.", chinese: "按当前列升序或降序。")),
            QuickTip(keys: "s t u", title: localizedText(isChinese, english: "Select", chinese: "选择"), detail: localizedText(isChinese, english: "Select, toggle, or unselect rows for later commands.", chinese: "选择、切换或取消选择行。")),
            QuickTip(keys: "z → Ctrl+H", title: localizedText(isChinese, english: "Command Help", chinese: "命令帮助"), detail: localizedText(isChinese, english: "Press `z`, then `Control+H` to view commands for the current sheet.", chinese: "先按 `z`，再按 `Control+H`，查看当前表的命令。")),
            QuickTip(keys: "q", title: localizedText(isChinese, english: "Back / Quit Sheet", chinese: "返回 / 退出表"), detail: localizedText(isChinese, english: "Go back from a derived sheet or quit the session when you are done.", chinese: "返回上层表格，或退出会话。")),
        ]
    }

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selectedTopic) { topic in
                Label(topic.title(isChinese: isChinese), systemImage: topic.icon)
                    .tag(topic)
            }
            .navigationTitle(isChinese ? "帮助" : "Help")
            .safeAreaInset(edge: .bottom) {
                Button(isChinese ? "关闭" : "Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .padding()
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(selectedTopic.title(isChinese: isChinese))
                        .font(.largeTitle.bold())

                    Text(selectedTopic.summary(isChinese: isChinese))
                        .foregroundStyle(.secondary)

                    helpSection(title: "", tips: selectedTips)
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 720, height: 540)
    }

    private var selectedTips: [QuickTip] {
        switch selectedTopic {
        case .iData:
            onboardingTips
        case .files:
            softwareTips
        case .shortcuts:
            visiDataTips
        }
    }

    @ViewBuilder
    private func helpSection(title: String, tips: [QuickTip]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
            }

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
        .padding(.vertical, 4)
    }

}

private enum HelpTopic: String, CaseIterable, Identifiable {
    case iData
    case files
    case shortcuts

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .iData: "macwindow"
        case .files: "doc"
        case .shortcuts: "keyboard"
        }
    }

    func title(isChinese: Bool) -> String {
        switch self {
        case .iData: localizedText(isChinese, english: "Using iData", chinese: "使用 iData")
        case .files: localizedText(isChinese, english: "Opening Files", chinese: "打开文件")
        case .shortcuts: localizedText(isChinese, english: "Shortcuts", chinese: "快捷键")
        }
    }

    func summary(isChinese: Bool) -> String {
        switch self {
        case .iData:
            localizedText(isChinese, english: "Open files, revisit recent work, and adjust the app.", chinese: "打开文件、查看最近项目和调整应用设置。")
        case .files:
            localizedText(isChinese, english: "What iData opens directly and what needs an extra loader.", chinese: "了解直接支持的格式和额外依赖。")
        case .shortcuts:
            localizedText(isChinese, english: "The essential commands for working inside VisiData.", chinese: "在 VisiData 中常用的基础命令。")
        }
    }
}

private struct TutorialHubView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedChapterID: String?

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    var body: some View {
        NavigationSplitView {
            List(model.tutorialChapters, selection: $selectedChapterID) { chapter in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chapter.title)
                        Text("\(chapter.completedStepCount)/\(chapter.steps.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: chapter.isCompleted ? "checkmark.circle.fill" : chapter.icon)
                        .foregroundStyle(chapter.isCompleted ? .green : Color.accentColor)
                }
                .tag(chapter.id)
            }
            .navigationTitle(isChinese ? "教程" : "Tutorial")
            .safeAreaInset(edge: .bottom) {
                Button(isChinese ? "关闭" : "Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .padding()
            }
        } detail: {
            if let chapter = selectedChapter {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(chapter.title)
                                    .font(.largeTitle.bold())
                                Text(chapter.subtitle)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(chapter.isCompleted ? (isChinese ? "重新练习" : "Practice Again") : (isChinese ? "开始练习" : "Start")) {
                                model.startTutorial(chapterID: chapter.id)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if let errorMessage = model.tutorialErrorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Text(isChinese
                            ? "记号：+ 表示同时按，→ 表示依次按，| 表示任选。每步完成后，请在引导卡中确认。"
                            : "Notation: + means together, → means in sequence, and | means either. Confirm each step in the coach when done.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        ForEach(chapter.steps, id: \.id) { step in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: step.index < chapter.completedStepCount ? "checkmark.circle.fill" : "\(step.index + 1).circle")
                                    .foregroundStyle(step.index < chapter.completedStepCount ? .green : Color.secondary)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.title)
                                        .font(.headline)
                                    Text(step.command)
                                        .font(.system(.subheadline, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(step.instruction)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(28)
                }
            } else {
                ContentUnavailableView(
                    isChinese ? "选择章节" : "Choose a Chapter",
                    systemImage: "graduationcap",
                    description: Text(isChinese ? "从左侧选择教程。" : "Select a tutorial from the sidebar.")
                )
            }
        }
        .frame(width: 760, height: 560)
        .onAppear {
            if selectedChapterID == nil {
                selectedChapterID = model.tutorialChapters.first?.id
            }
        }
    }

    private var selectedChapter: AppModel.TutorialChapter? {
        model.tutorialChapters.first { $0.id == selectedChapterID }
    }
}

private struct WelcomeDetailView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdaterController
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    private var quickTips: [QuickTip] {
        [
            QuickTip(keys: "← ↑ ↓ →  |  h j k l", title: localizedText(isChinese, english: "Move", chinese: "移动"), detail: localizedText(isChinese, english: "Move quickly across rows and columns.", chinese: "在行列间移动。")),
            QuickTip(keys: "/  ?  n  Shift+N", title: localizedText(isChinese, english: "Search", chinese: "搜索"), detail: localizedText(isChinese, english: "Search and move between matches.", chinese: "搜索并切换匹配项。")),
            QuickTip(keys: "s t u", title: localizedText(isChinese, english: "Select Rows", chinese: "选择行"), detail: localizedText(isChinese, english: "Select, toggle, or unselect rows.", chinese: "选择、切换或取消选择行。")),
            QuickTip(keys: "[ ↑  |  ] ↓", title: localizedText(isChinese, english: "Sort", chinese: "排序"), detail: localizedText(isChinese, english: "Sort the current column up or down.", chinese: "按当前列升序或降序。")),
            QuickTip(keys: "z → Ctrl+H", title: localizedText(isChinese, english: "Help", chinese: "帮助"), detail: localizedText(isChinese, english: "View commands for the current sheet.", chinese: "查看当前表的命令。"))
        ]
    }

    private let repositoryURL = URL(string: "https://github.com/laleoarrow/iData")!

    var body: some View {
        let dependencyState = model.visiDataDependencyState

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroCard(dependencyState: dependencyState)
                Divider()
                quickTipsCard
                systemStatusSection(dependencyState: dependencyState)

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
            .frame(maxWidth: 760)
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
    }

    private func heroCard(dependencyState: AppModel.VisiDataDependencyState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(isChinese ? "打开数据" : "Open Data")
                        .font(.largeTitle.bold())

                    Text(isChinese ? "选择表格，直接进入 VisiData。" : "Choose a table and go straight to VisiData.")
                        .foregroundStyle(.secondary)
                }
            }

            heroActions(dependencyState: dependencyState)

            Text(isChinese ? "支持常见表格与 .gz / .bgz 压缩文件。" : "Supports common tables and .gz / .bgz compressed files.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heroActions(dependencyState: AppModel.VisiDataDependencyState) -> some View {
        HStack(spacing: 10) {
            heroPrimaryActions(dependencyState: dependencyState)

            Menu {
                Button {
                    model.presentTutorialHub()
                } label: {
                    Label(isChinese ? "教程" : "Tutorial", systemImage: "graduationcap")
                }

                SettingsLink {
                    Label(isChinese ? "设置" : "Settings", systemImage: "gearshape")
                }

                Divider()

                Button {
                    updater.checkForUpdates()
                } label: {
                    Label(isChinese ? "检查更新" : "Check for Updates", systemImage: "arrow.clockwise")
                }

                Link(destination: repositoryURL) {
                    Label("GitHub", systemImage: "link")
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "ellipsis.circle")
                    Text(isChinese ? "更多" : "More")
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .fixedSize()
            .quietInteractiveSurface(enabled: motionEnabled)
        }
    }

    @ViewBuilder
    private func heroPrimaryActions(dependencyState: AppModel.VisiDataDependencyState) -> some View {
        Button {
            model.openDocument()
        } label: {
            Label(isChinese ? "打开…" : "Open…", systemImage: "tablecells")
        }
        .buttonStyle(.borderedProminent)
        .quietInteractiveSurface(enabled: motionEnabled, glowStyle: .prominentRounded(8))

        if case .missing = dependencyState {
            Button {
                model.runVisiDataOneClickSetup()
            } label: {
                Label(isChinese ? "安装 VisiData" : "Install VisiData", systemImage: "shippingbox")
            }
            .buttonStyle(.borderedProminent)
            .quietInteractiveSurface(enabled: motionEnabled)
        }
    }

    private func systemStatusSection(dependencyState: AppModel.VisiDataDependencyState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: dependencyState.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(dependencyState.isAvailable ? .green : .orange)

            Text(dependencyState.isAvailable
                ? (isChinese ? "VisiData 已就绪" : "VisiData Ready")
                : (isChinese ? "需要安装 VisiData" : "VisiData Required"))
                .font(.subheadline.weight(.semibold))

            Spacer()

            Text(model.appVersionDisplay(revealingBuild: false))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
    }

    private var quickTipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(localizedText(isChinese, english: "VisiData Quick Start", chinese: "VisiData 快速上手"))
                        .font(.headline)

                    Text(localizedText(
                        isChinese,
                        english: "These are common starter shortcuts. All normal VisiData commands still work inside the embedded session.",
                        chinese: "常用快捷键；其他 VisiData 命令同样可用。"
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    quickTipColumn(Array(quickTips.prefix(2)), keyWidth: 94)

                    Divider()

                    quickTipColumn(Array(quickTips.dropFirst(2).prefix(2)), keyWidth: 58)
                }
                .frame(minWidth: 560)
                .fixedSize(horizontal: false, vertical: true)

                quickTipColumn(Array(quickTips.prefix(4)), keyWidth: 94)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickTipColumn(_ tips: [QuickTip], keyWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tips.enumerated()), id: \.element.id) { index, tip in
                quickTipPreviewRow(tip, keyWidth: keyWidth)
                    .padding(.vertical, 12)

                if index < tips.count - 1 {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func quickTipPreviewRow(_ tip: QuickTip, keyWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(tip.keys)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(Color.accentColor)
                .frame(width: keyWidth, alignment: .leading)

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
                "命令帮助：先按 z，再按 Ctrl+H。",
                "搜索后按 Enter；n 到下一处，Shift+N 回到上一处。",
                "方向键和 hjkl 都能移动，用顺手的就行。",
                "当前列排序：[ 升序，] 降序。",
                "不确定快捷键时，先打开教程看一眼。",
            ]
        }

        return [
            "Tip: For command help, press `z`, then `Control+H`.",
            "Tip: After `/` search, use `n` for next and `Shift+N` for previous.",
            "Tip: Arrow keys and `h j k l` both work for movement.",
            "Tip: Sort the current column with `[` (asc) and `]` (desc).",
            "Tip: Replaying the tutorial checklist is the fastest way to build muscle memory.",
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sessionHeader

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
                .transition(.opacity)
            }

            ZStack(alignment: .topTrailing) {
                EmbeddedTerminalView(session: session)
                    .id(ObjectIdentifier(session))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10))
                    )

                if model.isTutorialActive, model.tutorialCurrentStep != nil {
                    TutorialCoachOverlay(
                        model: model,
                        returnFocusToTable: {
                            DispatchQueue.main.async {
                                session.focusTerminalDisplay()
                            }
                        }
                    )
                        .padding(12)
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
            } else if let statusMessage = model.tutorialStatusMessage ?? session.statusMessage ?? model.statusMessage {
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
        HStack(spacing: 8) {
            Button(action: openAction) {
                Label(localizedText(isChinese, english: "Open…", chinese: "打开…"), systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o")
            .quietInteractiveSurface(enabled: motionEnabled)

            Menu {
                Button {
                    reopenAction()
                } label: {
                    Label(localizedText(isChinese, english: "Reopen", chinese: "重新打开"), systemImage: "arrow.clockwise")
                }
                .disabled(!canReopen)

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
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .quietInteractiveSurface(enabled: motionEnabled, glowStyle: .circle)
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
                    .lineLimit(1)
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
        .padding(10)
        .frame(width: 380, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
    }
}

private struct StatusAndInputCard: View {
    let isChinese: Bool
    let statusMessage: String
    let inputDisplayName: String
    let isLikelyEnglish: Bool
    let onSwitchToEnglish: () -> Void

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
            VStack(alignment: .leading, spacing: 3) {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Label(inputDisplayName, systemImage: statusBadgeIcon)
                .font(.caption)
                .foregroundStyle(isLikelyEnglish ? .green : .orange)
                .lineLimit(1)

            InputMethodQuickSwitchOrbButton(
                isChinese: isChinese,
                onTap: onSwitchToEnglish
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardTint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                .allowsHitTesting(false)
        )
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 1)
        )
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
    let returnFocusToTable: () -> Void
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
                    returnFocusToTable()
                } label: {
                    Image(systemName: model.isTutorialCoachExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help(model.isTutorialCoachExpanded ? (isChinese ? "收起引导层" : "Collapse tutorial coach") : (isChinese ? "展开引导层" : "Expand tutorial coach"))

                Button {
                    model.cancelTutorial()
                    returnFocusToTable()
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
                            returnFocusToTable()
                        } label: {
                            Circle()
                                .fill(item.index == model.tutorialStepIndex ? Color.accentColor : Color.white.opacity(0.22))
                                .frame(width: 8, height: 8)
                        }
                        .buttonStyle(.plain)
                        .disabled(item.index > max(model.tutorialStepIndex, chapter.completedStepCount))
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
                        returnFocusToTable()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.tutorialStepIndex == 0)
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                    .help(isChinese ? "快捷键：⌘←" : "Shortcut: ⌘←")

                    CommandShortcutBadge(text: "⌘←")

                    Spacer(minLength: 0)

                    if model.isTutorialLastStep {
                        Button(isChinese ? "做完了，完成本章" : "Done — Finish Chapter") {
                            model.completeTutorial()
                            returnFocusToTable()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.rightArrow, modifiers: [.command])
                        .help(isChinese ? "快捷键：⌘→" : "Shortcut: ⌘→")
                    } else {
                        Button(isChinese ? "做完了，下一步" : "Done — Next") {
                            model.advanceTutorialStep()
                            returnFocusToTable()
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
            glowStyle: .rounded(12)
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
