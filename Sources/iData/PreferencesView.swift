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
                animationsCard
                appLanguageCard
                smallFileRoutingCard
                runtimeCard
                updatesCard
            }
            .padding(24)
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
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.accentColor.opacity(0.26), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "偏好设置" : "Preferences")
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text(isChinese ? "配置 `iData` 查找 `VisiData` 的位置，控制更新行为，并在打开大文件前确认当前运行状态。" : "Configure where `iData` finds `VisiData`, control update behavior, and verify the current runtime state before opening large files.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        VersionPill(model: model, tint: .white.opacity(0.12), icon: "shippingbox")

                        switch model.visiDataDependencyState {
                        case .available:
                            PreferencePill(title: isChinese ? "VisiData 已就绪" : "VisiData Ready", tint: .green.opacity(0.20), icon: "checkmark.circle.fill", animated: motionEnabled)
                        case .missing:
                            PreferencePill(title: isChinese ? "缺少 VisiData" : "VisiData Missing", tint: .orange.opacity(0.22), icon: "exclamationmark.triangle.fill", animated: motionEnabled)
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10))
        )
        .shadow(color: .black.opacity(0.12), radius: 22, y: 10)
    }

    private var animationsCard: some View {
        PreferencesCard(title: isChinese ? "外观" : "Appearance", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isChinese ? "减少 iData 动画效果" : "Reduce iData animations", isOn: $model.reduceAnimations)
                    .toggleStyle(.switch)

                Text(isChinese ? "降低应用内的大部分弹性、悬停和渐显动画强度。系统的“减少动态效果”设置仍然会被优先遵循。" : "Turns down most spring, hover, and reveal animations across the app. System Reduce Motion is still respected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var runtimeCard: some View {
        PreferencesCard(title: isChinese ? "VisiData 运行环境" : "VisiData Runtime", icon: "terminal") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("/opt/homebrew/bin/vd", text: $model.vdExecutablePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                HStack(spacing: 10) {
                    Button(isChinese ? "选择可执行文件…" : "Choose Executable…") {
                        model.chooseVDExecutable()
                    }
                    .buttonStyle(.borderedProminent)
                    .quietInteractiveSurface(enabled: motionEnabled)

                    Button(isChinese ? "自动检测" : "Auto Detect") {
                        model.vdExecutablePath = ""
                    }
                    .buttonStyle(.bordered)
                    .quietInteractiveSurface(enabled: motionEnabled)

                    if case .missing = model.visiDataDependencyState {
                        Button(isChinese ? "一键安装" : "One-Click Setup") {
                            model.runVisiDataOneClickSetup()
                        }
                        .buttonStyle(.bordered)
                        .quietInteractiveSurface(enabled: motionEnabled)
                    }

                    Spacer(minLength: 0)
                }

                Text(model.visiDataDependencySummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var smallFileRoutingCard: some View {
        PreferencesCard(title: isChinese ? "小文件转交" : "Small-File Handoff", icon: "arrowshape.turn.up.right.circle") {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.smallFileRoutingSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(isChinese ? "当前外部应用" : "Current external app")
                        .font(.subheadline.weight(.semibold))
                    Text(model.preferredSmallFileApplicationDisplayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 10) {
                    Button(isChinese ? "选择应用…" : "Choose App…") {
                        model.choosePreferredSmallFileApplication()
                    }
                    .buttonStyle(.borderedProminent)
                    .quietInteractiveSurface(enabled: motionEnabled)

                    Button(isChinese ? "清除" : "Clear") {
                        model.clearPreferredSmallFileApplication()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.preferredSmallFileApplication == nil)
                    .quietInteractiveSurface(enabled: motionEnabled)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var appLanguageCard: some View {
        PreferencesCard(title: isChinese ? "通用与语言" : "Language", icon: "globe") {
            VStack(alignment: .leading, spacing: 14) {
                Picker(isChinese ? "应用语言" : "App language", selection: $model.appLanguagePreference) {
                    ForEach(AppModel.AppLanguagePreference.allCases) { option in
                        Text(model.appLanguageOptionTitle(option))
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text(isChinese ? "“系统”会跟随 macOS 首选语言。整个原生界面和交互式教程都会同步切换。" : "`System` follows macOS preferred language. Applies across the native app shell and interactive tutorials.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(model.appLanguageSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var updatesCard: some View {
        PreferencesCard(title: isChinese ? "更新" : "Updates", icon: "square.and.arrow.down") {
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

                HStack(spacing: 10) {
                    Button(isChinese ? "立即检查更新" : "Check for Updates Now") {
                        updater.checkForUpdates()
                    }
                    .buttonStyle(.borderedProminent)
                    .quietInteractiveSurface(enabled: motionEnabled)

                    Button(isChinese ? "打开发布页" : "Open Releases") {
                        NSWorkspace.shared.open(updater.releasesURL)
                    }
                    .buttonStyle(.bordered)
                    .quietInteractiveSurface(enabled: motionEnabled)
                }

                Text(updater.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PreferencesCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.headline)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
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
