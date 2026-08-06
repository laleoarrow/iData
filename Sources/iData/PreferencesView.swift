import AppKit
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdaterController
    @State private var selectedTab: PreferencesTab = .general
    @State private var customAssociationInput = ""

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    private var normalizedCustomAssociationExtension: String {
        AppModel.associationExtension(for: customAssociationInput)
    }

    private var canSubmitCustomAssociation: Bool {
        AppModel.canSetAssociationExtensionInput(customAssociationInput) && !model.isSettingFormatDefault
    }

    private var isCustomAssociationDefault: Bool {
        guard !normalizedCustomAssociationExtension.isEmpty else {
            return false
        }
        return model.formatAssociationStatus[normalizedCustomAssociationExtension] ?? false
    }

    private var displayedFormatExtensions: [String] {
        AppModel.formatPanelFormats.map(\.fileExtension)
    }

    private var orderedSupportedFormats: [(format: AppModel.SupportedFormat, isDefault: Bool)] {
        AppModel.formatPanelFormats.map { format in
            let lookupExtension = AppModel.associationExtension(for: format.fileExtension)
            let isDefault = model.formatAssociationStatus[lookupExtension]
                ?? model.formatAssociationStatus[format.fileExtension]
                ?? false
            return (format, isDefault)
        }
    }

    var body: some View {
        let dependencyState = model.visiDataDependencyState

        TabView(selection: $selectedTab) {
            generalTab(dependencyState: dependencyState)
                .tabItem {
                    Label(isChinese ? "通用" : "General", systemImage: "gearshape")
                }
                .tag(PreferencesTab.general)

            filesTab
                .tabItem {
                    Label(isChinese ? "文件" : "Files", systemImage: "doc")
                }
                .tag(PreferencesTab.files)

            runtimeTab(dependencyState: dependencyState)
                .tabItem {
                    Label("VisiData", systemImage: "terminal")
                }
                .tag(PreferencesTab.runtime)

            updatesTab
                .tabItem {
                    Label(isChinese ? "更新" : "Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(PreferencesTab.updates)
        }
        .frame(width: 640, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.idataAnimationsEnabled, model.animationsEnabled)
        .onAppear(perform: refreshFormatAssociations)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshFormatAssociations()
        }
        .onChange(of: normalizedCustomAssociationExtension) { _, newValue in
            guard !newValue.isEmpty else {
                return
            }
            model.refreshFormatAssociationStatuses(forExtensions: [newValue])
        }
    }

    private func generalTab(dependencyState: AppModel.VisiDataDependencyState) -> some View {
        Form {
            Section {
                Picker(isChinese ? "语言" : "Language", selection: $model.appLanguagePreference) {
                    ForEach(AppModel.AppLanguagePreference.allCases) { option in
                        Text(model.appLanguageOptionTitle(option))
                            .tag(option)
                    }
                }

                Toggle(isChinese ? "减少动画" : "Reduce motion", isOn: $model.reduceAnimations)
            } footer: {
                Text(isChinese ? "系统“减少动态效果”始终优先。" : "System Reduce Motion always takes priority.")
            }

            Section(isChinese ? "状态" : "Status") {
                LabeledContent(isChinese ? "版本" : "Version") {
                    Text(model.appVersionDisplay(revealingBuild: false))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("VisiData") {
                    Label(
                        visiDataStatusTitle(for: dependencyState),
                        systemImage: dependencyState.isAvailable
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(dependencyState.isAvailable ? .green : .orange)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var filesTab: some View {
        Form {
            Section {
                Toggle(
                    isChinese ? "转交小文件" : "Hand Off Small Files",
                    isOn: $model.isSmallFileHandoffEnabled
                )

                LabeledContent(isChinese ? "转交给" : "Hand off to") {
                    Text(model.preferredSmallFileApplicationDisplayName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .disabled(!model.isSmallFileHandoffEnabled)

                HStack {
                    Button(isChinese ? "选择应用…" : "Choose App…") {
                        model.choosePreferredSmallFileApplication()
                    }

                    Button(isChinese ? "测试打开" : "Test Open") {
                        testSmallFileHandoff()
                    }

                    Spacer()

                    Button(isChinese ? "恢复默认" : "Restore Default") {
                        model.clearPreferredSmallFileApplication()
                    }
                    .disabled(model.preferredSmallFileApplication == nil)
                }
                .disabled(!model.isSmallFileHandoffEnabled)
            } header: {
                Text(isChinese ? "小文件" : "Small Files")
            } footer: {
                Text(model.isSmallFileHandoffEnabled
                    ? (isChinese
                        ? "从 Finder 打开的表格不超过 \(AppModel.smallFileRoutingThresholdDisplay) 时转交；压缩文件仍由 iData 打开。"
                        : "Tables opened from Finder are handed off up to \(AppModel.smallFileRoutingThresholdDisplay). Compressed files stay in iData.")
                    : (isChinese
                        ? "从 Finder 打开的表格将直接留在 iData。"
                        : "Tables opened from Finder stay in iData."))
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                    ForEach(orderedSupportedFormats, id: \.format.fileExtension) { entry in
                        FormatChip(
                            title: entry.format.localizedDisplayName(for: model.effectiveLanguage),
                            extensionText: entry.format.fileExtension,
                            isDefault: entry.isDefault,
                            isLoading: model.isSettingFormatDefault
                                && model.settingFormatExtension == entry.format.fileExtension,
                            isChinese: isChinese,
                            onTap: {
                                model.setFormatAsDefault(forExtension: entry.format.fileExtension)
                            }
                        )
                    }
                }

                LabeledContent(isChinese ? "自定义后缀" : "Custom Suffix") {
                    HStack(spacing: 8) {
                        TextField(
                            text: $customAssociationInput,
                            prompt: Text(isChinese ? "例如 .bed" : "e.g. .bed")
                        ) {
                            Text(isChinese ? "文件扩展名" : "File Extension")
                        }
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit(setCustomAssociation)

                        Button(customAssociationActionTitle, action: setCustomAssociation)
                            .disabled(!canSubmitCustomAssociation)
                    }
                }

                if !normalizedCustomAssociationExtension.isEmpty {
                    Label(
                        customAssociationStatusTitle,
                        systemImage: isCustomAssociationDefault ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption)
                    .foregroundStyle(isCustomAssociationDefault ? .green : .secondary)
                }
            } header: {
                HStack {
                    Text(isChinese ? "默认打开方式" : "Default Applications")
                    Spacer()
                    Button {
                        refreshFormatAssociations()
                    } label: {
                        Label(isChinese ? "刷新" : "Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            } footer: {
                Text(isChinese ? "点击格式设为 iData；再次点击恢复原应用。" : "Click a format to use iData; click again to restore the previous app.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func runtimeTab(dependencyState: AppModel.VisiDataDependencyState) -> some View {
        Form {
            Section {
                TextField("/opt/homebrew/bin/vd", text: $model.vdExecutablePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                HStack {
                    Button(isChinese ? "选择…" : "Choose…") {
                        model.chooseVDExecutable()
                    }

                    Button(isChinese ? "自动检测" : "Auto Detect") {
                        model.vdExecutablePath = ""
                    }

                    if case .missing = dependencyState {
                        Button(isChinese ? "安装 VisiData" : "Install VisiData") {
                            model.runVisiDataOneClickSetup()
                        }
                    }
                }
            } header: {
                Text(isChinese ? "可执行文件" : "Executable")
            } footer: {
                Text(model.visiDataDependencySummary(for: dependencyState))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var updatesTab: some View {
        Form {
            Section {
                Toggle(
                    isChinese ? "自动检查更新" : "Automatically check for updates",
                    isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticallyChecksForUpdates($0) }
                    )
                )

                Toggle(
                    isChinese ? "自动下载更新" : "Automatically download updates",
                    isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.setAutomaticallyDownloadsUpdates($0) }
                    )
                )
                .disabled(!updater.automaticallyChecksForUpdates)

                HStack {
                    Button(isChinese ? "检查更新" : "Check for Updates") {
                        updater.checkForUpdates()
                    }

                    Button(isChinese ? "查看发布页" : "View Releases") {
                        NSWorkspace.shared.open(updater.releasesURL)
                    }
                }
            } footer: {
                Text(updater.statusMessage)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func visiDataStatusTitle(for dependencyState: AppModel.VisiDataDependencyState) -> String {
        switch dependencyState {
        case .available:
            isChinese ? "已就绪" : "Ready"
        case .missing:
            isChinese ? "未安装" : "Not Installed"
        }
    }

    private var customAssociationActionTitle: String {
        if isCustomAssociationDefault {
            return isChinese ? "恢复原应用" : "Restore"
        }
        return isChinese ? "设为 iData" : "Use iData"
    }

    private var customAssociationStatusTitle: String {
        if model.isSettingFormatDefault,
           AppModel.associationExtension(for: model.settingFormatExtension ?? "")
            == normalizedCustomAssociationExtension {
            return isChinese ? "设置中…" : "Updating…"
        }
        if isCustomAssociationDefault {
            return isChinese ? ".\(normalizedCustomAssociationExtension) 已使用 iData" : ".\(normalizedCustomAssociationExtension) uses iData"
        }
        return isChinese ? ".\(normalizedCustomAssociationExtension) 使用其他应用" : ".\(normalizedCustomAssociationExtension) uses another app"
    }

    private func setCustomAssociation() {
        guard canSubmitCustomAssociation else {
            return
        }
        model.setFormatAsDefault(forExtension: customAssociationInput)
    }

    private func refreshFormatAssociations() {
        model.refreshFormatAssociationStatuses(forExtensions: displayedFormatExtensions)
    }

    private func testSmallFileHandoff() {
        do {
            _ = try model.testSmallFileHandoff()
        } catch {
            model.statusMessage = nil
            model.errorMessage = model.localized(
                english: "Could not prepare the handoff test: \(error.localizedDescription)",
                chinese: "无法准备测试：\(error.localizedDescription)"
            )
        }
    }
}

private enum PreferencesTab: Hashable {
    case general
    case files
    case runtime
    case updates
}

extension AppModel.VisiDataDependencyState {
    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }
}
