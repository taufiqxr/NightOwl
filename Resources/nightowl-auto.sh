#!/bin/bash
# NightOwl daemon (installed by NightOwl.app, runs as root).
#
# Mode "auto":   awake on AC power, normal sleep on battery.
# Mode "always": awake everywhere — except the low-battery guard: below
#                ${LOW}% on battery, normal sleep is restored so a
#                forgotten unplugged Mac can't run itself flat (or hot in
#                a closed bag). Re-arms at ${REARM}% or when AC returns.
#
# Removed automatically when you pick a different mode in NightOwl.
MODE="${1:-auto}"
LOW=15
REARM=18

while true; do
  cur=$(/usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/{print $2}')
  if /usr/bin/pmset -g ps | /usr/bin/head -1 | /usr/bin/grep -q "AC Power"; then
    want=1
  else
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
  fi
  sleep 20
done
