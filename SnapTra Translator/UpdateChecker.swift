import AppKit
import Foundation
import Sparkle

enum DistributionChannel {
    case github
    case appStore

    static var current: DistributionChannel {
        // Only GitHub Release builds have DISTRIBUTION_CHANNEL set
        if let channel = Bundle.main.infoDictionary?["DISTRIBUTION_CHANNEL"] as? String,
           channel == "github" {
            return .github
        }
        return .appStore
    }

    static var isGitHubRelease: Bool {
        current == .github
    }
}

@MainActor
final class UpdateChecker: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateChecker()

    private var updaterController: SPUStandardUpdaterController?
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private var autoCheckTimer: Timer?

    var isGitHubRelease: Bool {
        #if DEBUG
        // Debug mode: allow forcing GitHub release mode for testing
        // 直接从 UserDefaults 读取，确保能获取最新值
        let debugEnabled = UserDefaults.standard.bool(forKey: AppSettingKey.debugShowChannelSelector)
        if debugEnabled {
            return true
        }
        #endif
        return DistributionChannel.isGitHubRelease
    }

    private override init() {
        super.init()
    }

    func initialize() {
        guard updaterController == nil else { return }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        if let updater = updaterController?.updater {
            updater.automaticallyChecksForUpdates = SettingsStore.shared.autoCheckUpdates && isGitHubRelease
            updater.updateCheckInterval = checkInterval
        }
    }

    func updateFeedURL() {
        guard let updater = updaterController?.updater else { return }
        
        // 清除 Sparkle 的 feed URL 缓存
        updater.clearFeedURLFromUserDefaults()
        
        // 清除 Sparkle 的 appcast 缓存，强制重新下载
        let defaults = UserDefaults.standard
        let sparkleKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("SU") }
        for key in sparkleKeys {
            defaults.removeObject(forKey: key)
        }
        
        // 重置 feed URL，强制 Sparkle 重新调用 feedURLString(for:)
        updater.setFeedURL(nil)
        
        // 重置更新周期
        updater.resetUpdateCycle()
        
        print("[UpdateChecker] Feed URL updated, Sparkle cache cleared for channel: \(SettingsStore.shared.updateChannel)")
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
        if isGitHubRelease {
            if let controller = updaterController {
                if silent {
                    controller.updater.checkForUpdatesInBackground()
                } else {
                    controller.checkForUpdates(nil)
                }
            } else if !silent {
                showSparkleNotInitializedAlert()
            }
        } else {
            guard !silent else { return }
            openAppStore()
        }
    }

    func checkForUpdatesWithUI() {
        if isGitHubRelease {
            if let controller = updaterController {
                controller.checkForUpdates(nil)
            } else {
                showSparkleNotInitializedAlert()
            }
        } else {
            openAppStore()
        }
    }

    // MARK: - App Store

    private func openAppStore() {
        if let url = URL(string: "https://apps.apple.com/cn/app/snaptra-translator/id6757981764") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? {
        // 直接从 UserDefaults 读取，确保获取最新值
        let channelValue = UserDefaults.standard.string(forKey: AppSettingKey.updateChannel) ?? "stable"
        let channel = UpdateChannel(rawValue: channelValue) ?? .stable
        
        let url: String
        switch channel {
        case .stable:
            url = "https://snaptra.yelog.org/appcast.xml"
        case .beta:
            url = "https://snaptra.yelog.org/appcast-beta.xml"
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

    // MARK: - GitHub Releases

    private func openGitHubReleases() {
        let channelValue = UserDefaults.standard.string(forKey: AppSettingKey.updateChannel) ?? "stable"
        let channel = UpdateChannel(rawValue: channelValue) ?? .stable

        let urlString: String
        switch channel {
        case .stable:
            urlString = "https://github.com/yelog/SnapTraTranslator/releases/latest"
        case .beta:
            urlString = "https://github.com/yelog/SnapTraTranslator/releases"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Alerts

    private func showSparkleNotInitializedAlert() {
        let alert = NSAlert()
        alert.messageText = L("Update Check Failed")
        alert.informativeText = L("Auto-updater is not available. Please visit GitHub to download the latest version.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("Go to GitHub"))
        alert.addButton(withTitle: L("OK"))

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openGitHubReleases()
        }
    }

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
            openGitHubReleases()
        }
    }
}
