//
//  Snap_TranslateApp.swift
//  Snap Translate
//
//  Created by 杨玉杰 on 2026/1/12.
//

import AppKit
import Combine
import SwiftUI
import Translation

@main
struct Snap_TranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NSApp.sendAction(#selector(AppDelegate.openSettingsWindow), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private lazy var model = AppModel()
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var visibilityTask: Task<Void, Never>?
    private var isManualWindowOpen = false
    private var shouldShowWindowAfterPermissionGrant = false

    private var settingsWindow: NSWindow? {
        settingsWindowController?.window
    }

    // Store menu items that need state updates
    private weak var pronunciationMenuItem: NSMenuItem?
    private weak var continuousTranslationMenuItem: NSMenuItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        configureStatusItem()
        checkPermissionGrantRestart()

        if #available(macOS 15.0, *) {
            createTranslationServiceWindow(model: model)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else { return }
                warmupServices(model: self.model)
            }
        }

        model.permissions.$status
            .sink { [weak self] _ in
                self?.scheduleVisibilityUpdate()
            }
            .store(in: &cancellables)

        model.settings.$continuousTranslation
            .sink { [weak self] _ in
                self?.scheduleVisibilityUpdate()
            }
            .store(in: &cancellables)

        model.settings.$playPronunciation
            .combineLatest(model.settings.$ttsProvider)
            .sink { [weak self] _, _ in
                self?.updateDynamicMenuItems()
            }
            .store(in: &cancellables)

        model.settings.$sourceLanguage
            .combineLatest(model.settings.$targetLanguage)
            .sink { [weak self] _, _ in
                self?.scheduleVisibilityUpdate()
            }
            .store(in: &cancellables)

        // Listen for language changes to update menu
        NotificationCenter.default.publisher(for: .languageChanged)
            .sink { [weak self] _ in
                self?.updateMenuLanguage()
            }
            .store(in: &cancellables)

        // Initialize localization manager with saved language
        LocalizationManager.shared.setLanguage(model.settings.appLanguage)

        Task {
            await refreshAndUpdateVisibility()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        isManualWindowOpen = true
        NSApp.setActivationPolicy(.regular)
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            showSettingsWindow()
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        hideDockIcon()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == settingsWindow else { return }
        isManualWindowOpen = true
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            button.image = makeStatusBarImage()
            button.imagePosition = .imageOnly
            button.toolTip = "SnapTra Translator"
            // Note: When using statusItem.menu, we don't need to set target/action
            // The menu will be shown automatically when the button is clicked
        }

        // Create and assign the menu
        let menu = createStatusBarMenu()
        item.menu = menu

        statusItem = item
    }

    private func createStatusBarMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        // Title item (disabled, gray)
        let titleItem = NSMenuItem(
            title: "SnapTra Translator",
            action: nil,
            keyEquivalent: ""
        )
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        // Quick actions - store references for dynamic updates
        // Pronunciation toggle
        let pronunciationItem = NSMenuItem(
            title: "",
            action: #selector(togglePronunciation),
            keyEquivalent: ""
        )
        pronunciationItem.target = self
        menu.addItem(pronunciationItem)
        self.pronunciationMenuItem = pronunciationItem

        // Continuous translation toggle
        let continuousItem = NSMenuItem(
            title: "",
            action: #selector(toggleContinuousTranslation),
            keyEquivalent: ""
        )
        continuousItem.target = self
        menu.addItem(continuousItem)
        self.continuousTranslationMenuItem = continuousItem

        // Hotkey display (disabled, just shows current hotkey)
        let hotkeyItem = NSMenuItem(
            title: String(format: L("Shortcut: %@"), model.settings.hotkeyDisplayText),
            action: nil,
            keyEquivalent: ""
        )
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)

        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: L("Settings..."),
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // About
        let aboutItem = NSMenuItem(
            title: L("About SnapTra"),
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.indentationLevel = 0
        menu.addItem(aboutItem)

        // Quit
        let quitItem = NSMenuItem(
            title: L("Quit"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.indentationLevel = 0
        menu.addItem(quitItem)

        // Update dynamic menu item titles
        updateDynamicMenuItems()

        return menu
    }

    private func updateDynamicMenuItems() {
        // Update pronunciation menu item with provider info
        let provider = model.settings.ttsProvider
        let providerName = provider == .apple
            ? L("System")
            : provider.displayName
        let pronunciationTitle = model.settings.playPronunciation
            ? String(format: L("Pronunciation: On (%@)"), providerName)
            : L("Pronunciation: Off")
        pronunciationMenuItem?.title = pronunciationTitle

        // Update continuous translation menu item
        let continuousTitle = model.settings.continuousTranslation
            ? L("Continuous Translation: On")
            : L("Continuous Translation: Off")
        continuousTranslationMenuItem?.title = continuousTitle
    }

    private func updateMenuLanguage() {
        // Recreate menu with new language
        if let item = statusItem {
            let menu = createStatusBarMenu()
            item.menu = menu
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Update menu item states before showing
        updateDynamicMenuItems()
    }

    // This method is kept for compatibility but no longer used
    // When statusItem.menu is set, the system handles menu display automatically
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {}

    @objc private func togglePronunciation() {
        model.settings.playPronunciation.toggle()
    }

    @objc private func toggleContinuousTranslation() {
        model.settings.continuousTranslation.toggle()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func openAbout() {
        openSettings(initialTab: .about)
    }

    @objc func openSettingsWindow() {
        openSettings(initialTab: .general)
    }

    private func openSettings(initialTab: SettingsTab) {
        isManualWindowOpen = true
        NSApp.setActivationPolicy(.regular)
        if let window = settingsWindow, window.isVisible {
            NotificationCenter.default.post(name: .switchSettingsTab, object: initialTab)
            // Defer activation to after the status bar menu fully closes,
            // otherwise makeKeyAndOrderFront may fail while the menu is dismissing.
            DispatchQueue.main.async {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            showSettingsWindow(initialTab: initialTab)
        }
    }

    private func makeStatusBarImage() -> NSImage? {
        if let image = NSImage(named: "StatusBarIcon")?.copy() as? NSImage {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            return image
        }

        if let sourceImage = NSApp.applicationIconImage,
           let image = sourceImage.copy() as? NSImage {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            return image
        }

        return nil
    }

    private func checkPermissionGrantRestart() {
        let lastStatus = UserDefaults.standard.bool(forKey: AppSettingKey.lastScreenRecordingStatus)
        let currentStatus = CGPreflightScreenCaptureAccess()
        
        if !lastStatus && currentStatus {
            shouldShowWindowAfterPermissionGrant = true
        }
        
        UserDefaults.standard.set(currentStatus, forKey: AppSettingKey.lastScreenRecordingStatus)
    }

    private func refreshAndUpdateVisibility() async {
        await model.permissions.refreshStatusAsync()
        await updateVisibilityFromCurrentState()
    }

    private func scheduleVisibilityUpdate() {
        visibilityTask?.cancel()
        visibilityTask = Task { [weak self] in
            guard let self else { return }
            await self.updateVisibilityFromCurrentState()
        }
    }

    private func updateVisibilityFromCurrentState() async {
        var needsSettings = !model.permissions.status.screenRecording

        if #available(macOS 15.0, *) {
            let status = await model.languagePackManager?.checkLanguagePairQuiet(
                from: model.settings.sourceLanguage,
                to: model.settings.targetLanguage
            )
            if let status {
                needsSettings = needsSettings || status != .installed
            } else {
                needsSettings = true
            }
        }

        if needsSettings {
            showSettingsWindow()
        } else if shouldShowWindowAfterPermissionGrant {
            shouldShowWindowAfterPermissionGrant = false
            isManualWindowOpen = true
            showSettingsWindow()
        } else if !isManualWindowOpen {
            hideDockIcon()
        }
    }

    private func showSettingsWindow(initialTab: SettingsTab = .general) {
        let windowController = settingsWindowController ?? SettingsWindowController(model: model, initialTab: initialTab)
        settingsWindowController = windowController
        settingsWindow?.delegate = self
        NSApp.setActivationPolicy(.regular)
        windowController.showWindow(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideDockIcon() {
        isManualWindowOpen = false
        settingsWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(model: AppModel, initialTab: SettingsTab = .general) {
        let contentView = SettingsWindowView(initialTab: initialTab)
            .environmentObject(model)
        let hostingView = NSHostingView(rootView: contentView)
        let initialContentSize = SettingsWindowLayout.windowContentSize(for: initialTab)
        let initialContentRect = NSRect(origin: .zero, size: initialContentSize)
        hostingView.frame = initialContentRect

        let window = NSWindow(
            contentRect: initialContentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = L("Settings")
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(macOS 15.0, *)
func createTranslationServiceWindow(model: AppModel) {
    guard TranslationServiceWindowHolder.shared.window == nil else { return }

    let translationView = TranslationBridgeView(
        bridge: model.translationBridge
    )

    let hostingView = NSHostingView(rootView: translationView)
    hostingView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.isOpaque = false
    window.backgroundColor = .clear
    window.setIsVisible(false)

    TranslationServiceWindowHolder.shared.window = window
}

@available(macOS 15.0, *)
class TranslationServiceWindowHolder {
    static let shared = TranslationServiceWindowHolder()
    var window: NSWindow?
    private init() {}
}

@available(macOS 15.0, *)
func warmupServices(model: AppModel) {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 500_000_000)

        let sourceLanguage = Locale.Language(identifier: model.settings.sourceLanguage)
        let targetLanguage = Locale.Language(identifier: model.settings.targetLanguage)

        _ = try? await model.translationBridge.translate(
            text: "hello",
            source: sourceLanguage,
            target: targetLanguage,
            timeout: 10.0
        )

        print("✅ Translation service warmed up (source: \(model.settings.sourceLanguage), target: \(model.settings.targetLanguage))")
    }
}
