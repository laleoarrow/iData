import AppKit
import Carbon.HIToolbox
import SwiftUI

struct GlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.4), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 16, x: 0, y: 8)
    }
}

extension View {
    func glassCard() -> some View {
        self.modifier(GlassCardModifier())
    }
}

struct IDataAnimationsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var idataAnimationsEnabled: Bool {
        get { self[IDataAnimationsEnabledKey.self] }
        set { self[IDataAnimationsEnabledKey.self] = newValue }
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
    let glowStyle: SidebarHoverGlowStyle

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background {
                SidebarHoverGlow(
                    isVisible: enabled && isHovering,
                    style: glowStyle
                )
            }
            .scaleEffect(enabled && isHovering ? hoverScale : 1)
            .offset(y: enabled && isHovering ? hoverYOffset : 0)
            .shadow(
                color: .black.opacity(enabled && isHovering ? shadowOpacity : 0),
                radius: enabled && isHovering ? shadowRadius : 0,
                y: enabled && isHovering ? max(2, shadowRadius * 0.35) : 0
            )
            .animation(enabled ? .easeOut(duration: 0.24) : nil, value: isHovering)
            .onHover { hovering in
                isHovering = enabled && hovering
            }
    }
}

extension View {
    func quietInteractiveSurface(
        enabled: Bool,
        hoverScale: CGFloat = 1.01,
        hoverYOffset: CGFloat = -1.5,
        shadowOpacity: Double = 0.14,
        shadowRadius: CGFloat = 16,
        glowStyle: SidebarHoverGlowStyle = .none
    ) -> some View {
        modifier(
            QuietInteractiveSurfaceModifier(
                enabled: enabled,
                hoverScale: hoverScale,
                hoverYOffset: hoverYOffset,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                glowStyle: glowStyle
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

struct StatusPill: View {
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

struct FormatChip: View {
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

struct QuickTip: Identifiable {
    let id = UUID()
    let keys: String
    let title: String
    let detail: String
}

struct MessageCard: View {
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
        .glassCard()
        .background(color.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .quietInteractiveSurface(
            enabled: idataAnimationsEnabled && !accessibilityReduceMotion,
            hoverScale: 1.006,
            hoverYOffset: -0.5,
            shadowOpacity: 0.05,
            shadowRadius: 8
        )
    }
}
