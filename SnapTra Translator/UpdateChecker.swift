import AppKit
import Foundation
import Sparkle

enum DistributionChannel {
    case github
    case appStore

    static var isGitHubRelease: Bool {
        if let channel = Bundle.main.infoDictionary?["DISTRIBUTION_CHANNEL"] as? String,
           channel == "github" {
            return true
        }
        return false
    }
}

@MainActor
final class UpdateChecker: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateChecker()

    private var updaterController: SPUStandardUpdaterController?
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private var autoCheckTimer: Timer?

    var isGitHubRelease: Bool {
        DistributionChannel.isGitHubRelease
    }

    private override init() {
        super.init()
    }

    func initialize() {
        guard isGitHubRelease else { return }
        guard updaterController == nil else { return }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        if let updater = updaterController?.updater {
            updater.automaticallyChecksForUpdates = SettingsStore.shared.autoCheckUpdates
            updater.updateCheckInterval = checkInterval
        }
    }

    func updateFeedURL() {
        updaterController?.updater.clearFeedURLFromUserDefaults()
    }

    func startAutoCheckIfNeeded() {
        guard isGitHubRelease else { return }
        guard SettingsStore.shared.autoCheckUpdates else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.checkForUpdates(silent: true)
        }

        autoCheckTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard SettingsStore.shared.autoCheckUpdates else { return }
                self?.checkForUpdates(silent: true)
            }
        }
    }

    func checkForUpdates(silent: Bool = false) {
        guard isGitHubRelease else {
            guard !silent else { return }
            openAppStore()
            return
        }

        guard let controller = updaterController else {
            if !silent {
                openAppStore()
            }
            return
        }

        if silent {
            controller.updater.checkForUpdatesInBackground()
        } else {
            controller.checkForUpdates(nil)
        }
    }

    func checkForUpdatesWithUI() {
        guard isGitHubRelease else {
            openAppStore()
            return
        }

        updaterController?.checkForUpdates(nil)
    }

    // MARK: - App Store

    private func openAppStore() {
        if let url = URL(string: "https://apps.apple.com/cn/app/snaptra-translator/id6757981764") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? {
        let channel = SettingsStore.shared.updateChannel
        let url: String
        switch channel {
        case .stable:
            url = "https://yelog.github.io/SnapTraTranslator/appcast.xml"
        case .beta:
            url = "https://yelog.github.io/SnapTraTranslator/appcast-beta.xml"
        }
        print("[UpdateChecker] Using feed URL for channel '\(channel)': \(url)")
        return url
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        print("[UpdateChecker] Update found: \(item.displayVersionString)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        print("[UpdateChecker] No update found")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        print("[UpdateChecker] Update aborted with error: \(error.localizedDescription)")

        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain {
            switch nsError.code {
            case 1001:
                print("[UpdateChecker] Already up to date")
                return
            case 4007:
                print("[UpdateChecker] Update was canceled by user")
                return
            default:
                break
            }
        }

        DispatchQueue.main.async {
            self.showUpdateFailedAlert(error: error)
        }
    }

    // MARK: - Alerts

    private func showUpdateFailedAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = L("Update Check Failed")
        alert.informativeText = "\(L("Auto-update failed. You can download the latest version from GitHub."))\n\n\(L("Error")): \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Download from GitHub"))
        alert.addButton(withTitle: L("OK"))

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "https://github.com/yelog/SnapTraTranslator/releases/latest") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}