import AppKit
import SwiftUI
import UserNotifications

final class DisplayPowerController {
    static let shared = DisplayPowerController()
    private let scriptPath: String = {
        if let bundled = Bundle.main.path(forResource: "apply-preset", ofType: "sh", inDirectory: "scripts") {
            return bundled
        }
        let devPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/apply-preset.sh")
        if FileManager.default.fileExists(atPath: devPath.path) {
            return devPath.path
        }
        return "/usr/local/share/display-power/scripts/apply-preset.sh"
    }()

    enum Mode: String {
        case alwaysOn = "always-on"
        case batteryDefault = "battery-default"
        case unknown

        var label: String {
            switch self {
            case .alwaysOn: return "螢幕長亮"
            case .batteryDefault: return "電池預設"
            case .unknown: return "未知"
            }
        }

        var symbolName: String {
            switch self {
            case .alwaysOn: return "sun.max.fill"
            case .batteryDefault: return "moon.fill"
            case .unknown: return "display"
            }
        }
    }

    func currentMode() -> Mode {
        if let preset = DisplayPowerPreferences.defaults.string(forKey: "activePreset"),
           let mode = Mode(rawValue: preset) {
            return mode
        }

        let caffeinateRunning = Process()
        caffeinateRunning.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        caffeinateRunning.arguments = ["-f", "com.tern.display-power.caffeinate"]
        let pipe = Pipe()
        caffeinateRunning.standardOutput = pipe
        caffeinateRunning.standardError = Pipe()
        if (try? caffeinateRunning.run()) != nil {
            caffeinateRunning.waitUntilExit()
            if caffeinateRunning.terminationStatus == 0 {
                return .alwaysOn
            }
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g", "custom"]
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return .unknown
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return .unknown }

        var batteryDisplaySleep: String?
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("displaysleep") {
                let parts = trimmed.split(whereSeparator: \.isWhitespace)
                if parts.count >= 2 {
                    batteryDisplaySleep = String(parts[1])
                }
            }
            if trimmed == "AC Power:" { break }
        }

        guard let value = batteryDisplaySleep, let minutes = Int(value) else { return .unknown }
        return minutes == 0 ? .alwaysOn : .batteryDefault
    }

    func apply(_ mode: Mode) async -> (Bool, String) {
        let scriptPath = scriptPath
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                let outPipe = Pipe()
                task.executableURL = URL(fileURLWithPath: "/bin/bash")
                task.arguments = [scriptPath, mode.rawValue]
                task.standardOutput = outPipe
                task.standardError = outPipe

                do {
                    try task.run()
                    task.waitUntilExit()
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let success = task.terminationStatus == 0
                    DispatchQueue.main.async {
                        continuation.resume(returning: (
                            success,
                            success ? "已套用：\(mode.label)" : output
                        ))
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(returning: (false, error.localizedDescription))
                    }
                }
            }
        }
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

enum DisplayPowerPreferences {
    static let showMenuBarIconKey = "showMenuBarIcon"
    static let launchAtLoginKey = "launchAtLogin"
    static let showDockIconKey = "showDockIcon"
    static let defaults = UserDefaults(suiteName: "com.tern.display-power-toggle") ?? .standard

    static func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    static func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
        defaults.synchronize()
    }

    static var showMenuBarIcon: Bool {
        get { bool(forKey: showMenuBarIconKey, default: true) }
        set { set(newValue, forKey: showMenuBarIconKey) }
    }

    static var launchAtLogin: Bool {
        get { bool(forKey: launchAtLoginKey, default: false) }
        set { set(newValue, forKey: launchAtLoginKey) }
    }

    static var showDockIcon: Bool {
        get { bool(forKey: showDockIconKey, default: true) }
        set { set(newValue, forKey: showDockIconKey) }
    }
}

@MainActor
final class LaunchAtLoginController {
    static let shared = LaunchAtLoginController()

    private let label = "com.tern.display-power.launcher"

    private var plistURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path) && isAgentLoaded()
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try install()
        } else {
            uninstall()
        }
    }

    private func isAgentLoaded() -> Bool {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "gui/\(getuid())/\(label)"]
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func install() throws {
        let appPath = Bundle.main.bundlePath
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-a", appPath],
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )

        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: plistURL, options: .atomic)

        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        guard runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path]) else {
            throw NSError(
                domain: "DisplayPower",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "無法啟用開機自動啟動"]
            )
        }
    }

    private func uninstall() {
        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}

@MainActor
final class DockIconController {
    static let shared = DockIconController()

    func setVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        if visible {
            NSApp.activate(ignoringOtherApps: false)
        }
    }
}

@MainActor
final class DisplayPowerModel: ObservableObject {
    static let shared = DisplayPowerModel()

    @Published var mode: DisplayPowerController.Mode = .unknown
    @Published var isApplying = false
    @Published var statusText = "讀取中…"
    @Published var showMenuBarIcon = DisplayPowerPreferences.showMenuBarIcon
    @Published var launchAtLogin = DisplayPowerPreferences.launchAtLogin
    @Published var showDockIcon = DisplayPowerPreferences.showDockIcon
    @Published var menuBarIconStatusText = ""
    @Published var launchAtLoginStatusText = ""
    @Published var dockIconStatusText = ""

    func applyMenuBarIconVisibility(_ visible: Bool) {
        showMenuBarIcon = visible
        DisplayPowerPreferences.showMenuBarIcon = visible
        menuBarIconStatusText = visible ? "選單列圖示：顯示中" : "選單列圖示：已隱藏"
        StatusBarController.shared.setVisible(visible, model: self)
    }

    func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginController.shared.setEnabled(enabled)
            launchAtLogin = enabled
            DisplayPowerPreferences.launchAtLogin = enabled
            launchAtLoginStatusText = enabled ? "登入時自動啟動：已開啟" : "登入時自動啟動：已關閉"
        } catch {
            launchAtLogin = LaunchAtLoginController.shared.isEnabled()
            let alert = NSAlert()
            alert.messageText = "無法設定開機自動啟動"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    func applyDockIconVisibility(_ visible: Bool) {
        showDockIcon = visible
        DisplayPowerPreferences.showDockIcon = visible
        dockIconStatusText = visible ? "Dock 圖示：顯示中" : "Dock 圖示：已隱藏"
        DockIconController.shared.setVisible(visible)
    }

    func loadPreferences() {
        let menuBar = DisplayPowerPreferences.showMenuBarIcon
        applyMenuBarIconVisibility(menuBar)

        let dock = DisplayPowerPreferences.showDockIcon
        applyDockIconVisibility(dock)

        let loginEnabled = LaunchAtLoginController.shared.isEnabled()
        launchAtLogin = loginEnabled
        DisplayPowerPreferences.launchAtLogin = loginEnabled
        launchAtLoginStatusText = loginEnabled ? "登入時自動啟動：已開啟" : "登入時自動啟動：已關閉"
    }

    func refresh() {
        let current = DisplayPowerController.shared.currentMode()
        mode = current
        statusText = "目前模式：\(current.label)"
        if showMenuBarIcon {
            StatusBarController.shared.update(from: self)
        }
    }

    func apply(_ target: DisplayPowerController.Mode) async {
        guard !isApplying else { return }
        isApplying = true
        statusText = "套用中：\(target.label)…"
        if showMenuBarIcon {
            StatusBarController.shared.update(from: self)
        }

        let (success, message) = await DisplayPowerController.shared.apply(target)
        refresh()
        isApplying = false
        DisplayPowerController.shared.notify(
            title: success ? "Display Power" : "套用失敗",
            body: message
        )

        if !success {
            let alert = NSAlert()
            alert.messageText = "套用失敗"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private weak var model: DisplayPowerModel?
    private(set) var isReady = false

    func setup(model: DisplayPowerModel) {
        self.model = model
        isReady = true
        setVisible(model.showMenuBarIcon, model: model)
    }

    func setVisible(_ visible: Bool, model: DisplayPowerModel) {
        guard isReady else { return }
        self.model = model

        if visible {
            installStatusItem()
            update(from: model)
        } else {
            removeStatusItem()
        }
    }

    private func installStatusItem() {
        removeStatusItem()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if #available(macOS 13.0, *) {
            item.behavior = .removalAllowed
        }
        item.isVisible = true
        item.autosaveName = "DisplayPowerStatusItem"
        statusItem = item
    }

    private func removeStatusItem() {
        guard let item = statusItem else { return }
        item.menu = nil
        item.isVisible = false
        item.button?.isHidden = true
        item.length = 0
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    func update(from model: DisplayPowerModel) {
        guard model.showMenuBarIcon else {
            removeStatusItem()
            return
        }

        if statusItem == nil {
            installStatusItem()
        }

        guard let statusItem, let button = statusItem.button else { return }
        button.isHidden = false
        statusItem.isVisible = true
        statusItem.length = NSStatusItem.variableLength

        let emoji = model.mode == .alwaysOn ? "☀️" : "🌙"
        button.title = emoji
        button.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        button.image = nil
        button.imagePosition = .noImage
        button.contentTintColor = .systemOrange
        button.toolTip = "Display Power — \(model.statusText)"
        button.setAccessibilityLabel("Display Power")
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let statusItem, let model else { return }
        let menu = NSMenu()

        let status = NSMenuItem(title: model.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let alwaysOn = NSMenuItem(title: "☀️  螢幕維持長亮", action: #selector(applyAlwaysOn), keyEquivalent: "1")
        alwaysOn.target = self
        alwaysOn.state = model.mode == .alwaysOn ? .on : .off
        alwaysOn.isEnabled = !model.isApplying
        menu.addItem(alwaysOn)

        let battery = NSMenuItem(title: "🔋  恢復電池預設", action: #selector(applyBatteryDefault), keyEquivalent: "2")
        battery.target = self
        battery.state = model.mode == .batteryDefault ? .on : .off
        battery.isEnabled = !model.isApplying
        menu.addItem(battery)

        menu.addItem(.separator())

        let showWindow = NSMenuItem(title: "開啟控制視窗", action: #selector(showWindow), keyEquivalent: "o")
        showWindow.target = self
        menu.addItem(showWindow)

        let refresh = NSMenuItem(title: "重新整理狀態", action: #selector(refreshStatus), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let toggleIcon = NSMenuItem(title: "顯示選單列圖示", action: #selector(toggleMenuBarIcon), keyEquivalent: "")
        toggleIcon.target = self
        toggleIcon.state = model.showMenuBarIcon ? .on : .off
        menu.addItem(toggleIcon)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "結束", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func applyAlwaysOn() {
        Task { await model?.apply(.alwaysOn) }
    }

    @objc private func applyBatteryDefault() {
        Task { await model?.apply(.batteryDefault) }
    }

    @objc private func refreshStatus() {
        model?.refresh()
    }

    @objc private func toggleMenuBarIcon() {
        guard let model else { return }
        model.applyMenuBarIconVisibility(!model.showMenuBarIcon)
    }

    func highlightIcon() {
        guard let button = statusItem?.button else { return }
        let original = button.title
        var ticks = 0
        Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { timer in
            Task { @MainActor in
                ticks += 1
                button.title = (ticks % 2 == 0) ? original : "✦"
                if ticks >= 8 {
                    button.title = original
                    timer.invalidate()
                }
            }
        }
    }

    @objc private func showWindow() {
        if DisplayPowerPreferences.showDockIcon {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
            window.center()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

struct AppKitSwitch: NSViewRepresentable {
    @Binding var isOn: Bool
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        button.setButtonType(.switch)
        button.state = isOn ? .on : .off
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        let buttonOn = nsView.state == .on
        if buttonOn != isOn {
            nsView.state = isOn ? .on : .off
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isOn: $isOn, onChange: onChange)
    }

    final class Coordinator: NSObject {
        @Binding var isOn: Bool
        let onChange: (Bool) -> Void

        init(isOn: Binding<Bool>, onChange: @escaping (Bool) -> Void) {
            _isOn = isOn
            self.onChange = onChange
        }

        @objc func changed(_ sender: NSButton) {
            let newValue = sender.state == .on
            isOn = newValue
            onChange(newValue)
        }
    }
}

struct ControlPanel: View {
    @EnvironmentObject private var model: DisplayPowerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: model.mode.symbolName)
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Display Power")
                        .font(.headline)
                    Text(model.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task { await model.apply(.alwaysOn) }
            } label: {
                Label("螢幕維持長亮", systemImage: "sun.max.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .controlSize(.large)
            .disabled(model.isApplying)

            Button {
                Task { await model.apply(.batteryDefault) }
            } label: {
                Label("恢復電池預設", systemImage: "moon.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .controlSize(.large)
            .disabled(model.isApplying)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("顯示選單列圖示")
                    Text(model.menuBarIconStatusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("位置：螢幕右上角，時鐘與 Wi‑Fi 左側")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                AppKitSwitch(isOn: $model.showMenuBarIcon) { visible in
                    model.applyMenuBarIconVisibility(visible)
                }
            }

            if model.showMenuBarIcon {
                Button("閃爍選單列圖示 3 秒") {
                    StatusBarController.shared.highlightIcon()
                }
                .controlSize(.small)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("登入時自動啟動")
                    Text(model.launchAtLoginStatusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                AppKitSwitch(isOn: $model.launchAtLogin) { enabled in
                    model.applyLaunchAtLogin(enabled)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("在 Dock 顯示圖示")
                    Text(model.dockIconStatusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                AppKitSwitch(isOn: $model.showDockIcon) { visible in
                    model.applyDockIconVisibility(visible)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            model.loadPreferences()
            model.refresh()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let powerModel = DisplayPowerModel.shared

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        StatusBarController.shared.setup(model: powerModel)
        powerModel.loadPreferences()
        powerModel.refresh()

        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
                window.center()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}

@main
struct DisplayPowerToggleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Display Power", id: "main") {
            ControlPanel()
                .environmentObject(DisplayPowerModel.shared)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 300, height: 340)
        .windowResizability(.contentSize)
    }
}