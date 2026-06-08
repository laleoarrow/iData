import SwiftUI

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdaterController
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
                preferencesHero
                smallFileRoutingCard
                animationsCard
                appLanguageCard
                runtimeCard
                updatesCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(width: 620, height: 660)
        .background(preferencesBackground.ignoresSafeArea())
        .environment(\EnvironmentValues.idataAnimationsEnabled, model.animationsEnabled)
    }

    private var preferencesHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Color.accentColor.opacity(0.24), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "偏好设置" : "Preferences")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text(isChinese ? "管理小文件转交、VisiData 路径与更新。" : "Manage handoff, VisiData path, and updates.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        VersionPill(model: model, tint: .white.opacity(0.12), icon: "shippingbox")

                        switch model.visiDataDependencyState {
                        case .available:
                            PreferencePill(title: isChinese ? "VisiData 已就绪" : "VisiData Ready", tint: .green.opacity(0.20), icon: "checkmark.circle.fill", animated: motionEnabled)
                        case .missing:
                            PreferencePill(title: isChinese ? "缺少 VisiData" : "VisiData Missing", tint: Color.primary.opacity(0.12), icon: "exclamationmark.triangle.fill", animated: motionEnabled)
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.18),
                                Color.accentColor.opacity(0.08),
                                Color.white.opacity(0.04),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            Color.accentColor.opacity(0.16),
                            Color.white.opacity(0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    }

    private var animationsCard: some View {
        PreferencesCard(title: isChinese ? "外观" : "Appearance", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isChinese ? "减少 iData 动画效果" : "Reduce iData animations", isOn: $model.reduceAnimations)
                    .toggleStyle(.switch)

                Text(isChinese ? "降低悬停、弹性和渐显动画；系统“减少动态效果”优先。" : "Reduces hover, spring, and reveal motion while respecting System Reduce Motion.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var runtimeCard: some View {
        PreferencesCard(title: isChinese ? "VisiData 运行环境" : "VisiData Runtime", icon: "terminal", accessory: {
            PreferencesMenuButton(title: isChinese ? "操作" : "Actions", icon: "ellipsis.circle", animated: motionEnabled) {
                Button {
                    model.chooseVDExecutable()
                } label: {
                    Label(isChinese ? "选择可执行文件…" : "Choose Executable…", systemImage: "folder")
                }

                Button {
                    model.vdExecutablePath = ""
                } label: {
                    Label(isChinese ? "自动检测" : "Auto Detect", systemImage: "wand.and.stars")
                }

                if case .missing = model.visiDataDependencyState {
                    Divider()

                    Button {
                        model.runVisiDataOneClickSetup()
                    } label: {
                        Label(isChinese ? "一键安装" : "One-Click Setup", systemImage: "arrow.down.circle")
                    }
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("/opt/homebrew/bin/vd", text: $model.vdExecutablePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Text(model.visiDataDependencySummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var smallFileRoutingCard: some View {
        PreferencesCard(title: isChinese ? "小文件打开方式" : "Small-File Opening", icon: "arrowshape.turn.up.right.circle", accessory: {
            PreferencesMenuButton(title: isChinese ? "操作" : "Actions", icon: "ellipsis.circle", animated: motionEnabled) {
                Button {
                    model.choosePreferredSmallFileApplication()
                } label: {
                    Label(isChinese ? "选择应用…" : "Choose App…", systemImage: "app.badge")
                }

                Button {
                    testSmallFileHandoff()
                } label: {
                    Label(isChinese ? "测试转交" : "Test Handoff", systemImage: "arrowshape.turn.up.right")
                }

                Divider()

                Button {
                    model.clearPreferredSmallFileApplication()
                } label: {
                    Label(isChinese ? "清除自定义应用" : "Clear Custom App", systemImage: "xmark.circle")
                }
                .disabled(model.preferredSmallFileApplication == nil)
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 38, height: 38)
                        .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(isChinese ? "默认目标：\(model.preferredSmallFileApplicationDisplayName)" : "Default target: \(model.preferredSmallFileApplicationDisplayName)")
                            .font(.headline)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(isChinese ? "Finder 交来的小型 CSV / Excel 优先转交；压缩文件仍留在 iData。" : "Small CSV / Excel files from Finder hand off first; compressed files stay in iData.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    PreferencePill(
                        title: isChinese ? "≤ \(AppModel.smallFileRoutingThresholdDisplay)" : "≤ \(AppModel.smallFileRoutingThresholdDisplay)",
                        tint: Color.accentColor.opacity(0.16),
                        icon: "scalemass",
                        animated: motionEnabled
                    )

                    PreferencePill(
                        title: isChinese ? "压缩文件留在 iData" : "Compressed files stay in iData",
                        tint: Color.accentColor.opacity(0.12),
                        icon: "archivebox",
                        animated: motionEnabled
                    )
                }

                HStack(spacing: 8) {
                    ForEach([".csv", ".tsv", ".xlsx", ".xls"], id: \.self) { suffix in
                        Text(suffix)
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                }

                Text(isChinese ? "仅影响 Finder / 系统把文件交给 iData 的外部打开流程；不会改变你在 iData 内点“打开…”时的行为。" : "This only affects files handed to iData by Finder or other system open events. It does not change what happens when you click Open inside iData.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var appLanguageCard: some View {
        PreferencesCard(title: isChinese ? "通用与语言" : "Language", icon: "globe") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isChinese ? "应用语言" : "App language")
                            .font(.headline)

                        Text(isChinese ? "跟随系统，或固定为中文/英文。" : "Follow the system language, or lock the app to Chinese or English.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PreferencesMenuButton(title: model.appLanguageOptionTitle(model.appLanguagePreference), animated: motionEnabled) {
                        ForEach(AppModel.AppLanguagePreference.allCases) { option in
                            Button {
                                model.appLanguagePreference = option
                            } label: {
                                if option == model.appLanguagePreference {
                                    Label(model.appLanguageOptionTitle(option), systemImage: "checkmark")
                                } else {
                                    Text(model.appLanguageOptionTitle(option))
                                }
                            }
                        }
                    }
                    .frame(minWidth: 150, alignment: .trailing)
                }

                Text(model.appLanguageSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var updatesCard: some View {
        PreferencesCard(title: isChinese ? "更新" : "Updates", icon: "square.and.arrow.down", accessory: {
            PreferencesMenuButton(title: isChinese ? "操作" : "Actions", icon: "ellipsis.circle", animated: motionEnabled) {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Label(isChinese ? "立即检查更新" : "Check for Updates Now", systemImage: "arrow.clockwise")
                }

                Button {
                    NSWorkspace.shared.open(updater.releasesURL)
                } label: {
                    Label(isChinese ? "打开发布页" : "Open Releases", systemImage: "safari")
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isChinese ? "自动检查更新" : "Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.setAutomaticallyChecksForUpdates($0) }
                ))
                .toggleStyle(.switch)

                Toggle(isChinese ? "自动下载更新" : "Automatically download updates", isOn: Binding(
                    get: { updater.automaticallyDownloadsUpdates },
                    set: { updater.setAutomaticallyDownloadsUpdates($0) }
                ))
                .toggleStyle(.switch)
                .disabled(!updater.automaticallyChecksForUpdates)

                Text(updater.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func testSmallFileHandoff() {
        do {
            _ = try model.testSmallFileHandoff()
        } catch {
            model.statusMessage = nil
            model.errorMessage = model.localized(
                english: "Could not prepare the handoff test: \(error.localizedDescription)",
                chinese: "无法准备转交测试：\(error.localizedDescription)"
            )
        }
    }
}

private struct PreferencesCard<Content: View, Accessory: View>: View {
    let title: String
    let icon: String
    let tint: Color
    let accessory: Accessory
    let content: Content

    init(
        title: String,
        icon: String,
        tint: Color = .accentColor,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 22, height: 22)

                    Text(title)
                        .font(.headline)
                }

                Spacer(minLength: 12)

                accessory
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.16),
                                Color.white.opacity(0.05),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint.opacity(0.74))
                    .frame(width: 3)
                    .padding(.vertical, 18)
                    .padding(.leading, 1)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            tint.opacity(0.20),
                            Color.white.opacity(0.04),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

private extension PreferencesCard where Accessory == EmptyView {
    init(
        title: String,
        icon: String,
        tint: Color = .accentColor,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, icon: icon, tint: tint, accessory: { EmptyView() }, content: content)
    }
}

private struct PreferencesMenuButton<Content: View>: View {
    let title: String
    let icon: String?
    let animated: Bool
    @ViewBuilder let content: Content

    init(
        title: String,
        icon: String? = nil,
        animated: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.animated = animated
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 16, height: 16)
                }

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
            }
            .padding(.horizontal, 12)
            .frame(width: 150, height: 34, alignment: .leading)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .quietInteractiveSurface(enabled: animated)
    }
}

private struct PreferencePill: View {
    let title: String
    let tint: Color
    let icon: String
    let animated: Bool

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint, in: Capsule())
            .quietInteractiveSurface(enabled: animated, hoverScale: 1.012, hoverYOffset: -0.5, shadowOpacity: 0.08, shadowRadius: 8)
    }
}

private let preferencesBackground = LinearGradient(
    colors: [
        Color.accentColor.opacity(0.16),
        Color(nsColor: .windowBackgroundColor),
        Color.black.opacity(0.05),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
