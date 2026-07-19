import Cocoa
import ServiceManagement

// NightOwl — a menu bar utility that keeps your Mac awake, even with the
// lid closed.
//
// macOS force-sleeps a MacBook when the lid closes unless it is docked to
// AC power AND an external display. Tools like caffeinate or Amphetamine
// cannot prevent that — their assertions only stop *idle* sleep. The only
// switch that survives a lid close is `pmset disablesleep`, which needs
// admin rights. NightOwl wraps it in three modes:
//
//   Always Awake : disablesleep 1, permanently (careful in a bag!)
//   Smart Auto   : a root LaunchDaemon keeps the Mac awake on AC power
//                  and restores normal sleep on battery (bag-safe)
//   Normal Sleep : disablesleep 0 — the macOS default
//
// Every mode change runs through the standard macOS admin-password dialog.

let appVersion = "1.0.0"
let daemonLabel = "com.nightowl.auto"
let daemonPlistPath = "/Library/LaunchDaemons/com.nightowl.auto.plist"
let daemonScriptPath = "/usr/local/bin/nightowl-auto.sh"

// MARK: - System state helpers

@discardableResult
func shell(_ cmd: String) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-c", cmd]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do { try p.run() } catch { return "" }
    p.waitUntilExit()
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

func sleepDisabledNow() -> Bool {
    for line in shell("/usr/bin/pmset -g").split(separator: "\n")
    where line.contains("SleepDisabled") {
        return line.contains("1")
    }
    return false
}

func onACPower() -> Bool {
    shell("/usr/bin/pmset -g ps").contains("AC Power")
}

func autoModeInstalled() -> Bool {
    FileManager.default.fileExists(atPath: daemonPlistPath)
}

// MARK: - Privileged execution

enum AdminResult {
    case success
    case cancelled
    case failed(String)
}

/// Runs a shell command as root via the standard macOS admin-password
/// dialog. Uses an osascript subprocess so the app's UI never blocks.
func runAdmin(_ cmd: String, completion: @escaping (AdminResult) -> Void) {
    let escaped = cmd
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    let src = "do shell script \"\(escaped)\" with administrator privileges"

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", src]
    let errPipe = Pipe()
    p.standardError = errPipe
    p.standardOutput = Pipe()
    p.terminationHandler = { proc in
        let errText = String(
            data: errPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8) ?? ""
        DispatchQueue.main.async {
            if proc.terminationStatus == 0 {
                completion(.success)
            } else if errText.contains("-128") || errText.lowercased().contains("cancel") {
                completion(.cancelled)
            } else {
                completion(.failed(errText.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }
    do { try p.run() } catch {
        DispatchQueue.main.async { completion(.failed(error.localizedDescription)) }
    }
}

// MARK: - App

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()

        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refreshIcon()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshIcon() }

        offerLoginItemOnFirstRun()
    }

    // On the very first launch, enable Start at Login (visible and
    // revocable in the menu and in System Settings > Login Items).
    func offerLoginItemOnFirstRun() {
        let key = "NightOwlLoginItemConfigured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }

    func refreshIcon() {
        let awake = sleepDisabledNow()
        statusItem.button?.title = awake ? "🦉" : "💤"
        statusItem.button?.toolTip = awake
            ? "NightOwl — your Mac will NOT sleep (even lid closed)"
            : "NightOwl — your Mac sleeps normally (lid close = sleep)"
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let awake = sleepDisabledNow()
        let auto = autoModeInstalled()

        addInfo(menu, awake ? "Your Mac will NOT sleep — even with the lid closed"
                            : "Your Mac sleeps normally — lid close = sleep")
        addInfo(menu, onACPower() ? "Power: plugged in" : "Power: on battery")
        menu.addItem(.separator())

        addMode(menu, "🦉 Always Awake — never sleep (careful in a bag)",
                #selector(setAlwaysAwake), checked: !auto && awake)
        addMode(menu, "🔌 Smart Auto — awake when plugged in, sleep on battery",
                #selector(setSmartAuto), checked: auto)
        addMode(menu, "💤 Normal Sleep — macOS default",
                #selector(setNormalSleep), checked: !auto && !awake)

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Start at Login",
                               action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let about = NSMenuItem(title: "About NightOwl…",
                               action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit NightOwl",
                              action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func addInfo(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    func addMode(_ menu: NSMenu, _ title: String, _ sel: Selector, checked: Bool) {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = self
        item.state = checked ? .on : .off
        menu.addItem(item)
    }

    // MARK: Mode changes
    // Every switch first removes the Smart Auto daemon (so it can never
    // fight a manual choice), then applies the requested state — all in
    // ONE admin-password prompt.

    var removeDaemonCmd: String {
        "launchctl bootout system/\(daemonLabel) 2>/dev/null; " +
        "rm -f '\(daemonPlistPath)' '\(daemonScriptPath)'; true"
    }

    @objc func setAlwaysAwake() {
        applyChange("\(removeDaemonCmd); /usr/bin/pmset -a disablesleep 1")
    }

    @objc func setNormalSleep() {
        applyChange("\(removeDaemonCmd); /usr/bin/pmset -a disablesleep 0")
    }

    @objc func setSmartAuto() {
        guard let res = Bundle.main.resourcePath else { return }
        applyChange("""
            \(removeDaemonCmd); \
            mkdir -p /usr/local/bin; \
            cp -f '\(res)/nightowl-auto.sh' '\(daemonScriptPath)'; \
            chown root:wheel '\(daemonScriptPath)'; chmod 755 '\(daemonScriptPath)'; \
            cp -f '\(res)/\(daemonLabel).plist' '\(daemonPlistPath)'; \
            chown root:wheel '\(daemonPlistPath)'; chmod 644 '\(daemonPlistPath)'; \
            launchctl bootstrap system '\(daemonPlistPath)'
            """)
    }

    func applyChange(_ cmd: String) {
        runAdmin(cmd) { [weak self] result in
            self?.refreshIcon()
            switch result {
            case .success, .cancelled:
                break
            case .failed(let msg):
                let a = NSAlert()
                a.messageText = "NightOwl couldn't apply that change"
                a.informativeText = "The previous mode is still active.\n\n\(msg)"
                a.alertStyle = .warning
                a.runModal()
            }
        }
    }

    // MARK: Misc actions

    @objc func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't change the login item"
            a.informativeText = error.localizedDescription
            a.runModal()
        }
    }

    @objc func showAbout() {
        let a = NSAlert()
        a.messageText = "NightOwl \(appVersion) 🦉"
        a.informativeText = """
            Keeps your Mac awake — even with the lid closed.

            Modes:
            🦉 Always Awake — the Mac never sleeps, plugged in or not. \
            Don't forget it in a closed bag on battery.
            🔌 Smart Auto — awake whenever it's plugged in, normal sleep \
            on battery. Set-and-forget.
            💤 Normal Sleep — the macOS default.

            Mode changes ask for your admin password because they use \
            macOS's own power-management switch (pmset disablesleep).
            """
        a.runModal()
    }

    @objc func quitApp() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
