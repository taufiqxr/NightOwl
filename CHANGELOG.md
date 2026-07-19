# Changelog

All notable changes to NightOwl are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com); versions follow
[Semantic Versioning](https://semver.org).

Releases are cut with `scripts/release.sh`, which publishes the matching
section of this file as the GitHub release notes — so this file is the
single source of truth for what shipped.

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

[1.2.0]: https://github.com/taufiqxr/NightOwl/releases/tag/v1.2.0
[1.1.0]: https://github.com/taufiqxr/NightOwl/releases/tag/v1.1.0
[1.0.0]: https://github.com/taufiqxr/NightOwl/releases/tag/v1.0.0
