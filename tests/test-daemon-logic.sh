#!/bin/bash
# NightOwl daemon logic tests.
#
# Runs ONE cycle of Resources/nightowl-auto.sh against mocked system tools
# (pmset / ioreg / logger) and asserts exactly which privileged commands it
# issued for each power/battery/lid scenario. No root, no real pmset calls.
#
#   bash tests/test-daemon-logic.sh
set -u
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

# One-cycle copy of the daemon: strip absolute tool paths so PATH-mocking
# works, and turn the poll sleep into an exit.
sed -e 's|/usr/bin/pmset|pmset|g; s|/usr/sbin/ioreg|ioreg|g; s|/usr/bin/logger|logger|g' \
    -e 's|/usr/bin/head|head|g; s|/usr/bin/grep|grep|g; s|/usr/bin/tr|tr|g; s|/usr/bin/awk|awk|g' \
    -e 's|sleep 20|exit 0|' \
    Resources/nightowl-auto.sh > "$WORK/one-cycle.sh"

cat > "$WORK/bin/pmset" <<'EOF'
#!/bin/bash
if [ "$1" = "-g" ] && [ "${2:-}" = "ps" ]; then
  if [ "$MOCK_AC" = "1" ]; then echo "Now drawing from 'AC Power'"; else echo "Now drawing from 'Battery Power'"; fi
  [ -n "$MOCK_PCT" ] && echo " -InternalBattery-0 (id=123)	${MOCK_PCT}%; discharging; 3:00 remaining"
elif [ "$1" = "-g" ]; then
  echo " SleepDisabled		${MOCK_CUR}"
elif [ "$1" = "-a" ]; then
  echo "disablesleep $3" >> "$MOCK_LOG"
elif [ "$1" = "sleepnow" ]; then
  echo "sleepnow" >> "$MOCK_LOG"
fi
EOF

cat > "$WORK/bin/ioreg" <<'EOF'
#!/bin/bash
echo "\"AppleClamshellState\" = ${MOCK_LID}"
EOF

cat > "$WORK/bin/logger" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "$WORK/bin/"*

PASS=0
FAIL=0

# check <mode> <ac> <pct> <cur> <lid Yes|No> <expected ;-joined privileged calls or "none">
check() {
  local mode=$1 ac=$2 pct=$3 cur=$4 lid=$5 expect=$6
  export MOCK_AC=$ac MOCK_PCT=$pct MOCK_CUR=$cur MOCK_LID=$lid MOCK_LOG="$WORK/calls.txt"
  rm -f "$MOCK_LOG"
  PATH="$WORK/bin:$PATH" bash "$WORK/one-cycle.sh" "$mode"
  local got
  got=$(paste -sd';' "$MOCK_LOG" 2>/dev/null || true)
  [ -z "$got" ] && got="none"
  if [ "$got" = "$expect" ]; then
    PASS=$((PASS+1))
    echo "PASS  mode=$mode ac=$ac pct=${pct:-n/a} cur=$cur lid=$lid -> $got"
  else
    FAIL=$((FAIL+1))
    echo "FAIL  mode=$mode ac=$ac pct=${pct:-n/a} cur=$cur lid=$lid -> got '$got', expected '$expect'"
  fi
}

echo "== always mode =="
check always 1 50 0 No  "disablesleep 1"                 # AC: awake
check always 0 50 0 No  "disablesleep 1"                 # battery, healthy: awake
check always 0 15 1 No  "disablesleep 0"                 # guard trips, lid open: no force
check always 0 15 1 Yes "disablesleep 0;sleepnow"        # guard trips, lid closed: force sleep
check always 0 16 0 No  "none"                           # hysteresis band holds 0
check always 0 17 1 No  "none"                           # hysteresis band holds 1
check always 0 18 0 No  "disablesleep 1"                 # re-arms at 18%
check always 0 "" 0 No  "disablesleep 1"                 # no battery reading: treat as full

echo "== auto mode =="
check auto 1 50 0 No  "disablesleep 1"                   # AC: awake
check auto 0 50 1 No  "disablesleep 0"                   # battery: normal sleep
check auto 0 50 1 Yes "disablesleep 0;sleepnow"          # unplugged with lid closed: force sleep
check auto 0 50 0 No  "none"                             # battery, already normal: no-op
check auto 1 50 1 Yes "none"                             # AC, already awake: no-op, no force

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
