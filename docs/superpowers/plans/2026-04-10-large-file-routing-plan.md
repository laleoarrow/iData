# Large File Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route externally opened supported files into `iData` only when they are larger than 100 MiB, and silently forward smaller files to a non-`iData` app.

**Architecture:** Add a small external-open routing decision inside `AppModel`, inject a testable file-forwarding dependency, and defer app activation in `AppDelegate` until the route decision says the file should stay in `iData` or surface an error. Keep the existing `VisiData` session-opening path unchanged once `iData` owns the file.

**Tech Stack:** Swift, Swift Testing, AppKit `NSWorkspace`, SwiftUI app delegate bridge

---

### Task 1: Add Failing Routing Tests

**Files:**
- Modify: `Tests/iDataAppTests/AppModelTests.swift`
- Modify: `Sources/iData/AppModel.swift`

- [ ] **Step 1: Write the failing tests for small-file forwarding and large-file ownership**

```swift
    @Test
    func smallSupportedFileForwardsToAlternateApplication() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-forward-small-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let target = tempRoot.appendingPathComponent("small.xlsx")
        try Data("ok".utf8).write(to: target)

        let excel = DefaultApplicationHandler(
            url: URL(fileURLWithPath: "/Applications/Microsoft Excel.app"),
            bundleIdentifier: "com.microsoft.Excel",
            displayName: "Microsoft Excel"
        )
        let opener = RecordingExternalFileOpener()

        let model = AppModel(
            defaults: defaults,
            externalFileOpener: opener,
            alternateApplicationResolver: { _, _ in excel },
            fileSizeProvider: { _ in 10 }
        )

        let action = model.routeExternalFile(target)

        #expect(action == .forwardedToAlternateApp(appName: "Microsoft Excel"))
        #expect(opener.openedFileURL?.standardizedFileURL == target.standardizedFileURL)
        #expect(opener.openedApplicationURL == excel.url)
        #expect(model.activeSession == nil)
    }

    @Test
    func fileLargerThanThresholdStaysInsideIData() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-open-large-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let launcher = tempRoot.appendingPathComponent("fake-vd-long.zsh")
        try makeLongRunningLauncher(at: launcher, sleepSeconds: 120)

        let target = tempRoot.appendingPathComponent("large.xlsx")
        try Data("ok".utf8).write(to: target)

        let opener = RecordingExternalFileOpener()
        let model = AppModel(
            defaults: defaults,
            externalFileOpener: opener,
            alternateApplicationResolver: { _, _ in nil },
            fileSizeProvider: { _ in AppModel.largeFileOpenThresholdBytes + 1 }
        )
        model.vdExecutablePath = launcher.path
        defer { model.activeSession?.terminate() }

        let action = model.routeExternalFile(target)

        #expect(action == .openedInIData)
        #expect(opener.openedFileURL == nil)
        #expect(model.activeSession?.currentFileURL?.standardizedFileURL == target.standardizedFileURL)
    }
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `swift test --filter 'AppModelTests/(smallSupportedFileForwardsToAlternateApplication|fileLargerThanThresholdStaysInsideIData)'`
Expected: FAIL because `routeExternalFile`, `RecordingExternalFileOpener`, and injected routing dependencies do not exist yet.

- [ ] **Step 3: Add failure-path tests**

```swift
    @Test
    func smallSupportedFileShowsErrorWhenNoAlternateApplicationExists() throws {
        let target = URL(fileURLWithPath: "/tmp/no-alt.csv")
        let model = AppModel(
            externalFileOpener: RecordingExternalFileOpener(),
            alternateApplicationResolver: { _, _ in nil },
            fileSizeProvider: { _ in 10 }
        )

        let action = model.routeExternalFile(target)

        #expect(action == .presentedError)
        #expect(model.errorMessage?.contains("non-iData app") == true || model.errorMessage?.contains("非 iData 应用") == true)
    }

    @Test
    func thresholdBoundaryForwardsExactlyFiveHundredMiB() throws {
        let target = URL(fileURLWithPath: "/tmp/boundary.tsv")
        let numbers = DefaultApplicationHandler(
            url: URL(fileURLWithPath: "/Applications/Numbers.app"),
            bundleIdentifier: "com.apple.Numbers",
            displayName: "Numbers"
        )
        let opener = RecordingExternalFileOpener()
        let model = AppModel(
            externalFileOpener: opener,
            alternateApplicationResolver: { _, _ in numbers },
            fileSizeProvider: { _ in AppModel.largeFileOpenThresholdBytes }
        )

        let action = model.routeExternalFile(target)

        #expect(action == .forwardedToAlternateApp(appName: "Numbers"))
        #expect(opener.openedApplicationURL == numbers.url)
    }
```

- [ ] **Step 4: Run the targeted tests to verify they fail for the new behavior**

Run: `swift test --filter 'AppModelTests/(smallSupportedFileShowsErrorWhenNoAlternateApplicationExists|thresholdBoundaryForwardsExactlyFiveHundredMiB)'`
Expected: FAIL because routing behavior and threshold constant do not exist yet.

- [ ] **Step 5: Commit the red tests checkpoint**

```bash
git add Tests/iDataAppTests/AppModelTests.swift
git commit -m "test: cover external file size routing"
```

### Task 2: Implement Routing Decision in AppModel

**Files:**
- Modify: `Sources/iData/AppModel.swift`
- Test: `Tests/iDataAppTests/AppModelTests.swift`

- [ ] **Step 1: Add the minimal routing types and injected dependencies**

```swift
    static let largeFileOpenThresholdBytes = 100 * 1024 * 1024

    private let externalFileOpener: any ExternalFileOpening
    private let alternateApplicationResolver: @MainActor (URL, String) -> DefaultApplicationHandler?
    private let fileSizeProvider: (URL) -> Int64?
```

```swift
protocol ExternalFileOpening: Sendable {
    func open(_ fileURL: URL, withApplicationAt applicationURL: URL) -> Bool
}

struct WorkspaceExternalFileOpener: ExternalFileOpening {
    func open(_ fileURL: URL, withApplicationAt applicationURL: URL) -> Bool {
        NSWorkspace.shared.open([fileURL], withApplicationAt: applicationURL, configuration: NSWorkspace.OpenConfiguration())
    }
}

enum ExternalOpenAction: Equatable {
    case openedInIData
    case forwardedToAlternateApp(appName: String)
    case presentedError
}
```

- [ ] **Step 2: Extend `AppModel.init` with defaulted injected collaborators**

```swift
    init(
        defaults: UserDefaults = .standard,
        recentFilesStore: RecentFilesStore? = nil,
        executableChecker: any ExecutableChecking = LocalExecutableChecker(),
        environmentPathProvider: @escaping () -> String = { ProcessInfo.processInfo.environment["PATH"] ?? "" },
        preferredLanguagesProvider: @escaping () -> [String] = { Locale.preferredLanguages },
        externalFileOpener: any ExternalFileOpening = WorkspaceExternalFileOpener(),
        alternateApplicationResolver: @escaping @MainActor (URL, String) -> DefaultApplicationHandler? = AppModel.resolveAlternateApplication(for:lookupExtension:),
        fileSizeProvider: @escaping (URL) -> Int64? = AppModel.fileSizeInBytes(for:)
    )
```

- [ ] **Step 3: Implement the route decision before session launch**

```swift
    func routeExternalFile(_ url: URL) -> ExternalOpenAction {
        guard Self.supportsTableFile(url) else {
            statusMessage = nil
            errorMessage = localized(
                english: "The selected item is not a regular file. iData opens most file suffixes directly and streams .gz/.bgz files without extracting.",
                chinese: "所选内容不是普通文件。iData 会直接打开大多数文件后缀，并对 .gz/.bgz 文件进行流式读取而不解压。"
            )
            return .presentedError
        }

        let lookupExtension = Self.associationExtension(for: url.pathExtension)
        if let fileSize = fileSizeProvider(url), fileSize <= Self.largeFileOpenThresholdBytes {
            if let app = alternateApplicationResolver(url, lookupExtension) {
                if externalFileOpener.open(url, withApplicationAt: app.url) {
                    statusMessage = nil
                    errorMessage = nil
                    return .forwardedToAlternateApp(appName: app.displayName)
                }
                errorMessage = localized(
                    english: "Could not open \(url.lastPathComponent) with \(app.displayName).",
                    chinese: "无法用 \(app.displayName) 打开 \(url.lastPathComponent)。"
                )
                statusMessage = nil
                return .presentedError
            }
            errorMessage = localized(
                english: "Could not find a non-iData app to open \(url.lastPathComponent).",
                chinese: "找不到可用于打开 \(url.lastPathComponent) 的非 iData 应用。"
            )
            statusMessage = nil
            return .presentedError
        }

        openExternalFile(url)
        return activeSession?.currentFileURL?.standardizedFileURL == url.standardizedFileURL ? .openedInIData : .presentedError
    }
```

- [ ] **Step 4: Add the minimal file-size and alternate-app helpers**

```swift
    static func fileSizeInBytes(for url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey])
        if let size = values?.totalFileAllocatedSize { return Int64(size) }
        if let size = values?.fileAllocatedSize { return Int64(size) }
        if let size = values?.fileSize { return Int64(size) }
        return nil
    }

    @MainActor
    static func resolveAlternateApplication(for url: URL, lookupExtension: String) -> DefaultApplicationHandler? {
        let fallbackCandidates = FileTypeAssociation.alternativeApplicationCandidates(forExtension: lookupExtension)
        return preferredRestoreApplication(
            storedPreviousDefault: FileTypeAssociation.currentDefaultApp(forExtension: lookupExtension).flatMap { current in
                FileTypeAssociation.isIDataBundleIdentifier(current.bundleIdentifier) ? nil : current
            },
            fallbackCandidates: fallbackCandidates
        )
    }
```

- [ ] **Step 5: Run the same targeted tests to verify they pass**

Run: `swift test --filter 'AppModelTests/(smallSupportedFileForwardsToAlternateApplication|fileLargerThanThresholdStaysInsideIData|smallSupportedFileShowsErrorWhenNoAlternateApplicationExists|thresholdBoundaryForwardsExactlyFiveHundredMiB)'`
Expected: PASS

- [ ] **Step 6: Commit the green routing logic**

```bash
git add Sources/iData/AppModel.swift Tests/iDataAppTests/AppModelTests.swift
git commit -m "feat: route small external files to alternate apps"
```

### Task 3: Defer App Activation Until Routing Decides

**Files:**
- Modify: `Sources/iData/iDataApp.swift`
- Modify: `Sources/iData/AppModel.swift`
- Test: `Tests/iDataAppTests/AppModelTests.swift`

- [ ] **Step 1: Add a small route-result bridge from `AppModel` to `AppDelegate`**

```swift
enum ExternalOpenPresentationDecision: Equatable {
    case activateApp
    case stayBackground
}
```

```swift
    func handleExternalFileOpen(_ urls: [URL]) -> ExternalOpenPresentationDecision {
        guard let url = Self.firstSupportedFile(in: urls) else {
            _ = routeExternalFile(urls.first ?? URL(fileURLWithPath: "/"))
            return .activateApp
        }

        switch routeExternalFile(url) {
        case .openedInIData, .presentedError:
            return .activateApp
        case .forwardedToAlternateApp:
            return .stayBackground
        }
    }
```

- [ ] **Step 2: Update `AppDelegate.routeOpen` to activate only when needed**

```swift
    private func routeOpen(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }

        let dispatch: ([URL]) -> Void = { [weak self] incoming in
            guard let self else { return }
            let shouldActivate = openHandler?(incoming) ?? .activateApp
            if shouldActivate == .activateApp {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
            }
        }

        if openHandler != nil {
            dispatch(fileURLs)
        } else {
            pendingOpenURLs.append(contentsOf: fileURLs)
        }
    }
```

- [ ] **Step 3: Run focused tests plus a full app test pass**

Run: `swift test --filter AppModelTests`
Expected: PASS

- [ ] **Step 4: Commit the activation-routing change**

```bash
git add Sources/iData/iDataApp.swift Sources/iData/AppModel.swift Tests/iDataAppTests/AppModelTests.swift
git commit -m "feat: defer app activation for forwarded files"
```

### Task 4: Verify End-to-End

**Files:**
- Modify: `Sources/iData/AppModel.swift` (only if verification exposes defects)
- Modify: `Sources/iData/iDataApp.swift` (only if verification exposes defects)
- Test: `Tests/iDataAppTests/AppModelTests.swift`

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: PASS

- [ ] **Step 2: Run the Debug macOS build**

Run: `/bin/zsh -lc 'xcodebuild -project iData.xcodeproj -scheme iDataApp -configuration Debug -derivedDataPath .build/xcode-debug build'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Record the manual verification commands**

Run:

```bash
open -a /Users/leoarrow/Project/mypackage/agents/iData/dist/iData.app /tmp/small.xlsx
open -a /Users/leoarrow/Project/mypackage/agents/iData/dist/iData.app /tmp/large.xlsx
```

Expected:
- `small.xlsx` opens in Excel/WPS/TextEdit instead of creating an `iData` session
- `large.xlsx` opens in `iData`

- [ ] **Step 4: Commit the verified final state**

```bash
git add Sources/iData/iDataApp.swift Sources/iData/AppModel.swift Tests/iDataAppTests/AppModelTests.swift
git commit -m "feat: gate external file opening by size"
```
