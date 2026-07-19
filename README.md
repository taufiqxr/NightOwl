# NightOwl 🦉

A tiny macOS menu bar app that keeps your Mac awake — **even with the lid
closed**.

## Why NightOwl exists

If you run anything on a MacBook that needs to stay alive (a home server, a
bot, a long download, a build), closing the lid kills it: macOS **force-sleeps**
a MacBook on lid close unless it's docked to both AC power *and* an external
display. Popular keep-awake tools — `caffeinate`, Amphetamine, and friends —
**cannot prevent this**. Their power assertions only stop *idle* sleep; the
forced clamshell sleep ignores them entirely.

The only switch that survives a lid close is macOS's own
`pmset disablesleep`, which requires admin rights and is easy to misuse
(a Mac that *never* sleeps will happily cook in a backpack). NightOwl wraps
it in a menu bar app with three explicit modes and an always-visible status.

## What you see

- **🦉 in the menu bar** — your Mac will *not* sleep, lid closed or not.
- **💤 in the menu bar** — your Mac sleeps normally; closing the lid sleeps it.

The icon reflects the *actual* system state (checked every 10 seconds), not
just what NightOwl last did — so it stays honest even if something else
changes the setting.

## Modes

| Mode | Behavior | Use it when |
|---|---|---|
| 🦉 **Always Awake** | Never sleeps, plugged in or on battery | The Mac is a stationary appliance. **Don't forget it in a closed bag** — it will stay on and run hot. |
| 🔌 **Smart Auto** | Awake whenever plugged in; normal sleep on battery | Set-and-forget. Bag-safe by construction: unplugged = normal sleep. |
| 💤 **Normal Sleep** | The macOS default | You want stock behavior back. |

Every mode change asks for your admin password via the standard macOS
dialog — that's macOS protecting the power switch, not NightOwl phoning home.

## Install

### Option A — build from source (recommended)

Requires the Xcode Command Line Tools (`xcode-select --install`), macOS 13+.

```bash
git clone https://github.com/taufiqxr/NightOwl.git
cd NightOwl
./build.sh --install
```

That compiles, installs to `/Applications`, and launches it. NightOwl adds
itself to your Login Items on first run (toggle it off in the menu anytime).

### Option B — download the app directly

Grab `NightOwl-<version>.zip` from the
[Releases page](https://github.com/taufiqxr/NightOwl/releases).
Unzip, drag `NightOwl.app` to `/Applications`, then **right-click → Open**
the first time (it's not notarized with a paid Apple developer account, so
Gatekeeper needs the explicit right-click → Open once). If macOS still
refuses, clear the download quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/NightOwl.app
```

To create that zip from source: `./build.sh --release` → `dist/NightOwl-<version>.zip`.

## How it works (and what runs as root)

Transparency matters for a tool that asks for your password, so here is the
complete list of what NightOwl does with admin rights:

- **Always Awake** runs `pmset -a disablesleep 1`.
- **Normal Sleep** runs `pmset -a disablesleep 0`.
- **Smart Auto** installs a small root LaunchDaemon
  (`/Library/LaunchDaemons/com.nightowl.auto.plist` +
  `/usr/local/bin/nightowl-auto.sh` — ~20 lines of shell you can read in
  `Resources/`) that checks the power source every 20 seconds and applies
  the rule: AC → `disablesleep 1`, battery → `disablesleep 0`.
- Switching modes always removes the daemon first, so it can never fight a
  manual choice.

Nothing else. No network access, no analytics, no background helpers beyond
the one daemon Smart Auto installs (and removes when you leave that mode).

`disablesleep` persists across reboots; whatever mode you pick stays picked.

## Uninstall

```bash
./uninstall.sh
```

Quits the app, removes the Smart Auto daemon if present, restores normal
sleep (`disablesleep 0`), and deletes `/Applications/NightOwl.app`.

## Requirements

- macOS 13 Ventura or later (Apple Silicon or Intel)
- An admin account (mode changes use the macOS admin-password dialog)

## License

MIT — see [LICENSE](LICENSE).
