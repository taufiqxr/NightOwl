# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

NightOwl 🦉 — a public, MIT-licensed macOS menu bar app
(github.com/taufiqxr/NightOwl) that keeps a Mac awake even with the lid
closed, via `pmset disablesleep`. Born 2026-07-19 out of a real problem: a
MacBook running always-on services kept dying on lid close. The key
technical fact behind the whole app: caffeinate/Amphetamine-style
assertions only stop *idle* sleep — clamshell sleep ignores them entirely;
only `disablesleep` survives a lid close.

## Commands

```bash
./build.sh                       # compile + assemble build/NightOwl.app (ad-hoc signed)
./build.sh --install             # + install to /Applications and (re)launch
./build.sh --release             # + shareable zip in dist/
bash tests/test-daemon-logic.sh  # 13 mock-based daemon scenarios — run after ANY daemon change
./scripts/release.sh             # cut a GitHub release (CHANGELOG-gated, see below)
./uninstall.sh                   # full removal incl. daemon + disablesleep 0
```

No Xcode project — plain `swiftc` via the Command Line Tools. CI
(`.github/workflows/ci.yml`, macOS runner) runs build + tests on every
push.

## Architecture

Two pieces:

- **`Sources/main.swift`** — the menu bar app (single file, AppKit +
  ServiceManagement). Shows live state (🦉 = `SleepDisabled 1`, 💤 = 0),
  polled every 10s + on wake — it reports the *actual* pmset state, never
  an assumption. Three modes; every mode switch runs ONE admin command
  via osascript `with administrator privileges` (async subprocess, never
  NSAppleScript on a thread), and always removes the daemon before
  applying the new mode so the daemon can't fight it.
- **`Resources/nightowl-auto.sh`** — the root LaunchDaemon
  (`com.nightowl.auto`, installed to `/usr/local/bin/nightowl-auto.sh` +
  `/Library/LaunchDaemons/com.nightowl.auto.plist`), used by BOTH
  non-Normal modes. One script, mode passed as argv (the bundled plist has
  `MODE_PLACEHOLDER`, replaced by `sed` at install time): `auto` = awake
  on AC / sleep on battery; `always` = awake everywhere except the
  low-battery guard (≤15% battery → `disablesleep 0`, re-arm ≥18% or AC,
  hysteresis band holds current state between the two). If sleep
  permission is restored while the lid is closed (ioreg
  AppleClamshellState), it fires `pmset sleepnow` — deterministic for the
  closed-bag case. Every state change logs via `logger -t NightOwl`.

App-side daemon awareness (all in main.swift): `installedDaemonMode()`
parses the installed plist (a pre-1.1 plist with no mode arg reads as
"auto"); `daemonProcessRunning()` uses `pgrep -f nightowl-auto.sh`
(user-privilege view of root processes — the plist can exist while the
process is dead); `daemonScriptOutdated()` compares md5 of installed vs
bundled script. Dead process → "⚠️ click to repair" menu item; stale
script → "⬆️ click to install"; both reinstall in the current mode.

## Conventions & gotchas

- **Version lives ONLY in `Resources/Info.plist`** — main.swift reads
  `CFBundleShortVersionString` at runtime and `scripts/release.sh` reads
  the same key. Don't reintroduce a hardcoded version string.
- **Release process is CHANGELOG-driven**: bump Info.plist, add a
  `## [<version>] — <date>` section to CHANGELOG.md, commit, run
  `./scripts/release.sh`. It refuses to ship without the changelog
  section, a clean pushed tree, and passing tests, and publishes the
  changelog section verbatim as the GitHub release notes.
- **The daemon must keep using absolute tool paths** (`/usr/bin/pmset`,
  `/usr/sbin/ioreg`, …): the test harness `sed`s exactly those prefixes to
  swap in mocks. A bare `pmset` in the daemon would silently escape the
  mocks (and PATH for LaunchDaemons is minimal anyway).
- **README's "How it works (and what runs as root)" section is a
  transparency contract** — any change to what the daemon or the admin
  commands do MUST be reflected there, and usually in the FAQ. Same for
  the About dialog text in main.swift.
- **Test after daemon edits**: `bash tests/test-daemon-logic.sh` locally,
  and add scenarios for new behavior — CI runs the same suite.
- The app is **ad-hoc signed, not notarized** (no paid Apple account):
  recipients need right-click → Open once; README documents this plus the
  `xattr -dr com.apple.quarantine` fallback. Don't promise a
  no-warning install experience.
- `SMAppService.mainApp` handles Start at Login (registered on first
  launch, toggleable in the menu) — no LaunchAgents.
- The maintainer's Mac is a production user of the app (it runs always-on
  services that must survive lid closes): after changing the app,
  `./build.sh --install` keeps the installed copy in sync, and if the
  daemon script changed, the menu's "⬆️ Daemon update available" needs a
  user click (admin password) to take effect — an agent can't do that
  part.
