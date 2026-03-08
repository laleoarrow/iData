import SwiftUI

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdaterController
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var motionEnabled: Bool {
        model.animationsEnabled && !accessibilityReduceMotion
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                preferencesHero
                animationsCard
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
                    Text("Preferences")
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text("Configure where `iData` finds `VisiData`, control update behavior, and verify the current runtime state before opening large files.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        VersionRevealPill(model: model, tint: .white.opacity(0.12), icon: "shippingbox")

                        switch model.visiDataDependencyState {
                        case .available:
                            PreferencePill(title: "VisiData Ready", tint: .green.opacity(0.20), icon: "checkmark.circle.fill", animated: motionEnabled)
                        case .missing:
                            PreferencePill(title: "VisiData Missing", tint: .orange.opacity(0.22), icon: "exclamationmark.triangle.fill", animated: motionEnabled)
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
        PreferencesCard(title: "Appearance", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Reduce iData animations", isOn: $model.reduceAnimations)
                    .toggleStyle(.switch)

                Text("Turns down most spring, hover, and reveal animations across the app. System Reduce Motion is still respected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var runtimeCard: some View {
        PreferencesCard(title: "VisiData Runtime", icon: "terminal") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("/opt/homebrew/bin/vd", text: $model.vdExecutablePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                HStack(spacing: 10) {
                    Button("Choose Executable…") {
                        model.chooseVDExecutable()
                    }
                    .buttonStyle(.borderedProminent)
                    .quietInteractiveSurface(enabled: motionEnabled)

                    Button("Auto Detect") {
                        model.vdExecutablePath = ""
                    }
                    .buttonStyle(.bordered)
                    .quietInteractiveSurface(enabled: motionEnabled)

                    Spacer(minLength: 0)
                }

                Text(model.visiDataDependencySummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var updatesCard: some View {
        PreferencesCard(title: "Updates", icon: "square.and.arrow.down") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.setAutomaticallyChecksForUpdates($0) }
                ))
                .toggleStyle(.switch)

                Toggle("Automatically download updates", isOn: Binding(
                    get: { updater.automaticallyDownloadsUpdates },
                    set: { updater.setAutomaticallyDownloadsUpdates($0) }
                ))
                .toggleStyle(.switch)
                .disabled(!updater.automaticallyChecksForUpdates)

                HStack(spacing: 10) {
                    Button("Check for Updates Now") {
                        updater.checkForUpdates()
                    }
                    .buttonStyle(.borderedProminent)
                    .quietInteractiveSurface(enabled: motionEnabled)

                    Button("Open Releases") {
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
