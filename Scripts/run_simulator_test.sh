#!/bin/bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p Build/RuntimeLogs
REPORT=SIMULATOR_TEST_REPORT.md
RESULT=AUTOTEST_RESULT.json
echo "# Simulator Test Report" > "$REPORT"
UDID="$(python3 - <<'PY'
import json, subprocess
j=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))
devs=[d for _,xs in j['devices'].items() for d in xs if d.get('isAvailable') and d['name'].startswith('iPhone')]
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
  echo "- Runtime validation: UNAVAILABLE (no available iPhone simulator)" >> "$REPORT"
  echo '{"status":"UNAVAILABLE","reason":"no iPhone simulator"}' > "$RESULT"
  exit 0
fi
NAME="$(xcrun simctl list devices | grep "$UDID" | sed -E 's/^[[:space:]]*([^\(]+).*/\1/' | xargs || true)"
echo "- Device: $NAME" >> "$REPORT"
echo "- UDID: $UDID" >> "$REPORT"
xcrun simctl shutdown all >/dev/null 2>&1 || true
xcrun simctl boot "$UDID" 2>/dev/null || true
if ! xcrun simctl bootstatus "$UDID" -b; then
  echo "- Runtime validation: UNAVAILABLE (simulator boot failed)" >> "$REPORT"
  echo '{"status":"UNAVAILABLE","reason":"simulator boot failed"}' > "$RESULT"
  exit 0
fi
APP=Build/DerivedData/Build/Products/Debug-iphonesimulator/BO2IOSCS.app
BUNDLE=com.r347h4ck3r.bo2ioscs
if ! xcrun simctl install "$UDID" "$APP" > Build/RuntimeLogs/install.log 2>&1; then
  echo "- Runtime validation: FAIL (install failed)" >> "$REPORT"
  echo '{"status":"FAIL","reason":"simulator install failed"}' > "$RESULT"
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  exit 1
fi
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)"
# Hosted runners can leave simctl launch itself blocked while the application is
# healthy. Keep that client alive while the in-app autotest runs; an installed
# data container alone is not evidence that launch has completed.
SIMCTL_CHILD_AUTOTEST=1 xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" --autotest > Build/RuntimeLogs/launch.log 2>&1 &
LAUNCH_PID=$!
for _ in $(seq 1 45); do
  if [ -n "$DATA" ] && [ -f "$DATA/Documents/Logs/AUTOTEST_RESULT.json" ]; then
    break
  fi
  # If simctl returned, retain its exit status for diagnostics but still allow
  # a launched app a short window to publish the result.
  if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then
    wait "$LAUNCH_PID" 2>/dev/null
    LAUNCH_RC=$?
    if [ "$LAUNCH_RC" -ne 0 ]; then
      sleep 3
      break
    fi
  fi
  sleep 1
done
if kill -0 "$LAUNCH_PID" 2>/dev/null; then
  kill "$LAUNCH_PID" >/dev/null 2>&1 || true
  wait "$LAUNCH_PID" 2>/dev/null || true
fi
xcrun simctl io "$UDID" screenshot Build/RuntimeLogs/simulator.png >/dev/null 2>&1 || true
xcrun simctl spawn "$UDID" log show --last 4m --style compact --predicate 'process == "BO2IOSCS" OR eventMessage CONTAINS "[BO2IOSCS]"' > Build/RuntimeLogs/application.log 2>&1 || true
STATUS=FAIL
if [ -n "$DATA" ] && [ -f "$DATA/Documents/Logs/AUTOTEST_RESULT.json" ]; then
  cp "$DATA/Documents/Logs/AUTOTEST_RESULT.json" "$RESULT"
  cp "$DATA/Documents/Logs/runtime.log" Build/RuntimeLogs/runtime.log 2>/dev/null || true
  STATUS="$(python3 -c 'import json; d=json.load(open("AUTOTEST_RESULT.json")); ok=d.get("status")=="PASS" and d.get("player_combat_integrated") is True and d.get("player_eliminations",0)>0; print("PASS" if ok else "FAIL")')"
else
  echo '{"status":"FAIL","reason":"AUTOTEST_RESULT.json missing"}' > "$RESULT"
fi
find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -type f -name '*BO2IOSCS*' -mmin -10 -exec cp {} Build/RuntimeLogs/ \; 2>/dev/null || true
echo "- AUTOTEST: $STATUS" >> "$REPORT"
echo "- Screenshot: Build/RuntimeLogs/simulator.png" >> "$REPORT"
echo "- Logs: Build/RuntimeLogs/application.log" >> "$REPORT"
echo "- Device IPA was not executed in Simulator; this validates only the simulator build." >> "$REPORT"
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
[ "$STATUS" = PASS ]
