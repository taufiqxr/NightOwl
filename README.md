# NightOwl 🦉

[![CI](https://github.com/taufiqxr/NightOwl/actions/workflows/ci.yml/badge.svg)](https://github.com/taufiqxr/NightOwl/actions/workflows/ci.yml)

A tiny macOS menu bar app that keeps your Mac awake — **even with the lid
closed**.

Perfect for running bots, agents, home servers, long downloads, or anything
else that needs a Mac awake 24/7 — **turn a MacBook you already own into an
always-on machine, no Mac mini required.**

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
| 🦉 **Always Awake** | Never sleeps, plugged in or on battery — with a **low-battery guard**: below 15% on battery, normal sleep is restored so a forgotten Mac can't run itself flat (re-arms at 18% or on the charger) | The Mac is a stationary appliance that occasionally goes mobile. |
| 🔌 **Smart Auto** | Awake whenever plugged in; normal sleep on battery | Set-and-forget. Bag-safe by construction: unplugged = normal sleep. |
| 💤 **Normal Sleep** | The macOS default | You want stock behavior back. |

The menu always shows the live status, the power source, and — when on
battery — the current charge percentage.

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

- **Always Awake** and **Smart Auto** install a small root LaunchDaemon
  (`/Library/LaunchDaemons/com.nightowl.auto.plist` +
  `/usr/local/bin/nightowl-auto.sh` — ~40 lines of shell you can read in
  `Resources/`) that checks the power state every 20 seconds:
  - in **auto** mode: AC → `disablesleep 1`, battery → `disablesleep 0`;
  - in **always** mode: `disablesleep 1` everywhere, except the
    low-battery guard — at ≤15% on battery it runs `disablesleep 0`
    (re-arming at ≥18% or on AC). The guard runs as root precisely so it
    works *unattended* — no password prompt when the Mac is forgotten in
    a bag.
- **Normal Sleep** removes the daemon and runs `pmset -a disablesleep 0`.
- Switching modes always removes the daemon first, so it can never fight
  the new choice.
- When the daemon restores sleep permission while the lid is already
  closed (guard trip in a bag, or unplugging a closed Smart Auto Mac),
  it puts the Mac to sleep immediately (`pmset sleepnow`) instead of
  waiting for macOS to get around to it.
- The daemon logs every state change to the system log — view it with
  Console.app or:
  ```bash
  log show --predicate 'eventMessage CONTAINS "NightOwl"' --last 1h
  ```
- The menu self-checks the daemon: if the process has died, or an app
  update shipped a newer daemon script than the one installed, the menu
  shows a one-click repair/update item. The daemon's decision logic is
  covered by [mock-based tests](tests/test-daemon-logic.sh) run in CI on
  every push.

Nothing else. No network access, no analytics, no background helpers beyond
the one daemon Smart Auto installs (and removes when you leave that mode).

`disablesleep` persists across reboots; whatever mode you pick stays picked.

## FAQ

**My screen still turns off and locks when I close the lid — is it even
working?**
Yes — that's the design. The *display* sleeps and locks; the *machine* keeps
running. Check the menu bar icon (🦉 = awake) or run
`pmset -g | grep SleepDisabled` — `1` means every server, download, and
script is still going with the lid shut.

**Will Always Awake drain my battery?**
It will use it, yes — unplugged, the Mac stays fully on. But it won't run
itself flat: the built-in guard restores normal sleep below 15% battery
(and re-arms once you're back on the charger or above 18%). If your Mac
travels a lot, 🔌 **Smart Auto** is still the better fit: normal sleep the
moment you unplug.

**How do I verify what state my Mac is in right now?**
```bash
pmset -g | grep SleepDisabled   # 1 = won't sleep, 0 = sleeps normally
```
The menu bar icon shows the same thing live (🦉 / 💤), and it reflects the
actual system state — not just what NightOwl last did.

**Why does it need my admin password?**
`pmset disablesleep` is a root-level power switch — macOS itself requires
admin rights for it. NightOwl asks through the standard macOS dialog and the
[How it works](#how-it-works-and-what-runs-as-root) section lists every
command it runs with those rights.

**Does the Mac wake up fine afterward?**
Nothing about wake changes — open the lid or press a key as usual. NightOwl
only controls whether the Mac is *allowed* to sleep.

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
