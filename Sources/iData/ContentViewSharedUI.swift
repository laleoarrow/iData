import AppKit
import Carbon.HIToolbox
import SwiftUI

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
            apply(
                displayName: localizedText(appShellLanguage() == .chinese, english: "Unknown", chinese: "未知"),
                isLikelyEnglish: false
            )
            return
        }

        let localizedName = Self.readInputSourceString(source: source, key: kTISPropertyLocalizedName) ?? localizedText(appShellLanguage() == .chinese, english: "Unknown", chinese: "未知")
        let sourceID = Self.readInputSourceString(source: source, key: kTISPropertyInputSourceID) ?? ""
        let inputModeID = Self.readInputSourceString(source: source, key: kTISPropertyInputModeID) ?? ""

        apply(
            displayName: localizedName,
            isLikelyEnglish: Self.looksEnglish(
                sourceID: sourceID,
                inputModeID: inputModeID,
                localizedName: localizedName
            )
        )
    }

    private func apply(displayName: String, isLikelyEnglish: Bool) {
        if self.displayName != displayName {
            self.displayName = displayName
        }
        if self.isLikelyEnglish != isLikelyEnglish {
            self.isLikelyEnglish = isLikelyEnglish
        }
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
    let glowStyle: SidebarHoverGlowStyle

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if enabled && isHovering {
                    SidebarHoverGlow(
                        isVisible: true,
                        style: glowStyle
                    )
                    .transition(.opacity)
                }
            }
            .animation(enabled ? .easeOut(duration: 0.16) : nil, value: isHovering)
            .onHover { hovering in
                let nextHoverState = enabled && hovering
                guard nextHoverState != isHovering else {
                    return
                }
                isHovering = nextHoverState
            }
            .onChange(of: enabled) { _, isEnabled in
                if !isEnabled {
                    isHovering = false
                }
            }
    }
}

extension View {
    func quietInteractiveSurface(
        enabled: Bool,
        glowStyle: SidebarHoverGlowStyle = .rounded(8)
    ) -> some View {
        modifier(
            QuietInteractiveSurfaceModifier(
                enabled: enabled,
                glowStyle: glowStyle
            )
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
    private var statusRow: some View {
        HStack(spacing: 4) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text(localizedText(isChinese, english: "Setting...", chinese: "设置中…"))
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
        Button {
            if !isLoading {
                onTap()
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(".\(extensionText)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                statusRow
            }
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isDefault ? Color.green.opacity(0.10) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isDefault ? Color.green.opacity(0.35) : Color.primary.opacity(0.08))
        )
        .disabled(isLoading)
        .accessibilityLabel("\(title), .\(extensionText)")
        .accessibilityValue(isDefault ? localizedText(isChinese, english: "Default app: iData", chinese: "默认使用 iData") : "")
    }
}

struct QuickTip: Identifiable {
    let keys: String
    let title: String
    let detail: String

    var id: String { keys }
}

struct MessageCard: View {
    let title: String
    let message: String
    let color: Color
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.20), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
