import AppKit
import Combine
import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class AppUpdaterController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isConfigured = false
    @Published var automaticallyChecksForUpdates = true
    @Published var automaticallyDownloadsUpdates = true
    @Published private(set) var statusMessage = "Automatic updates are not configured yet."

    let releasesURL = URL(string: "https://github.com/laleoarrow/iData/releases")!
    let appcastURL = URL(string: "https://laleoarrow.github.io/iData/appcast.xml")!

    #if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController?
    private var cancellables: Set<AnyCancellable> = []
    #endif
    private var didPerformStartupCheck = false
    private let urlSession = URLSession(configuration: .ephemeral)

    init() {
        #if canImport(Sparkle)
        if Self.hasSparkleConfiguration {
            let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            self.updaterController = controller
            self.isConfigured = true
            self.statusMessage = "Automatic updates are enabled through Sparkle."

            controller.updater.publisher(for: \.canCheckForUpdates)
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.canCheckForUpdates = $0 }
                .store(in: &cancellables)

            controller.updater.publisher(for: \.automaticallyChecksForUpdates)
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
                .store(in: &cancellables)

            controller.updater.publisher(for: \.automaticallyDownloadsUpdates)
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.automaticallyDownloadsUpdates = $0 }
                .store(in: &cancellables)

            self.canCheckForUpdates = controller.updater.canCheckForUpdates
            self.automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
            self.automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
        } else {
            self.updaterController = nil
            self.isConfigured = false
            self.statusMessage = "Automatic updates will activate after Sparkle feed URL and signing keys are configured."
        }
        #else
        self.isConfigured = false
        self.statusMessage = "This build does not include Sparkle yet. You can still download updates from GitHub Releases."
        #endif
    }

    func performStartupUpdateCheckIfNeeded() {
        guard !didPerformStartupCheck else { return }
        didPerformStartupCheck = true

        Task {
            await performStartupUpdateCheck()
        }
    }

    func checkForUpdates() {
        Task {
            await performInteractiveUpdateCheck()
        }
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        #if canImport(Sparkle)
        updaterController?.updater.automaticallyChecksForUpdates = enabled
        #endif

        automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        #if canImport(Sparkle)
        updaterController?.updater.automaticallyDownloadsUpdates = enabled
        #endif

        automaticallyDownloadsUpdates = enabled
    }

    private static var hasSparkleConfiguration: Bool {
        let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        return !(feedURL?.isEmpty ?? true) && !(publicKey?.isEmpty ?? true)
    }

    private func performStartupUpdateCheck() async {
        #if canImport(Sparkle)
        guard
            let updaterController,
            updaterController.updater.automaticallyChecksForUpdates
        else {
            return
        }

        guard await isUpdateFeedReachable() else {
            statusMessage = "Update feed is not published yet. GitHub Releases remains available for manual installs."
            return
        }

        updaterController.updater.checkForUpdatesInBackground()
        #endif
    }

    private func performInteractiveUpdateCheck() async {
        #if canImport(Sparkle)
        if let updaterController {
            guard await isUpdateFeedReachable() else {
                statusMessage = "Update feed is not live yet. Opening GitHub Releases instead."
                NSWorkspace.shared.open(releasesURL)
                return
            }

            updaterController.checkForUpdates(nil)
            return
        }
        #endif

        statusMessage = "Sparkle is unavailable in this build. Opening GitHub Releases."
        NSWorkspace.shared.open(releasesURL)
    }

    private func isUpdateFeedReachable() async -> Bool {
        var request = URLRequest(url: appcastURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8

        do {
            let (_, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }
}
