#!/bin/bash
# Fully removes NightOwl and restores normal macOS sleep behavior.
# Asks for your admin password once (to remove the Smart Auto daemon,
# if installed, and reset the sleep switch).
set -u

echo "This will quit NightOwl, restore normal sleep, and remove the app."
read -r -p "Proceed? [y/N] " answer
if [[ ! "$answer" =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 0
fi

pkill -f "NightOwl.app/Contents/MacOS/NightOwl" 2>/dev/null

osascript -e 'do shell script "launchctl bootout system/com.nightowl.auto 2>/dev/null; rm -f /Library/LaunchDaemons/com.nightowl.auto.plist /usr/local/bin/nightowl-auto.sh; pmset -a disablesleep 0; true" with administrator privileges' \
  || { echo "Password prompt cancelled — nothing removed."; exit 1; }

rm -rf "/Applications/NightOwl.app"

echo "NightOwl removed. Normal sleep behavior restored."
echo "(If 'NightOwl' still shows under System Settings > General > Login Items, remove it there.)"
