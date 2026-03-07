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
                                    openAction: { model.openExternalFile(fileURL) },
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
                    .animation(.spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.15), value: model.recentFiles)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}

private struct SidebarHeaderCard: View {
    @ObservedObject var model: AppModel

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
                    Text("iData")
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    Text("Native shell for large-table workflows with VisiData")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button {
                    model.openDocument()
                } label: {
                    Label("Open", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer(minLength: 0)

                if !model.recentFiles.isEmpty {
                    Button("Clear All") {
                        model.clearRecentFiles()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear all recent file records")
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
    }
}

private struct EmptySidebarState: View {
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
    }
}

private struct RecentFileRow: View {
    let fileURL: URL
    let isActive: Bool
    let openAction: () -> Void
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

private struct WelcomeDetailView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdaterController

    private let quickTips: [QuickTip] = [
        QuickTip(keys: "hjkl / ←↑↓→", title: "Move", detail: "Navigate rows and columns quickly without leaving the keyboard."),
        QuickTip(keys: "/  ?  n  N", title: "Search", detail: "Search forward or backward in the current sheet, then jump to next or previous match."),
        QuickTip(keys: "s  t  u", title: "Select Rows", detail: "Select, toggle, or unselect rows before profiling or exporting."),
        QuickTip(keys: "[  ]", title: "Sort", detail: "Sort the current column ascending or descending."),
        QuickTip(keys: "Ctrl+H", title: "Help", detail: "Open the command and help menu to discover any VisiData action.")
    ]

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

                        StatusPill(title: model.appVersionSummary, tint: .white.opacity(0.14))
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

                Button {
                    updater.checkForUpdates()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.trianglehead.clockwise")
                }
                .buttonStyle(.bordered)

                SettingsLink {
                    Label("Preferences", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)

                if let fileURL = model.lastOpenedFile {
                    Button {
                        model.revealInFinder(fileURL)
                    } label: {
                        Label("Show Last File", systemImage: "finder")
                    }
                    .buttonStyle(.bordered)
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

            SummaryCard(
                title: "Updates",
                icon: "square.and.arrow.down",
                detail: updater.statusMessage
            )
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

                    Button {
                        model.copyPathToPasteboard(fileURL)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
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

private struct StatusPill: View {
    let title: String
    let tint: Color
    var icon: String? = nil

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
    }
}

private struct SummaryCard: View {
    let title: String
    let icon: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
    }
}

private struct FormatChip: View {
    let title: String
    let extensionText: String

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
    }
}
