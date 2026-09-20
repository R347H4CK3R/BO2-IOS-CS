#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="${1:-Build/XashSimulatorRuntime/BO2IOSCS.app}"
BUNDLE="com.r347h4ck3r.bo2ioscs.xash"
REPORT="XASH_SIMULATOR_TEST_REPORT.md"
LOGDIR="Build/XashRuntimeLogs"

rm -rf "$LOGDIR"
mkdir -p "$LOGDIR"

UDID="$(python3 - <<'PY'
import json, subprocess
j=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))
devs=[d for xs in j['devices'].values() for d in xs if d.get('isAvailable') and d['name'].startswith('iPhone')]
for wanted in ('iPhone 16 Plus','iPhone 16 Pro Max'):
    for d in devs:
        if d['name'] == wanted:
            print(d['udid']); raise SystemExit
for d in devs:
    if 'Plus' in d['name'] or 'Pro Max' in d['name']:
        print(d['udid']); raise SystemExit
if devs: print(devs[0]['udid'])
PY
)"

if [ -z "$UDID" ]; then
  echo "# Xash Simulator Test" > "$REPORT"
  echo "- status: UNAVAILABLE" >> "$REPORT"
  echo "- reason: no available iPhone Simulator" >> "$REPORT"
  exit 0
fi

xcrun simctl shutdown all >/dev/null 2>&1 || true
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b

xcrun simctl install "$UDID" "$APP" > "$LOGDIR/install.log" 2>&1

(
  xcrun simctl spawn "$UDID" log stream --style compact --level debug \
    --predicate 'process == "xash" OR eventMessage CONTAINS "BO2IOSCS_AUTOTEST" OR eventMessage CONTAINS "Xash"' \
    > "$LOGDIR/xash-live.log" 2>&1
) &
LOG_PID=$!

cleanup() {
  kill "$LOG_PID" >/dev/null 2>&1 || true
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

SIMCTL_CHILD_BO2IOSCS_AUTOTEST=1 \
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" \
  > "$LOGDIR/launch.log" 2>&1

sleep 8
xcrun simctl io "$UDID" screenshot "$LOGDIR/xash-simulator.png" >/dev/null 2>&1 || true
xcrun simctl spawn "$UDID" log show --last 3m --style compact \
  --predicate 'process == "xash" OR eventMessage CONTAINS "BO2IOSCS_AUTOTEST" OR eventMessage CONTAINS "Xash"' \
  > "$LOGDIR/xash.log" 2>&1 || true

AUTOTEST_MARKER=0
ENGINE_MARKER=0
if grep -q 'BO2IOSCS_AUTOTEST launch path enabled' "$LOGDIR/xash.log" "$LOGDIR/xash-live.log" 2>/dev/null; then
  AUTOTEST_MARKER=1
fi
if grep -Eiq 'Xash3D|Xash:|Host_Init|filesystem|gameinfo|bo2ioscs' "$LOGDIR/xash.log" "$LOGDIR/xash-live.log" 2>/dev/null; then
  ENGINE_MARKER=1
fi

STATUS=FAIL
if [ "$AUTOTEST_MARKER" -eq 1 ] && [ "$ENGINE_MARKER" -eq 1 ]; then
  STATUS=PASS
fi

cat > "$REPORT" <<EOF
# Xash Simulator Test

- status: $STATUS
- bundle: $BUNDLE
- simulator UDID: $UDID
- noninteractive iOS launch marker: $AUTOTEST_MARKER
- engine/filesystem marker: $ENGINE_MARKER
- screenshot: $LOGDIR/xash-simulator.png
- logs: $LOGDIR/xash.log
- scope: verifies native Xash iOS startup only; converted BO2 gameplay is not present yet
EOF

echo "$STATUS"
[ "$STATUS" = PASS ]
