import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                sidebarHeader

                if model.recentFiles.isEmpty {
                    ContentUnavailableView(
                        "No Recent Files",
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        description: Text("Open a table or drag one into the window to start.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(model.recentFiles, id: \.path) { fileURL in
                        RecentFileRow(
                            fileURL: fileURL,
                            isActive: model.activeSession?.currentFileURL?.standardizedFileURL == fileURL.standardizedFileURL,
                            openAction: { model.openExternalFile(fileURL) },
                            removeAction: { model.removeRecentFile(fileURL) }
                        )
                        .contextMenu {
                            Button("Open in VisiData") {
                                model.openExternalFile(fileURL)
                            }

                            Button("Show in Finder") {
                                model.revealInFinder(fileURL)
                            }

                            Button("Copy Path") {
                                model.copyPathToPasteboard(fileURL)
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
        } detail: {
            detailContent
        }
        .frame(minWidth: 900, minHeight: 560)
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
        if let session = model.activeSession {
            SessionDetailView(model: model, session: session)
        } else {
            WelcomeDetailView(model: model)
        }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 12) {
            Text("Recent Files")
                .font(.headline)

            Spacer()

            if !model.recentFiles.isEmpty {
                Button("Clear All") {
                    model.clearRecentFiles()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear all recent file records")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileURL.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    Text(fileURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 12)

            Button(action: removeAction) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(isHovering ? 0.08 : 0.0))
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        .listRowSeparator(.hidden)
    }

    private var rowBackground: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(.regularMaterial)
        }

        if isHovering {
            return AnyShapeStyle(Color.white.opacity(0.04))
        }

        return AnyShapeStyle(.clear)
    }
}

private struct WelcomeDetailView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            actionRow
            infoCard

            if let errorMessage = model.errorMessage {
                MessageCard(
                    title: "Launch Error",
                    message: errorMessage,
                    color: .red.opacity(0.12)
                )
            } else if let statusMessage = model.statusMessage {
                MessageCard(
                    title: "Status",
                    message: statusMessage,
                    color: .green.opacity(0.12)
                )
            }

            Spacer()
        }
        .padding(32)
        .background(detailBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("iData")
                .font(.system(size: 40, weight: .bold, design: .rounded))

            Text("A native macOS shell for opening large tables with VisiData.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Use the native shell to pick files and manage recents, then keep the actual VisiData session inside the iData window.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                model.openDocument()
            } label: {
                Label("Open File", systemImage: "tablecells")
            }
            .buttonStyle(.borderedProminent)

            SettingsLink {
                Label("Preferences", systemImage: "gearshape")
            }

            if let fileURL = model.lastOpenedFile {
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
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Current Behavior")
                .font(.headline)

            InfoRow(title: "Viewer", value: "VisiData keeps full keyboard behavior and shortcuts")
            InfoRow(title: "Host", value: "iData runs VisiData inside an embedded terminal surface")
            InfoRow(title: "Dependency", value: "Requires VisiData (`brew install visidata`) unless you set a custom `vd` path in Preferences.")
            InfoRow(title: "Association", value: "Finder registration is currently focused on CSV / TSV; Open and drag-and-drop support more formats.")
            InfoRow(title: "Supported Formats", value: AppModel.supportedFormatHelpText)
            InfoRow(title: "Executable", value: model.vdExecutablePath.isEmpty ? "Auto-detect from PATH" : model.vdExecutablePath)

            if let lastOpenedFile = model.lastOpenedFile {
                Divider()
                InfoRow(title: "Last Opened", value: lastOpenedFile.path)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        .background(detailBackground)
    }
}

private let detailBackground = LinearGradient(
    colors: [
        Color.accentColor.opacity(0.18),
        Color.clear,
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .fontWeight(.semibold)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
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
