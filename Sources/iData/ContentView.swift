import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdaterController
    private let sidebarWidth: CGFloat = 292

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
        .frame(minWidth: 960, minHeight: 620)
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

    private var listAnimation: Animation? {
        model.animationsEnabled && !accessibilityReduceMotion
            ? .spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.15)
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

            VStack(spacing: 16) {
                SidebarHeaderCard(model: model)

                if model.recentFiles.isEmpty {
                    EmptySidebarState()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(model.recentFiles, id: \.path) { fileURL in
                                RecentFileRow(
                                    fileURL: fileURL,
                                    isActive: model.activeSession?.currentFileURL?.standardizedFileURL == fileURL.standardizedFileURL,
                                    isPinned: model.isPinnedRecentFile(fileURL),
                                    openAction: { model.openExternalFile(fileURL) },
                                    togglePinAction: { model.togglePinnedRecentFile(fileURL) },
                                    removeAction: { model.removeRecentFile(fileURL) }
                                )
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .scale(scale: 0.96).combined(with: .opacity)
                                    )
                                )
                            }
                        }
                        .padding(.horizontal, 2)
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

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

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
                    }

                    Text("Native shell for large-table workflows with VisiData")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
}

private struct SidebarFooter: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    var body: some View {
        HStack(spacing: 10) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .quietInteractiveSurface(enabled: motionEnabled)

            Button {
                model.isHelpPresented = true
            } label: {
                Label("Help", systemImage: "questionmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .quietInteractiveSurface(enabled: motionEnabled)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
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
                        .lineLimit(2)

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

private struct SessionStageView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdaterController
    @ObservedObject var session: VisiDataSessionController

    var body: some View {
        if session.isRunning, session.currentFileURL != nil {
            SessionDetailView(model: model, session: session)
        } else {
            WelcomeDetailView(model: model, updater: updater)
        }
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

private struct WelcomeDetailView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdaterController
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heroCard
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

                        VersionRevealPill(model: model, tint: .white.opacity(0.14), icon: "shippingbox")
                    }

                    Text("Open large tables in a native macOS shell while keeping real VisiData behavior, shortcuts, and speed.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        dependencyPill

                        if let lastOpenedFile = model.lastOpenedFile {
                            StatusPill(title: "Last: \(lastOpenedFile.lastPathComponent)", tint: .white.opacity(0.10))
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(AppModel.supportedFormats, id: \.fileExtension) { format in
                    FormatChip(title: format.displayName, extensionText: format.fileExtension)
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

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.currentFileURL?.lastPathComponent ?? "VisiData Session")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(session.currentFileURL?.path ?? "No file loaded")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                if let fileURL = session.currentFileURL {
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
                MessageCard(
                    title: "Status",
                    message: statusMessage,
                    color: .green.opacity(0.12)
                )
            }
        }
        .padding(24)
        .background(detailBackground.ignoresSafeArea())
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

struct VersionRevealPill: View {
    @ObservedObject var model: AppModel
    let tint: Color
    var icon: String? = "shippingbox"

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @StateObject private var commandMonitor = CommandKeyMonitor()
    @State private var isHovering = false

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    private var revealsBuild: Bool {
        isHovering && commandMonitor.isCommandPressed
    }

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
            }

            Text(model.appVersionSummary)
                .font(.subheadline.weight(.semibold))

            if revealsBuild {
                Text("build \(model.appBuildNumber)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.10))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(revealsBuild ? 0.14 : 0.04))
        )
        .quietInteractiveSurface(
            enabled: motionEnabled,
            hoverScale: 1.015,
            hoverYOffset: -1,
            shadowOpacity: 0.10,
            shadowRadius: 10
        )
        .animation(motionEnabled ? .easeOut(duration: 0.28) : nil, value: revealsBuild)
        .onHover { hovering in
            if motionEnabled {
                withAnimation(.easeOut(duration: 0.18)) {
                    isHovering = hovering
                }
            } else {
                isHovering = hovering
            }
        }
        .help("Hold Command while hovering to reveal the build number")
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
    @Environment(\.idataAnimationsEnabled) private var idataAnimationsEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(".\(extensionText)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06))
        )
        .quietInteractiveSurface(
            enabled: idataAnimationsEnabled && !accessibilityReduceMotion,
            hoverScale: 1.012,
            hoverYOffset: -1,
            shadowOpacity: 0.06,
            shadowRadius: 8
        )
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
