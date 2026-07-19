# Changelog

All notable changes to NightOwl are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com); versions follow
[Semantic Versioning](https://semver.org).

Releases are cut with `scripts/release.sh`, which publishes the matching
section of this file as the GitHub release notes — so this file is the
single source of truth for what shipped.

## [1.9.0] — 2026-07-19

### Added
- **Claude sessions show their given names**: each session in the Claude
  submenu is now labeled by its Claude Code session name (the one set
  with `/rename`, or the auto-generated one) with the project folder in
  parentheses — so multiple terminals in the same folder are finally
  distinguishable. A ⚡ prefix marks sessions that are actively working
  right now; the submenu detail line adds tty and busy/idle. Source:
  Claude Code's own `~/.claude/sessions/<pid>.json` files — a direct
  pid→name mapping, read locally, nothing leaves the machine.

## [1.8.1] — 2026-07-19

### Fixed
- **Menu stutter on open** (reported live minutes after 1.8.0): the
  background refresh rebuilt the open menu unconditionally when it
  landed. The menu is now only rebuilt when the detected data actually
  changed — and Claude sessions compare by pid/tty/cwd, deliberately
  ignoring the running-time clock, which ticks every second and would
  otherwise count as a "change" on every single open.

## [1.8.0] — 2026-07-19

### Added
- **Jump to this terminal**: each Claude session's submenu can now bring
  its terminal window/tab to the front — Terminal.app and iTerm2 both
  expose per-tab ttys to AppleScript, so NightOwl finds the tab owning
  the session's tty and focuses it. Only already-running terminal apps
  are scripted (a `tell application` to a quit app would launch it).
  First use triggers macOS's one-time "NightOwl wants to control
  Terminal" automation prompt. Sessions hosted in other apps (VS Code
  integrated terminals) get an honest "can't bring it forward" message.

### Changed
- The Claude sessions item is now titled **Claude (N)**.

### Fixed
- **1–2 second menu-open lag** (reported live, introduced in 1.7.0): the
  menu was running a full `lsof` port scan plus one `lsof` per Claude
  session synchronously before it could draw. The menu now opens
  instantly from cached data and refreshes itself in place moments later;
  detection runs off the main thread everywhere (including the 60s watch
  cycle), and the per-session `lsof` calls collapsed into one.

## [1.7.0] — 2026-07-19

### Added
- **Claude terminals submenu**: lists every open Claude Code terminal
  session, labeled by the project folder it's working in (plus its tty),
  with a submenu showing the full path, PID, and running time, and
  **Reveal folder in Finder** / **Copy folder path** actions. Detection:
  interactive `claude` CLI processes (real tty; background helpers
  filtered), working directory via `lsof`. The section hides entirely
  when no sessions are running. `--print-claude-sessions` CLI flag for
  verification.

## [1.6.0] — 2026-07-19

### Changed
- **Services collapsed into one "Servers (N)" item** — hover to expand.
  The first click on the owl now shows a clean menu: status, modes,
  Servers, settings. The top-level "Servers" title carries a ⚠️ badge
  whenever a watched service or tunnel is down, so trouble is still
  visible without expanding; everything inside (per-service submenus,
  Open/Copy URL, watch toggles, DOWN entries) is unchanged.

## [1.5.0] — 2026-07-19

### Added
- **State-aware menu bar icon.** The icon now expresses every state the
  app knows, not just awake/asleep: 🦉 all well · 🦉⚠️ awake but a watched
  service is down or the daemon died · 🪫 low-battery guard tripped ·
  💤 normal sleep · 💤⚠️ sleep allowed and a watch is down. Tooltip
  explains the exact condition; watch transitions update the icon
  immediately, not on the next 10-second tick.

## [1.4.0] — 2026-07-19

### Added
- **Service watch with down/up alerts**: click "Watch" in any service's
  submenu and NightOwl checks it every 60 seconds, posting a macOS
  notification when it goes down and when it comes back. Watches are
  identified by port (they survive service restarts and app relaunches —
  persisted in preferences); tunnels are watched by process name. A
  watched service that goes down stays visible in the menu, marked
  "⚠️ DOWN", so it can still be unwatched. The first check after a watch
  is added or the app relaunches primes silently — no false alarm when
  services simply haven't started yet.
- **Guard and integrity notifications**: when the low-battery guard trips
  ("🛟 normal sleep restored") or re-arms ("🦉 staying awake again"),
  NightOwl posts a notification instead of acting silently. It also
  notifies if `disablesleep` changes *outside* NightOwl (no daemon
  installed, state flipped by something else). Smart Auto's routine
  plug/unplug flips stay silent by design, as do changes you just made
  yourself in the menu.
- Notifications respect the system permission: an explicit "don't allow"
  is honored (NightOwl stays quiet); only a broken registration falls
  back to AppleScript notifications.

## [1.3.0] — 2026-07-19

### Added
- **Services menu**: the menu now lists the local servers and tunnels the
  always-awake Mac is hosting — the things you're keeping it awake *for*.
  Each service opens a submenu with its PID and per-port
  **Open http://localhost:PORT** / **Copy URL** actions; tunnel clients
  (`cloudflared`, `ngrok`) are detected by process since they dial out
  rather than listen. Detection runs only when the menu opens (one `lsof`
  call), system/browser listeners are filtered out, and only process
  name + port + PID are ever shown — never command lines, which can carry
  secrets like tunnel tokens. Servers running as root are not visible
  (user-session `lsof`); documented limitation.
- `--print-services` CLI flag on the app binary: dumps detection to
  stdout and exits, for verification/debugging.

## [1.2.1] — 2026-07-19

### Fixed
- **Daemon logging was invisible.** v1.2.0 logged via `logger -t NightOwl`,
  but `logger(1)` messages don't reliably surface in the unified log on
  modern macOS — `log show` returned nothing, making the feature useless.
  The daemon now appends to `/var/log/nightowl.log` (one line per state
  change). Found within hours of the 1.2.0 release by a live monitoring
  session watching a production install.

## [1.2.0] — 2026-07-19

### Added
- **Deterministic bag protection**: when the daemon restores sleep
  permission while the lid is already closed (low-battery guard trip, or
  Smart Auto going to battery), it puts the Mac to sleep immediately with
  `pmset sleepnow` instead of waiting for macOS.
- **Daemon self-checks in the menu**: "⚠️ Daemon not running — click to
  repair" when the plist exists but the process is dead; "⬆️ Daemon update
  available — click to install" when an app upgrade shipped a newer daemon
  script than the installed one (md5 comparison).
- **System-log visibility**: the daemon logs every state change via
  `logger -t NightOwl`.
- **Single-instance guard**: launching a second copy exits instead of
  adding a second menu bar owl.
- **Test suite + CI**: 13 mock-based daemon logic scenarios in
  `tests/test-daemon-logic.sh`, run by GitHub Actions on every push.

## [1.1.0] — 2026-07-19

### Added
- **Low-battery guard** for Always Awake: at ≤15% on battery, normal sleep
  is restored so a forgotten unplugged Mac can't run itself flat (or hot
  in a closed bag); re-arms at ≥18% or when AC returns, with a hysteresis
  band between the thresholds to prevent flapping.
- Battery percentage in the menu when on battery, and a "guard active"
  status line when the guard has tripped.

### Changed
- Always Awake now installs the same root daemon as Smart Auto (in a new
  `always` mode) — required so the guard works unattended, with no
  password prompt at the critical moment.

## [1.0.0] — 2026-07-19

Initial release.

- Menu bar app with live status (🦉 won't sleep / 💤 sleeps normally),
  reflecting the actual system state every 10 seconds.
- Three modes around macOS's `pmset disablesleep` switch: Always Awake,
  Smart Auto (root LaunchDaemon: awake on AC, normal sleep on battery),
  Normal Sleep.
- One admin-password prompt per mode change; switching always removes the
  daemon first so it can never fight the new choice.
- Start at Login via SMAppService, About dialog, ad-hoc signed build via
  plain `swiftc` (no Xcode project).

[1.9.0]: https://github.com/taufiqxr/NightOwl/releases/tag/v1.9.0
[1.8.1]: https://github.com/taufiqxr/NightOwl/releases/tag/v1.8.1
[1.8.0]: https://github.com/taufiqxr/NightOwl/releases/tag/v1.8.0
[1.7.0]: https://github.com/taufiqxr/NightOwl/releases/tag/v1.7.0
[1.6.0]: https://github.com/taufiqxr/NightOwl/releases/tag/v1.6.0
[1.5.0]: https://github.com/taufiqxr/NightOwl/releases/tag/v1.5.0
[1.4.0]: https://github.com/taufiqxr/NightOwl/releases/tag/v1.4.0
[1.3.0]: https://github.com/taufiqxr/NightOwl/releases/tag/v1.3.0
[1.2.1]: https://github.com/taufiqxr/NightOwl/releases/tag/v1.2.1
[1.2.0]: https://github.com/taufiqxr/NightOwl/releases/tag/v1.2.0
[1.1.0]: https://github.com/taufiqxr/NightOwl/releases/tag/v1.1.0
[1.0.0]: https://github.com/taufiqxr/NightOwl/releases/tag/v1.0.0
