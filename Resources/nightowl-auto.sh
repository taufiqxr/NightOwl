#!/bin/bash
# NightOwl Smart Auto daemon (installed by NightOwl.app, runs as root).
#
# Rule: plugged in  -> Mac never sleeps (survives lid closes)
#       on battery  -> normal sleep (always safe to carry in a bag)
#
# Removed automatically when you pick a different mode in NightOwl.
while true; do
  if /usr/bin/pmset -g ps | /usr/bin/head -1 | /usr/bin/grep -q "AC Power"; then
    want=1
  else
    want=0
  fi
  cur=$(/usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/{print $2}')
  if [ "$cur" != "$want" ]; then
    /usr/bin/pmset -a disablesleep "$want"
  fi
  sleep 20
done
