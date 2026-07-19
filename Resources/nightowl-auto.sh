#!/bin/bash
# NightOwl daemon (installed by NightOwl.app, runs as root).
#
# Mode "auto":   awake on AC power, normal sleep on battery.
# Mode "always": awake everywhere — except the low-battery guard: below
#                ${LOW}% on battery, normal sleep is restored so a
#                forgotten unplugged Mac can't run itself flat (or hot in
#                a closed bag). Re-arms at ${REARM}% or when AC returns.
#
# Whenever sleep permission is restored while the lid is already closed,
# the Mac is put to sleep immediately (pmset sleepnow) instead of waiting
# for macOS to get around to it — deterministic for the closed-bag case.
#
# State changes are logged to /var/log/nightowl.log (tiny volume — one
# line per state change). Not the unified log: logger(1) messages don't
# reliably surface in `log show` on modern macOS, verified live.
#
# Removed automatically when you pick a different mode in NightOwl.
MODE="${1:-auto}"
LOW=15
REARM=18
LOGFILE="/var/log/nightowl.log"

log() { echo "$(/bin/date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOGFILE" 2>/dev/null || true; }
log "daemon started (mode=$MODE)"

while true; do
  cur=$(/usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/{print $2}')
  if /usr/bin/pmset -g ps | /usr/bin/head -1 | /usr/bin/grep -q "AC Power"; then
    power="ac"
    pct=""
    want=1
  else
    power="battery"
    pct=$(/usr/bin/pmset -g ps | /usr/bin/grep -Eo '[0-9]+%' | /usr/bin/head -1 | /usr/bin/tr -d '%')
    [ -z "$pct" ] && pct=100   # no battery (desktop Mac): guard never trips
    if [ "$MODE" = "always" ]; then
      if [ "$pct" -le "$LOW" ]; then
        want=0
      elif [ "$pct" -ge "$REARM" ]; then
        want=1
      else
        want="$cur"   # hysteresis band: hold current state, no flapping
      fi
    else
      want=0
    fi
  fi

  if [ "$cur" != "$want" ]; then
    /usr/bin/pmset -a disablesleep "$want"
    log "mode=$MODE power=$power${pct:+ pct=$pct%}: disablesleep $cur -> $want"
    if [ "$want" = "0" ] && /usr/sbin/ioreg -r -k AppleClamshellState -d 1 \
        | /usr/bin/grep -q '"AppleClamshellState" = Yes'; then
      log "lid is closed — forcing sleep now"
      /usr/bin/pmset sleepnow
    fi
  fi
  sleep 20
done
