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
//   Always Awake : never sleeps — with a low-battery guard (a root daemon
//                  restores normal sleep below 15% on battery, so a
//                  forgotten Mac can't run itself flat; re-arms at 18%
//                  or on AC)
//   Smart Auto   : the same daemon in "auto" mode — awake on AC power,
//                  normal sleep on battery (bag-safe)
//   Normal Sleep : disablesleep 0 — the macOS default, no daemon
//
// Every mode change runs through the standard macOS admin-password dialog.

// Single source of truth for the version is Resources/Info.plist —
// scripts/release.sh reads the same key to cut releases.
let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
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

func batteryPercent() -> Int? {
    let out = shell("/usr/bin/pmset -g ps")
    guard let r = out.range(of: #"\d+%"#, options: .regularExpression) else { return nil }
    return Int(out[r].dropLast())
}

/// nil = no daemon installed; "auto" or "always" = installed daemon's mode.
/// A pre-1.1 plist (no mode argument) behaved as "auto".
func installedDaemonMode() -> String? {
    guard let s = try? String(contentsOfFile: daemonPlistPath, encoding: .utf8) else { return nil }
    if s.contains("<string>always</string>") { return "always" }
    return "auto"
}

/// The plist can exist while the daemon itself is dead (failed bootstrap,
/// crash). pgrep sees root processes from a user session, no privileges
/// needed — so the menu can tell the truth instead of trusting the file.
func daemonProcessRunning() -> Bool {
    !shell("/usr/bin/pgrep -f 'nightowl-auto.sh'").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// True when the installed daemon script differs from the copy bundled in
/// this app version — i.e. an app upgrade shipped a newer daemon and the
/// user hasn't re-selected a mode yet.
func daemonScriptOutdated() -> Bool {
    guard let res = Bundle.main.resourcePath,
          FileManager.default.fileExists(atPath: daemonScriptPath) else { return false }
    let installed = shell("/sbin/md5 -q '\(daemonScriptPath)'")
    let bundled = shell("/sbin/md5 -q '\(res)/nightowl-auto.sh'")
    return !installed.isEmpty && !bundled.isEmpty && installed != bundled
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
        // Single instance: a second copy would just add a second owl.
        let mine = Bundle.main.bundleIdentifier ?? "com.nightowl.app"
        if NSRunningApplication.runningApplications(withBundleIdentifier: mine)
            .filter({ $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })
            .count > 0 {
            NSApp.terminate(nil)
            return
        }

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
        let ac = onACPower()
        let mode = installedDaemonMode()  // nil | "auto" | "always"

        addInfo(menu, awake ? "Your Mac will NOT sleep — even with the lid closed"
                            : "Your Mac sleeps normally — lid close = sleep")
        var powerLine = ac ? "Power: plugged in" : "Power: on battery"
        if !ac, let pct = batteryPercent() { powerLine += " — \(pct)%" }
        addInfo(menu, powerLine)
        if mode == "always" && !awake && !ac {
            addInfo(menu, "Low-battery guard active — re-arms when charging")
        }

        // Daemon self-checks: the file can exist while the process is dead,
        // and an app upgrade can leave an older script installed. Both are
        // one click to fix (reinstalls the daemon in the same mode).
        if mode != nil && !daemonProcessRunning() {
            let repair = NSMenuItem(title: "⚠️ Daemon not running — click to repair",
                                    action: #selector(repairDaemon), keyEquivalent: "")
            repair.target = self
            menu.addItem(repair)
        } else if mode != nil && daemonScriptOutdated() {
            let update = NSMenuItem(title: "⬆️ Daemon update available — click to install",
                                    action: #selector(repairDaemon), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
        }
        menu.addItem(.separator())

        addMode(menu, "🦉 Always Awake — never sleep (15% battery guard)",
                #selector(setAlwaysAwake),
                checked: mode == "always" || (mode == nil && awake))
        addMode(menu, "🔌 Smart Auto — awake when plugged in, sleep on battery",
                #selector(setSmartAuto), checked: mode == "auto")
        addMode(menu, "💤 Normal Sleep — macOS default",
                #selector(setNormalSleep), checked: mode == nil && !awake)

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
    // Every switch first removes the daemon (so it can never fight the new
    // choice), then applies the requested state — all in ONE admin prompt.

    var removeDaemonCmd: String {
        "launchctl bootout system/\(daemonLabel) 2>/dev/null; " +
        "rm -f '\(daemonPlistPath)' '\(daemonScriptPath)'; true"
    }

    /// Installs the root daemon in the given mode ("always" or "auto") and
    /// applies the correct immediate state so there's no 20-second gap.
    func installDaemonCmd(mode: String) -> String {
        guard let res = Bundle.main.resourcePath else { return "false" }
        let immediate = mode == "always"
            ? "/usr/bin/pmset -a disablesleep 1"
            : "if /usr/bin/pmset -g ps | /usr/bin/head -1 | /usr/bin/grep -q 'AC Power'; " +
              "then /usr/bin/pmset -a disablesleep 1; else /usr/bin/pmset -a disablesleep 0; fi"
        return """
            \(removeDaemonCmd); \
            mkdir -p /usr/local/bin; \
            cp -f '\(res)/nightowl-auto.sh' '\(daemonScriptPath)'; \
            chown root:wheel '\(daemonScriptPath)'; chmod 755 '\(daemonScriptPath)'; \
            cp -f '\(res)/\(daemonLabel).plist' '\(daemonPlistPath)'; \
            /usr/bin/sed -i '' 's/MODE_PLACEHOLDER/\(mode)/' '\(daemonPlistPath)'; \
            chown root:wheel '\(daemonPlistPath)'; chmod 644 '\(daemonPlistPath)'; \
            \(immediate); \
            launchctl bootstrap system '\(daemonPlistPath)'
            """
    }

    @objc func setAlwaysAwake() {
        applyChange(installDaemonCmd(mode: "always"))
    }

    @objc func setSmartAuto() {
        applyChange(installDaemonCmd(mode: "auto"))
    }

    @objc func setNormalSleep() {
        applyChange("\(removeDaemonCmd); /usr/bin/pmset -a disablesleep 0")
    }

    /// Reinstalls the daemon in whatever mode is currently configured —
    /// used by the "not running" and "update available" menu items.
    @objc func repairDaemon() {
        guard let mode = installedDaemonMode() else { return }
        applyChange(installDaemonCmd(mode: mode))
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
            🦉 Always Awake — the Mac never sleeps, plugged in or not. A \
            low-battery guard restores normal sleep below 15% on battery \
            (re-arms at 18% or on the charger), so a forgotten Mac can't \
            run itself flat.
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
