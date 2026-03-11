import AppKit
import Carbon.HIToolbox
import SwiftUI

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
                Button("Open…") {
                    model.openDocument()
                }
                .keyboardShortcut("o")

                Button("Reopen") {
                    model.reopenLastFile()
                }
                .disabled(model.lastOpenedFile == nil)
            }
        }
        .sheet(isPresented: $model.isHelpPresented) {
            HelpView()
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
                        EmptySidebarState()
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
                                            openAction: { model.openExternalFile(fileURL) },
                                            removeAction: { model.removeRecentFile(fileURL) }
                                        )
                                    } else {
                                        RecentFileRow(
                                            fileURL: fileURL,
                                            isActive: model.activeSession?.currentFileURL?.standardizedFileURL == fileURL.standardizedFileURL,
                                            isPinned: model.isPinnedRecentFile(fileURL),
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
                            Button("Clear All") {
                                model.clearRecentFiles()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.02, hoverYOffset: -1)
                            .help("Clear all recent file records")
                        }

                        SidebarCollapseToggleButton(
                            isCollapsed: false,
                            motionEnabled: motionEnabled,
                            action: { model.toggleSidebarCollapsed() }
                        )
                    }

                    Text("Native shell for large-table workflows with VisiData")
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

    var body: some View {
        Group {
            if model.isSidebarCollapsed {
                VStack(spacing: 18) {
                    SettingsLink {
                        SidebarFooterIcon(symbol: "gearshape.fill")
                            .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.05, hoverYOffset: -1)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")

                    Button {
                        model.isHelpPresented = true
                    } label: {
                        SidebarFooterIcon(symbol: "questionmark.circle")
                            .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.05, hoverYOffset: -1)
                    }
                    .buttonStyle(.plain)
                    .help("Help")

                    Button {
                        model.presentTutorialHub()
                    } label: {
                        SidebarFooterIcon(symbol: "graduationcap.fill")
                            .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.05, hoverYOffset: -1)
                    }
                    .buttonStyle(.plain)
                    .help(model.effectiveTutorialLanguage == .chinese ? "教程" : "Tutorial")
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 18) {
                    SettingsLink {
                        SidebarFooterIcon(symbol: "gearshape.fill")
                            .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.05, hoverYOffset: -1)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")

                    Button {
                        model.isHelpPresented = true
                    } label: {
                        SidebarFooterIcon(symbol: "questionmark.circle")
                            .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.05, hoverYOffset: -1)
                    }
                    .buttonStyle(.plain)
                    .help("Help")

                    Button {
                        model.presentTutorialHub()
                    } label: {
                        SidebarFooterIcon(symbol: "graduationcap.fill")
                            .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.05, hoverYOffset: -1)
                    }
                    .buttonStyle(.plain)
                    .help(model.effectiveTutorialLanguage == .chinese ? "教程" : "Tutorial")

                    Spacer(minLength: 0)
                }
            }
        }
        .foregroundStyle(.secondary)
    }
}

private struct EmptySidebarState: View {
    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("No recent files yet", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.headline)

            Text("Open a table or drag one into the window. Recent items stay here for one-click reopening.")
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
            .help(isPinned ? "Unpin from top" : "Pin to top")

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
            .help("Remove from recent files")
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
            return "Remove \(fileURL.lastPathComponent) from recent files"
        }
        return "Open \(fileURL.lastPathComponent)"
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
        .help(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
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
        session.isRunning && session.currentFileURL != nil
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    private let onboardingTips: [QuickTip] = [
        QuickTip(keys: "Open… / Drag File", title: "Open Data", detail: "Use the toolbar or drag a file into the main window. iData forwards the real file into embedded VisiData."),
        QuickTip(keys: "Recent + Pin", title: "Keep Key Files", detail: "Click a recent item to reopen it. Pin important files so they stay fixed at the top of the sidebar."),
        QuickTip(keys: "⌘,", title: "Settings", detail: "Adjust the `vd` path, automatic update behavior, or run a manual update check."),
    ]

    private let softwareTips: [QuickTip] = [
        QuickTip(keys: ".csv / .tsv / .ma", title: "Direct Open", detail: "Most regular text-like table files open directly, including unusual bioinformatics suffixes such as `.ma`."),
        QuickTip(keys: ".gz / .bgz", title: "Stream Compression", detail: "Compressed files are streamed into VisiData without extracting them to disk first."),
        QuickTip(keys: "Excel", title: "About `.xlsx`", detail: "VisiData can read Excel, but that depends on the Python environment having the required loader installed. If Excel fails, install the missing VisiData dependency in the same Python environment as `vd`."),
    ]

    private let visiDataTips: [QuickTip] = [
        QuickTip(keys: "hjkl / ←↑↓→", title: "Move", detail: "Navigate cells and columns without leaving the keyboard."),
        QuickTip(keys: "/  ?  n  N", title: "Search", detail: "Search forward or backward, then jump through matches."),
        QuickTip(keys: "[  ]", title: "Sort", detail: "Sort the current column ascending or descending."),
        QuickTip(keys: "s  t  u", title: "Select", detail: "Select, toggle, or unselect rows for later commands."),
        QuickTip(keys: "z?", title: "Command Help", detail: "Discover sheet-specific commands and see what VisiData can do on the current data."),
        QuickTip(keys: "q", title: "Back / Quit Sheet", detail: "Go back from a derived sheet or quit the session when you are done."),
    ]

    private var motionEnabled: Bool {
        !accessibilityReduceMotion
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                helpHero
                helpSection(title: "Using iData", tips: onboardingTips)
                helpSection(title: "File Loading Notes", tips: softwareTips)
                helpSection(title: "Common VisiData Shortcuts", tips: visiDataTips)
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
                        Text("iData Help")
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
                        .help("Close Help")
                        .keyboardShortcut(.cancelAction)
                    }

                    Text("iData is a native macOS shell around real VisiData. The outer app handles opening files, history, updates, and settings; the main table view remains genuine VisiData, so normal VisiData commands still apply inside the session.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        StatusPill(title: "Native macOS shell", tint: .white.opacity(0.12), icon: "macwindow")
                        StatusPill(title: "Real VisiData core", tint: Color.accentColor.opacity(0.20), icon: "terminal")
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
        model.effectiveTutorialLanguage == .chinese
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
                    Text(isChinese ? "Tutorial 清单" : "Tutorial Checklist")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text(isChinese ? "选择一个章节开始练习。完成的章节会自动打勾。" : "Choose a chapter to practice. Completed chapters are checked automatically.")
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
                    title: model.tutorialLanguageBadgeText,
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

    private let quickTips: [QuickTip] = [
        QuickTip(keys: "hjkl / ←↑↓→", title: "Move", detail: "Navigate rows and columns quickly without leaving the keyboard."),
        QuickTip(keys: "/  ?  n  N", title: "Search", detail: "Search forward or backward in the current sheet, then jump to next or previous match."),
        QuickTip(keys: "s  t  u", title: "Select Rows", detail: "Select, toggle, or unselect rows before profiling or exporting."),
        QuickTip(keys: "[  ]", title: "Sort", detail: "Sort the current column ascending or descending."),
        QuickTip(keys: "Ctrl+H", title: "Help", detail: "Open the command and help menu to discover any VisiData action.")
    ]

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var basicPreviewSteps: [AppModel.TutorialStep] {
        model.tutorialChapters
            .first(where: { $0.id == AppModel.defaultTutorialChapterID })?
            .steps ?? []
    }

    private var isChinese: Bool {
        model.effectiveTutorialLanguage == .chinese
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

    private var orderedSupportedFormats: [(format: AppModel.SupportedFormat, isDefault: Bool)] {
        let snapshot = AppModel.supportedFormats.enumerated().map { index, format in
            let isDefault = model.formatAssociationStatus[format.fileExtension]
                ?? model.checkFormatAssociation(forExtension: format.fileExtension)
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
                        title: "Launch Error",
                        message: errorMessage,
                        color: .red.opacity(0.14)
                    )
                } else if let statusMessage = model.statusMessage {
                    MessageCard(
                        title: "Status",
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
            HStack(alignment: .top, spacing: 18) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: 18, y: 8)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("iData")
                            .font(.system(size: 38, weight: .bold, design: .rounded))

                        VersionPill(model: model, tint: .white.opacity(0.14), icon: "shippingbox")

                        if showsReadyDependencyPillInTitleRow {
                            dependencyPill
                        }
                    }

                    Text("Open large tables in a native macOS shell while keeping real VisiData behavior, shortcuts, and speed.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if showsHeroMetadataRow {
                        HStack(spacing: 10) {
                            if case .missing = model.visiDataDependencyState {
                                dependencyPill
                            }

                            if let lastOpenedFile = model.lastOpenedFile {
                                StatusPill(title: "Last: \(lastOpenedFile.lastPathComponent)", tint: .white.opacity(0.10))
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    model.openDocument()
                } label: {
                    Label("Open File", systemImage: "tablecells")
                }
                .buttonStyle(.borderedProminent)
                .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.012, hoverYOffset: -1.5)

                if case .missing = model.visiDataDependencyState {
                    Button {
                        model.runVisiDataOneClickSetup()
                    } label: {
                        Label("Install VisiData", systemImage: "shippingbox")
                    }
                    .buttonStyle(.borderedProminent)
                    .quietInteractiveSurface(enabled: motionEnabled, hoverScale: 1.012, hoverYOffset: -1.5)
                }

                Button {
                    model.presentTutorialHub()
                } label: {
                    Label("Start Tutorial", systemImage: "graduationcap.fill")
                }
                .buttonStyle(.bordered)
                .quietInteractiveSurface(enabled: motionEnabled)

                Button {
                    updater.checkForUpdates()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.trianglehead.clockwise")
                }
                .buttonStyle(.bordered)
                .quietInteractiveSurface(enabled: motionEnabled)

                SettingsLink {
                    Label("Preferences", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .quietInteractiveSurface(enabled: motionEnabled)

                if let fileURL = model.lastOpenedFile {
                    Button {
                        model.revealInFinder(fileURL)
                    } label: {
                        Label("Show Last File", systemImage: "finder")
                    }
                    .buttonStyle(.bordered)
                    .quietInteractiveSurface(enabled: motionEnabled)
                }

                Link(destination: repositoryURL) {
                    Label("GitHub", systemImage: "link")
                }
                .buttonStyle(.bordered)
                .quietInteractiveSurface(enabled: motionEnabled)
                .help("Give a star if you like iData ✨")
            }

            Text("Tip: drag a supported table file into this window to open it directly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Most bioinformatics suffixes are passed through directly. Compressed `.gz` / `.bgz` files are streamed without extracting.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            return AnyView(StatusPill(title: "VisiData Ready", tint: .green.opacity(0.20), icon: "checkmark.circle.fill"))
        case .missing:
            return AnyView(StatusPill(title: "Install VisiData", tint: .orange.opacity(0.22), icon: "exclamationmark.triangle.fill"))
        }
    }

    private var summaryCards: some View {
        HStack(alignment: .top, spacing: 14) {
            SummaryCard(
                title: "Runtime",
                icon: "waveform.path.ecg.rectangle",
                detail: "\(model.visiDataDependencySummary) Files are no longer restricted by suffix; iData only special-cases compressed gzip-like inputs."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            SummaryCard(
                title: "Updates",
                icon: "square.and.arrow.down",
                detail: updater.statusMessage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var quickTipsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("VisiData Quick Start")
                .font(.headline)

            Text("These are common starter shortcuts. All normal VisiData commands still work inside the embedded session.")
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
            Text("Supported Formats")
                .font(.headline)

            Text("These are common examples. iData now forwards most regular files directly to VisiData and only special-cases gzip-like compression.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Tip: click once to set iData as default; click again to restore the previous default app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(orderedSupportedFormats, id: \.format.fileExtension) { entry in
                    FormatChip(
                        title: entry.format.displayName,
                        extensionText: entry.format.fileExtension,
                        isDefault: entry.isDefault,
                        isLoading: model.isSettingFormatDefault && model.settingFormatExtension == entry.format.fileExtension,
                        onTap: {
                            model.setFormatAsDefault(forExtension: entry.format.fileExtension)
                        }
                    )
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 10) {
                Text("Custom Suffix")
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
                        Label("Set Default to iData", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmitCustomAssociation)
                    .quietInteractiveSurface(enabled: motionEnabled)
                }

                if !normalizedCustomAssociationExtension.isEmpty {
                    HStack(spacing: 8) {
                        Text("Suffix: .\(normalizedCustomAssociationExtension)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if isSettingCustomAssociation {
                            ProgressView()
                                .controlSize(.small)
                            Text("Setting...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if isCustomAssociationDefault {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("Default: iData")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                } else {
                    Text("Enter a suffix to set its default handler to iData.")
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
        model.effectiveTutorialLanguage == .chinese
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
                    Text(session.currentFileURL?.lastPathComponent ?? "VisiData Session")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(session.currentFileURL?.path ?? "No file loaded")
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
                                Label("Show in Finder", systemImage: "finder")
                            }
                            .buttonStyle(.bordered)
                            .quietInteractiveSurface(enabled: motionEnabled)

                            Button {
                                model.copyPathToPasteboard(fileURL)
                            } label: {
                                Label("Copy Path", systemImage: "doc.on.doc")
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
                    title: "Launch Error",
                    message: errorMessage,
                    color: .red.opacity(0.12)
                )
            } else if let errorMessage = session.errorMessage {
                MessageCard(
                    title: "Session Error",
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
    return normalized.contains("running visidata") || normalized.contains("正在运行 visidata")
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
        model.effectiveTutorialLanguage == .chinese
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
                        .help("Jump to step \(item.index + 1)")
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
    @Published private(set) var displayName = "Unknown"
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
            displayName = "Unknown"
            isLikelyEnglish = false
            return
        }

        let localizedName = Self.readInputSourceString(source: source, key: kTISPropertyLocalizedName) ?? "Unknown"
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
    let onTap: () -> Void
    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var statusRow: some View {
        HStack(spacing: 4) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text("Setting...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .opacity(isDefault ? 1 : 0)
                Text("Default")
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
