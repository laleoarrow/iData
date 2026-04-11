import AppKit
import Carbon.HIToolbox
import SwiftUI

private func localizedText(_ isChinese: Bool, english: String, chinese: String) -> String {
    isChinese ? chinese : english
}

private func appShellLanguage() -> AppModel.AppResolvedLanguage {
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

            Divider()
                .overlay(Color.white.opacity(0.04))

            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            AppSweepShimmer(active: motionEnabled)
        }
        .frame(minWidth: 960, minHeight: 620)
        .animation(sidebarLayoutAnimation, value: model.isSidebarCollapsed)
        .dropDestination(for: URL.self) { items, _ in
            model.handleDroppedFiles(items)
        }
        .toolbar {
            ToolbarItemGroup {
                Button(localizedText(isChinese, english: "Open…", chinese: "打开…")) {
                    model.openDocument()
                }
                .keyboardShortcut("o")

                Button(localizedText(isChinese, english: "Reopen", chinese: "重新打开")) {
                    model.reopenLastFile()
                }
                .disabled(model.lastOpenedFile == nil)
            }
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

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var listAnimation: Animation? {
        motionEnabled
            ? .spring(response: 0.32, dampingFraction: 0.90, blendDuration: 0.14)
            : nil
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.10),
                    Color.black.opacity(0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                SidebarAmbientGlow(
                    isCollapsed: model.isSidebarCollapsed,
                    motionEnabled: motionEnabled
                )
            }

            VStack(alignment: .leading, spacing: model.isSidebarCollapsed ? 14 : 16) {
                SidebarHeaderCard(model: model)

                if model.recentFiles.isEmpty {
                    if model.isSidebarCollapsed {
                        EmptySidebarRailState()
                    } else {
                        EmptySidebarState(isChinese: model.effectiveLanguage == .chinese)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: model.isSidebarCollapsed ? 12 : 10) {
                            ForEach(model.recentFiles, id: \.path) { fileURL in
                                Group {
                                    if model.isSidebarCollapsed {
                                        CollapsedRecentFileRow(
                                            fileURL: fileURL,
                                            isActive: model.activeSession?.currentFileURL?.standardizedFileURL == fileURL.standardizedFileURL,
                                            isChinese: model.effectiveLanguage == .chinese,
                                            openAction: { model.openExternalFile(fileURL) },
                                            removeAction: { model.removeRecentFile(fileURL) }
                                        )
                                    } else {
                                        RecentFileRow(
                                            fileURL: fileURL,
                                            isActive: model.activeSession?.currentFileURL?.standardizedFileURL == fileURL.standardizedFileURL,
                                            isPinned: model.isPinnedRecentFile(fileURL),
                                            isChinese: model.effectiveLanguage == .chinese,
                                            openAction: { model.openExternalFile(fileURL) },
                                            togglePinAction: { model.togglePinnedRecentFile(fileURL) },
                                            removeAction: { model.removeRecentFile(fileURL) }
                                        )
                                    }
                                }
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                                        removal: .scale(scale: 0.96).combined(with: .opacity)
                                    )
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, model.isSidebarCollapsed ? 0 : 2)
                        .padding(.bottom, 6)
                    }
                    .scrollIndicators(.hidden)
                    .animation(listAnimation, value: model.recentFiles)
                }

                Spacer(minLength: 0)

                SidebarFooter(model: model)
            }
            .padding(16)
        }
    }
}

private struct SidebarHeaderCard: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @StateObject private var commandMonitor = CommandKeyMonitor()
    @State private var isHoveringCollapsedIcon = false

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var collapsedHeaderAction: AppModel.CollapsedSidebarHeaderAction {
        AppModel.collapsedSidebarHeaderAction(
            hasRecentFiles: !model.recentFiles.isEmpty,
            isCommandPressed: commandMonitor.isCommandPressed
        )
    }

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    var body: some View {
        Group {
            if model.isSidebarCollapsed {
                collapsedBody
            } else {
                expandedBody
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10))
        )
        .shadow(color: .black.opacity(0.10), radius: 24, y: 8)
        .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.008, hoverYOffset: -1, shadowOpacity: 0.08, shadowRadius: 12)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                appIcon

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
                            isCollapsed: false,
                            isChinese: isChinese,
                            motionEnabled: motionEnabled,
                            action: { model.toggleSidebarCollapsed() }
                        )
                    }

                    Text(localizedText(
                        isChinese,
                        english: "Native shell for large-table workflows with VisiData",
                        chinese: "面向超大表格工作流的原生 VisiData 壳层"
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var collapsedBody: some View {
        HStack {
            Spacer(minLength: 0)

            Button {
                if collapsedHeaderAction == .clearAll {
                    model.clearRecentFiles()
                } else {
                    model.setSidebarCollapsed(false)
                }
            } label: {
                ZStack {
                    appIcon

                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .opacity(isHoveringCollapsedIcon && commandMonitor.isCommandPressed && !model.recentFiles.isEmpty ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if motionEnabled {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isHoveringCollapsedIcon = hovering
                    }
                } else {
                    isHoveringCollapsedIcon = hovering
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var appIcon: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10))
            )
    }
}

private struct SidebarFooter: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    var body: some View {
        Group {
            if model.isSidebarCollapsed {
                VStack(spacing: 18) {
                    SettingsLink {
                        SidebarFooterIcon(symbol: "gearshape.fill")
                            .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.05, hoverYOffset: -1)
                    }
                    .buttonStyle(.plain)
                    .help(localizedText(isChinese, english: "Settings", chinese: "设置"))

                    Button {
                        model.isHelpPresented = true
                    } label: {
                        SidebarFooterIcon(symbol: "questionmark.circle")
                            .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.05, hoverYOffset: -1)
                    }
                    .buttonStyle(.plain)
                    .help(localizedText(isChinese, english: "Help", chinese: "帮助"))

                    Button {
                        model.presentTutorialHub()
                    } label: {
                        SidebarFooterIcon(symbol: "graduationcap.fill")
                            .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.05, hoverYOffset: -1)
                    }
                    .buttonStyle(.plain)
                    .help(localizedText(isChinese, english: "Tutorial", chinese: "教程"))
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 18) {
                    SettingsLink {
                        SidebarFooterIcon(symbol: "gearshape.fill")
                            .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.05, hoverYOffset: -1)
                    }
                    .buttonStyle(.plain)
                    .help(localizedText(isChinese, english: "Settings", chinese: "设置"))

                    Button {
                        model.isHelpPresented = true
                    } label: {
                        SidebarFooterIcon(symbol: "questionmark.circle")
                            .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.05, hoverYOffset: -1)
                    }
                    .buttonStyle(.plain)
                    .help(localizedText(isChinese, english: "Help", chinese: "帮助"))

                    Button {
                        model.presentTutorialHub()
                    } label: {
                        SidebarFooterIcon(symbol: "graduationcap.fill")
                            .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.05, hoverYOffset: -1)
                    }
                    .buttonStyle(.plain)
                    .help(localizedText(isChinese, english: "Tutorial", chinese: "教程"))

                    Spacer(minLength: 0)
                }
            }
        }
        .foregroundStyle(.secondary)
    }
}

private struct EmptySidebarState: View {
    let isChinese: Bool
    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(localizedText(isChinese, english: "No recent files yet", chinese: "还没有最近文件"), systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.headline)

            Text(localizedText(
                isChinese,
                english: "Open a table or drag one into the window. Recent items stay here for one-click reopening.",
                chinese: "打开一个表格，或直接把文件拖进窗口。最近文件会保留在这里，方便一键重新打开。"
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
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
    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
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
    let isChinese: Bool
    let openAction: () -> Void
    let togglePinAction: () -> Void
    let removeAction: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: openAction) {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button(action: togglePinAction) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isPinned ? Color.accentColor : .secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(isPinned ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.06))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(isPinned ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .help(isPinned
                ? localizedText(isChinese, english: "Unpin from top", chinese: "取消置顶")
                : localizedText(isChinese, english: "Pin to top", chinese: "置顶到顶部"))

            Button(action: removeAction) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(isHovering ? 0.10 : 0.0))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(isHovering ? 0.12 : 0.0))
                    )
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .help(localizedText(isChinese, english: "Remove from recent files", chinese: "从最近文件中移除"))
        }
        .padding(14)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(borderColor)
        )
        .shadow(color: .black.opacity(isActive ? 0.16 : 0.08), radius: isActive ? 16 : 10, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
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
            return AnyShapeStyle(.regularMaterial)
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

private struct CollapsedRecentFileRow: View {
    let fileURL: URL
    let isActive: Bool
    let isChinese: Bool
    let openAction: () -> Void
    let removeAction: () -> Void

    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @StateObject private var commandMonitor = CommandKeyMonitor()
    @State private var isHovering = false

    private var motionEnabled: Bool {
        idataAnimationsEnabled && !accessibilityReduceMotion
    }

    private var isCommandHovering: Bool {
        isHovering && commandMonitor.isCommandPressed
    }

    var body: some View {
        Button(action: primaryAction) {
            ZStack {
                Text(AppModel.collapsedRecentFileBadgeText(for: fileURL))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                    .opacity(isCommandHovering ? 0 : 1)

                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .opacity(isCommandHovering ? 1 : 0)
            }
            .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .help(primaryHelpText)
        .background(backgroundStyle, in: Circle())
        .overlay(
            Circle()
                .strokeBorder(borderColor)
        )
        .shadow(color: .black.opacity(isActive ? 0.16 : 0.08), radius: isActive ? 14 : 8, y: 4)
        .frame(maxWidth: .infinity)
        .contentShape(Circle())
        .onHover { hovering in
            if motionEnabled {
                withAnimation(.easeOut(duration: 0.18)) {
                    isHovering = hovering
                }
            } else {
                isHovering = hovering
            }
        }
        .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.02, hoverYOffset: -1)
    }

    private var primaryHelpText: String {
        if isCommandHovering {
            return localizedText(
                isChinese,
                english: "Remove \(fileURL.lastPathComponent) from recent files",
                chinese: "从最近文件中移除 \(fileURL.lastPathComponent)"
            )
        }
        return localizedText(
            isChinese,
            english: "Open \(fileURL.lastPathComponent)",
            chinese: "打开 \(fileURL.lastPathComponent)"
        )
    }

    private func primaryAction() {
        switch collapsedRecentFilePrimaryAction(isCommandHovering: isCommandHovering) {
        case .open:
            openAction()
        case .remove:
            removeAction()
        }
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

enum CollapsedRecentFilePrimaryAction: Equatable {
    case open
    case remove
}

func collapsedRecentFilePrimaryAction(isCommandHovering: Bool) -> CollapsedRecentFilePrimaryAction {
    isCommandHovering ? .remove : .open
}

private struct SidebarCollapseToggleButton: View {
    let isCollapsed: Bool
    let isChinese: Bool
    let motionEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(
                        colors: [
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
                        .strokeBorder(Color.white.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .help(isCollapsed
            ? localizedText(isChinese, english: "Expand sidebar", chinese: "展开侧边栏")
            : localizedText(isChinese, english: "Collapse sidebar", chinese: "收起侧边栏"))
        .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.02, hoverYOffset: -1, shadowOpacity: 0.08, shadowRadius: 10)
    }
}

private struct SidebarFooterIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }
}

private struct SidebarAmbientGlow: View {
    let isCollapsed: Bool
    let motionEnabled: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(isCollapsed ? 0.18 : 0.12),
                            Color.white.opacity(isCollapsed ? 0.02 : 0.08),
                            .clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 34)
                .offset(x: isCollapsed ? -28 : 34, y: isCollapsed ? -12 : -2)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isCollapsed ? 0.08 : 0.10),
                            .clear,
                        ],
                        center: isCollapsed ? .topLeading : .topTrailing,
                        startRadius: 8,
                        endRadius: 220
                    )
                )
                .blur(radius: 18)
                .offset(x: isCollapsed ? -12 : 24, y: -20)
        }
        .allowsHitTesting(false)
        .animation(motionEnabled ? .easeInOut(duration: 0.58) : nil, value: isCollapsed)
    }
}

private struct AppSweepShimmer: View {
    let active: Bool

    var body: some View {
        GeometryReader { proxy in
            if active {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: !active)) { context in
                    let width = max(proxy.size.width, 1)
                    let bandWidth = max(180, width * 0.22)
                    let startX = -bandWidth * 1.35
                    let endX = width + bandWidth * 1.35
                    let period = 24.0
                    let phase = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: period) / period
                    let x = startX + (endX - startX) * phase

                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.06),
                            Color.accentColor.opacity(0.10),
                            .clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: bandWidth)
                    .rotationEffect(.degrees(20))
                    .blur(radius: 16)
                    .offset(x: x, y: -proxy.size.height * 0.18)
                    .blendMode(.plusLighter)
                }
            }
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
                    .transition(.opacity)
            } else {
                WelcomeDetailView(model: model, updater: updater)
                    .transition(.opacity)
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
                    chinese: "用工具栏打开文件，或直接把文件拖进主窗口。iData 会把真实文件转交给内嵌的 VisiData。"
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
                title: localizedText(isChinese, english: "Stream Compression", chinese: "压缩流式读取"),
                detail: localizedText(
                    isChinese,
                    english: "Compressed files are streamed into VisiData without extracting them to disk first.",
                    chinese: "压缩文件会直接流式送入 VisiData，不需要先解压到磁盘。"
                )
            ),
            QuickTip(
                keys: "Excel",
                title: localizedText(isChinese, english: "About `.xlsx`", chinese: "关于 `.xlsx`"),
                detail: localizedText(
                    isChinese,
                    english: "VisiData can read Excel, but that depends on the Python environment having the required loader installed. If Excel fails, install the missing VisiData dependency in the same Python environment as `vd`.",
                    chinese: "VisiData 可以读取 Excel，但前提是 `vd` 所在的 Python 环境已经装好了对应的读取依赖。如果 Excel 打不开，请在同一个 `vd` 环境里补装缺失依赖。"
                )
            ),
        ]
    }

    private var visiDataTips: [QuickTip] {
        [
            QuickTip(keys: "hjkl / ←↑↓→", title: localizedText(isChinese, english: "Move", chinese: "移动"), detail: localizedText(isChinese, english: "Navigate cells and columns without leaving the keyboard.", chinese: "不离开键盘也能在单元格和列之间快速移动。")),
            QuickTip(keys: "/  ?  n  N", title: localizedText(isChinese, english: "Search", chinese: "搜索"), detail: localizedText(isChinese, english: "Search forward or backward, then jump through matches.", chinese: "支持向前或向后搜索，并在匹配结果间跳转。")),
            QuickTip(keys: "[  ]", title: localizedText(isChinese, english: "Sort", chinese: "排序"), detail: localizedText(isChinese, english: "Sort the current column ascending or descending.", chinese: "对当前列执行升序或降序排序。")),
            QuickTip(keys: "s  t  u", title: localizedText(isChinese, english: "Select", chinese: "选择"), detail: localizedText(isChinese, english: "Select, toggle, or unselect rows for later commands.", chinese: "选择、切换或取消选择行，供后续命令使用。")),
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
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
                        chinese: "iData 是包裹真实 VisiData 的原生 macOS 外壳。外层应用负责打开文件、历史记录、更新和设置；中间的主表格区域仍然是真正的 VisiData，因此你熟悉的 VisiData 命令在会话里依然有效。"
                    ))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        StatusPill(title: localizedText(isChinese, english: "Native macOS shell", chinese: "原生 macOS 壳层"), tint: .white.opacity(0.12), icon: "macwindow")
                        StatusPill(title: localizedText(isChinese, english: "Real VisiData core", chinese: "真实 VisiData 内核"), tint: Color.accentColor.opacity(0.20), icon: "terminal")
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
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var basicPreviewSteps: [AppModel.TutorialStep] {
        model.tutorialChapters
            .first(where: { $0.id == AppModel.defaultTutorialChapterID })?
            .steps ?? []
    }

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    private var quickTips: [QuickTip] {
        [
            QuickTip(keys: "hjkl / ←↑↓→", title: localizedText(isChinese, english: "Move", chinese: "移动"), detail: localizedText(isChinese, english: "Navigate rows and columns quickly without leaving the keyboard.", chinese: "不离开键盘也能快速移动行和列。")),
            QuickTip(keys: "/  ?  n  N", title: localizedText(isChinese, english: "Search", chinese: "搜索"), detail: localizedText(isChinese, english: "Search forward or backward in the current sheet, then jump to next or previous match.", chinese: "在当前工作表中向前或向后搜索，然后跳到下一个或上一个匹配项。")),
            QuickTip(keys: "s  t  u", title: localizedText(isChinese, english: "Select Rows", chinese: "选择行"), detail: localizedText(isChinese, english: "Select, toggle, or unselect rows before profiling or exporting.", chinese: "在统计分析或导出之前，先选择、切换或取消选择行。")),
            QuickTip(keys: "[  ]", title: localizedText(isChinese, english: "Sort", chinese: "排序"), detail: localizedText(isChinese, english: "Sort the current column ascending or descending.", chinese: "对当前列执行升序或降序排序。")),
            QuickTip(keys: "Ctrl+H", title: localizedText(isChinese, english: "Help", chinese: "帮助"), detail: localizedText(isChinese, english: "Open the command and help menu to discover any VisiData action.", chinese: "打开命令与帮助菜单，查看 VisiData 的可用操作。"))
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

        return snapshot
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault {
                    return lhs.isDefault && !rhs.isDefault
                }
                return lhs.index < rhs.index
            }
            .map { (format: $0.format, isDefault: $0.isDefault) }
    }

    private func refreshDisplayedFormatAssociationStatus() {
        model.refreshFormatAssociationStatuses(forExtensions: displayedFormatExtensions)
    }

    private let repositoryURL = URL(string: "https://github.com/laleoarrow/iData")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heroCard
                tutorialEntryCard
                summaryCards
                quickTipsCard
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
        .background(detailBackground.ignoresSafeArea())
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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

                    Text(isChinese ? "在原生 macOS 壳中打开超大表格文件，同时保留 VisiData 完整的行为、快捷键和运行速度。" : "Open large tables in a native macOS shell while keeping real VisiData behavior, shortcuts, and speed.")
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

            Text(isChinese ? "大多数生信文件后缀会直接透传。压缩的 `.gz` / `.bgz` 文件会直接流式读取，无需解压。" : "Most bioinformatics suffixes are passed through directly. Compressed `.gz` / `.bgz` files are streamed without extracting.")
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
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10))
        )
        .shadow(color: .black.opacity(0.10), radius: 26, y: 10)
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
        VStack(alignment: .leading, spacing: 14) {
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
                .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.012, hoverYOffset: -1)
            }

            VStack(spacing: 9) {
                ForEach(Array(basicPreviewSteps.prefix(4)), id: \.id) { step in
                    tutorialPreviewRow(step)
                }
            }
            .animation(motionEnabled ? .spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12) : nil, value: model.isTutorialActive)
        }
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
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10))
        )
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

    private var summaryCards: some View {
        HStack(alignment: .top, spacing: 14) {
            SummaryCard(
                title: localizedText(isChinese, english: "Runtime", chinese: "运行环境"),
                icon: "waveform.path.ecg.rectangle",
                detail: localizedText(
                    isChinese,
                    english: "\(model.visiDataDependencySummary) Files are no longer restricted by suffix; iData only special-cases compressed gzip-like inputs.",
                    chinese: "\(model.visiDataDependencySummary) 现在文件不再受后缀限制；iData 只会对 gzip 类压缩输入做少量特殊处理。"
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            SummaryCard(
                title: localizedText(isChinese, english: "Updates", chinese: "更新"),
                icon: "square.and.arrow.down",
                detail: updater.statusMessage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var quickTipsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localizedText(isChinese, english: "VisiData Quick Start", chinese: "VisiData 快速上手"))
                .font(.headline)

            Text(localizedText(
                isChinese,
                english: "These are common starter shortcuts. All normal VisiData commands still work inside the embedded session.",
                chinese: "这里列出的是常见入门快捷键。内嵌会话里其余标准 VisiData 命令仍然都可以正常使用。"
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(quickTips) { tip in
                HStack(alignment: .top, spacing: 14) {
                    Text(tip.keys)
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: Capsule())

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
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
    }

    private var formatsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localizedText(isChinese, english: "Supported Formats", chinese: "支持的格式"))
                .font(.headline)

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
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
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
    @State private var sessionInfoHint = ""

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    private var shouldShowSessionInfoHint: Bool {
        !model.isTutorialActive && session.currentFileURL != nil && !sessionInfoHint.isEmpty
    }

    private var sessionInfoHints: [String] {
        if isChinese {
            return [
                "提示：不是同时按 z?，而是先按 z，再按 ?。",
                "提示：搜索时输入后只按一次 Enter，之后用 n/N 跳转。",
                "提示：方向键和 hjkl 都能移动，先用顺手的就行。",
                "提示：当前列排序是 ] 升序、[ 降序。",
                "提示：有不确定命令时，先看教程清单再实践一遍。",
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.currentFileURL?.lastPathComponent ?? localizedText(isChinese, english: "VisiData Session", chinese: "VisiData 会话"))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(session.currentFileURL?.path ?? localizedText(isChinese, english: "No file loaded", chinese: "尚未加载文件"))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 12) {
                    if let fileURL = session.currentFileURL {
                        HStack(spacing: 10) {
                            Button {
                                model.revealInFinder(fileURL)
                            } label: {
                                Label(localizedText(isChinese, english: "Show in Finder", chinese: "在 Finder 中显示"), systemImage: "finder")
                            }
                            .buttonStyle(.bordered)
                            .quietInteractiveSurface(enabled: motionEnabled)

                            Button {
                                model.copyPathToPasteboard(fileURL)
                            } label: {
                                Label(localizedText(isChinese, english: "Copy Path", chinese: "复制路径"), systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .quietInteractiveSurface(enabled: motionEnabled)
                        }
                    }

                    if shouldShowSessionInfoHint {
                        SessionInfoHintRow(
                            isChinese: isChinese,
                            message: sessionInfoHint
                        )
                        .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .animation(motionEnabled ? .easeOut(duration: 0.22) : nil, value: shouldShowSessionInfoHint)

            ZStack(alignment: .topTrailing) {
                EmbeddedTerminalView(session: session)
                    .id(ObjectIdentifier(session))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08))
                    )
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 8)

                if model.isTutorialActive, model.tutorialCurrentStep != nil {
                    TutorialCoachOverlay(model: model)
                        .padding(.top, 62)
                        .padding(.trailing, 16)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(motionEnabled ? .spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12) : nil, value: model.isTutorialActive)

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
        .padding(24)
        .background(detailBackground.ignoresSafeArea())
        .onAppear {
            pickRandomSessionHint()
        }
        .onChange(of: session.currentFileURL?.path) { _, _ in
            pickRandomSessionHint()
        }
        .onChange(of: isChinese) { _, _ in
            pickRandomSessionHint()
        }
    }

    private func pickRandomSessionHint() {
        let pool = sessionInfoHints
        guard !pool.isEmpty else {
            sessionInfoHint = ""
            return
        }

        if pool.count == 1 {
            sessionInfoHint = pool[0]
            return
        }

        let current = sessionInfoHint
        let next = pool.randomElement() ?? pool[0]
        if next == current, let alternative = pool.first(where: { $0 != current }) {
            sessionInfoHint = alternative
        } else {
            sessionInfoHint = next
        }
    }
}

func statusPanelUsesRunningTint(for statusMessage: String) -> Bool {
    let normalized = statusMessage.lowercased()
    return normalized.contains("running visidata")
        || normalized.contains("正在运行 visidata")
        || normalized.contains("运行 visidata")
}

private struct StatusAndInputCard: View {
    let isChinese: Bool
    let statusMessage: String
    let inputDisplayName: String
    let isLikelyEnglish: Bool
    let onSwitchToEnglish: () -> Void

    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

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
        statusPanelUsesRunningTint(for: statusMessage) ? Color.green.opacity(0.14) : Color.white.opacity(0.08)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "状态" : "Status")
                    .font(.headline)

                Text(statusMessage)
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
                    .font(.subheadline)
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                cardTint
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        Color.clear,
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
                .strokeBorder(Color.white.opacity(0.10))
        )
        .quietInteractiveSurface(
            enabled: idataAnimationsEnabled && !accessibilityReduceMotion,
            hoverScale: 1.006,
            hoverYOffset: -0.5,
            shadowOpacity: 0.05,
            shadowRadius: 8
        )
    }
}

private struct InputMethodQuickSwitchOrbButton: View {
    let isChinese: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .semibold))
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
                .shadow(color: .black.opacity(0.28), radius: 12, y: 3)
        }
        .buttonStyle(.plain)
        .help(isChinese ? "切换到英文输入法" : "Switch to English input")
    }
}

private struct SessionInfoHintRow: View {
    let isChinese: Bool
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 360, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            ZStack {
                Color.clear
                    .background(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.accentColor.opacity(0.10),
                        Color.blue.opacity(0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        .help(isChinese ? "随机提示" : "Random tip")
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
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .inset(by: 1)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
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
        Color.accentColor.opacity(0.18),
        Color(nsColor: .windowBackgroundColor),
        Color.black.opacity(0.06),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

struct IDataAnimationsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var idataAnimationsEnabled: Bool {
        get { self[IDataAnimationsEnabledKey.self] }
        set { self[IDataAnimationsEnabledKey.self] = newValue }
    }
}

final class CommandKeyMonitor: ObservableObject {
    @Published var isCommandPressed = NSEvent.modifierFlags.contains(.command)

    private var localMonitor: Any?

    init() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.isCommandPressed = event.modifierFlags.contains(.command)
            return event
        }
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}

final class InputSourceMonitor: NSObject, ObservableObject {
    @Published private(set) var displayName = localizedText(appShellLanguage() == .chinese, english: "Unknown", chinese: "未知")
    @Published private(set) var isLikelyEnglish = false

    private let notificationName = Notification.Name(rawValue: kTISNotifySelectedKeyboardInputSourceChanged as String)

    override init() {
        super.init()
        refreshCurrentInputSource()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleInputSourceDidChange),
            name: notificationName,
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self, name: notificationName, object: nil)
    }

    @objc
    private func handleInputSourceDidChange(_: Notification) {
        refreshCurrentInputSource()
    }

    @objc
    private func refreshCurrentInputSourceOnMainThread() {
        refreshCurrentInputSource()
    }

    private func refreshCurrentInputSource() {
        if !Thread.isMainThread {
            performSelector(onMainThread: #selector(refreshCurrentInputSourceOnMainThread), with: nil, waitUntilDone: false)
            return
        }

        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            displayName = localizedText(appShellLanguage() == .chinese, english: "Unknown", chinese: "未知")
            isLikelyEnglish = false
            return
        }

        let localizedName = Self.readInputSourceString(source: source, key: kTISPropertyLocalizedName) ?? localizedText(appShellLanguage() == .chinese, english: "Unknown", chinese: "未知")
        let sourceID = Self.readInputSourceString(source: source, key: kTISPropertyInputSourceID) ?? ""
        let inputModeID = Self.readInputSourceString(source: source, key: kTISPropertyInputModeID) ?? ""

        displayName = localizedName
        isLikelyEnglish = Self.looksEnglish(sourceID: sourceID, inputModeID: inputModeID, localizedName: localizedName)
    }

    private static func readInputSourceString(source: TISInputSource, key: CFString) -> String? {
        guard let rawValue = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        let value = Unmanaged<CFTypeRef>.fromOpaque(rawValue).takeUnretainedValue()
        guard CFGetTypeID(value) == CFStringGetTypeID() else {
            return nil
        }

        return value as? String
    }

    static func looksEnglish(sourceID: String, inputModeID: String, localizedName: String) -> Bool {
        let source = sourceID.lowercased()
        let mode = inputModeID.lowercased()
        let name = localizedName.lowercased()

        if source.contains("com.apple.keylayout.abc") || source.contains("com.apple.keylayout.us") {
            return true
        }

        if source.hasSuffix(".abc") || source.hasSuffix(".u.s") || source.hasSuffix(".us") {
            return true
        }

        if mode.contains("roman") || mode.contains("ascii") || mode.contains("latin") || mode.contains("english") {
            return true
        }

        return name == "abc" || name == "u.s." || name == "us" || name.contains("english")
    }

    @discardableResult
    func switchToEnglishInputSource() -> Bool {
        let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        var bestCandidate: TISInputSource?
        var bestScore = Int.min

        for rawSource in sources {
            let source = rawSource as! TISInputSource
            guard Self.isSelectCapable(source: source) else {
                continue
            }

            let sourceID = Self.readInputSourceString(source: source, key: kTISPropertyInputSourceID) ?? ""
            let inputModeID = Self.readInputSourceString(source: source, key: kTISPropertyInputModeID) ?? ""
            let localizedName = Self.readInputSourceString(source: source, key: kTISPropertyLocalizedName) ?? ""
            let score = Self.englishInputSourceScore(sourceID: sourceID, inputModeID: inputModeID, localizedName: localizedName)
            guard score > bestScore else {
                continue
            }
            bestScore = score
            bestCandidate = source
        }

        guard let bestCandidate, Self.shouldSelectEnglishCandidate(score: bestScore) else {
            return false
        }

        let status = TISSelectInputSource(bestCandidate)
        if status == noErr {
            refreshCurrentInputSource()
            return true
        }

        return false
    }

    static func englishInputSourceScore(sourceID: String, inputModeID: String, localizedName: String) -> Int {
        let source = sourceID.lowercased()
        let mode = inputModeID.lowercased()
        let name = localizedName.lowercased()

        if source.contains("com.apple.keylayout.abc") {
            return 500
        }
        if source.contains("com.apple.keylayout.us") {
            return 450
        }
        if source.contains("abc") {
            return 420
        }
        if source.hasSuffix(".u.s") || source.hasSuffix(".us") {
            return 390
        }
        if mode.contains("roman") || mode.contains("ascii") || mode.contains("latin") || mode.contains("english") {
            return 320
        }
        if name == "abc" || name == "u.s." || name == "us" || name.contains("english") {
            return 260
        }
        return -1000
    }

    static func shouldSelectEnglishCandidate(score: Int) -> Bool {
        score > 0
    }

    private static func isSelectCapable(source: TISInputSource) -> Bool {
        guard let rawValue = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else {
            return false
        }

        let value = Unmanaged<CFTypeRef>.fromOpaque(rawValue).takeUnretainedValue()
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return false
        }

        return CFBooleanGetValue((value as! CFBoolean))
    }
}

private struct QuietInteractiveSurfaceModifier: ViewModifier {
    let enabled: Bool
    let hoverScale: CGFloat
    let hoverYOffset: CGFloat
    let shadowOpacity: Double
    let shadowRadius: CGFloat

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(enabled && isHovering ? hoverScale : 1)
            .offset(y: enabled && isHovering ? hoverYOffset : 0)
            .shadow(
                color: .black.opacity(enabled && isHovering ? shadowOpacity : 0),
                radius: enabled && isHovering ? shadowRadius : 0,
                y: enabled && isHovering ? max(2, shadowRadius * 0.35) : 0
            )
            .animation(enabled ? .easeOut(duration: 0.24) : nil, value: isHovering)
            .onHover { hovering in
                if enabled {
                    isHovering = hovering
                } else {
                    isHovering = false
                }
            }
    }
}

extension View {
    func quietInteractiveSurface(
        enabled: Bool,
        hoverScale: CGFloat = 1.01,
        hoverYOffset: CGFloat = -1.5,
        shadowOpacity: Double = 0.14,
        shadowRadius: CGFloat = 16
    ) -> some View {
        modifier(
            QuietInteractiveSurfaceModifier(
                enabled: enabled,
                hoverScale: hoverScale,
                hoverYOffset: hoverYOffset,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius
            )
        )
    }
}

struct VersionPill: View {
    @ObservedObject var model: AppModel
    let tint: Color
    var icon: String? = "shippingbox"

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
            }

            Text(model.appVersionSummary)
                .font(.subheadline.weight(.semibold))
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.04))
        )
        .quietInteractiveSurface(enabled: false)
    }
}

private struct StatusPill: View {
    let title: String
    let tint: Color
    var icon: String? = nil
    @Environment(\EnvironmentValues.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint, in: Capsule())
        .quietInteractiveSurface(
            enabled: idataAnimationsEnabled && !accessibilityReduceMotion,
            hoverScale: 1.012,
            hoverYOffset: -0.5,
            shadowOpacity: 0.08,
            shadowRadius: 8
        )
    }
}

private struct SummaryCard: View {
    let title: String
    let icon: String
    let detail: String
    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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

private struct FormatChip: View {
    let title: String
    let extensionText: String
    let isDefault: Bool
    let isLoading: Bool
    let isChinese: Bool
    let onTap: () -> Void
    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var statusRow: some View {
        HStack(spacing: 4) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text(localizedText(isChinese, english: "Setting...", chinese: "正在设置..."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .opacity(isDefault ? 1 : 0)
                Text(localizedText(isChinese, english: "Default", chinese: "默认"))
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .opacity(isDefault ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 14, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(".\(extensionText)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            statusRow
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isDefault ? Color.green.opacity(0.3) : Color.white.opacity(0.06))
        )
        .overlay(alignment: .bottom) {
            if isDefault && !isLoading {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.green)
                    .frame(height: 3)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isLoading {
                onTap()
            }
        }
        .quietInteractiveSurface(
            enabled: idataAnimationsEnabled && !accessibilityReduceMotion,
            hoverScale: 1.012,
            hoverYOffset: -1,
            shadowOpacity: 0.06,
            shadowRadius: 8
        )
        .animation(.easeInOut(duration: 0.2), value: isDefault)
    }
}

private struct QuickTip: Identifiable {
    let id = UUID()
    let keys: String
    let title: String
    let detail: String
}

private struct MessageCard: View {
    let title: String
    let message: String
    let color: Color
    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .quietInteractiveSurface(
            enabled: idataAnimationsEnabled && !accessibilityReduceMotion,
            hoverScale: 1.006,
            hoverYOffset: -0.5,
            shadowOpacity: 0.05,
            shadowRadius: 8
        )
    }
}
