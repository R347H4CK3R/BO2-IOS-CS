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
j=json.loads(subprocess.check_output(["xcrun","simctl","list","devices","available","-j"]))
devs=[d for _,xs in j["devices"].items() for d in xs if d.get("isAvailable") and d["name"].startswith("iPhone")]
for wanted in ("iPhone 16 Plus","iPhone 16 Pro Max"):
    for d in devs:
        if d["name"] == wanted:
            print(d["udid"]); raise SystemExit
for d in devs:
    if "Plus" in d["name"] or "Pro Max" in d["name"]:
        print(d["udid"]); raise SystemExit
if devs: print(devs[0]["udid"])
PY
)"
if [ -z "$UDID" ]; then
  echo "- Runtime validation: UNAVAILABLE" >> "$REPORT"
  echo '{"status":"UNAVAILABLE","reason":"no iPhone simulator"}' > "$RESULT"
  exit 0
fi
xcrun simctl shutdown all >/dev/null 2>&1 || true
xcrun simctl boot "$UDID" 2>/dev/null || true
if ! xcrun simctl bootstatus "$UDID" -b; then
  echo "- Runtime validation: UNAVAILABLE (boot failed)" >> "$REPORT"
  echo '{"status":"UNAVAILABLE","reason":"simulator boot failed"}' > "$RESULT"
  exit 0
fi
APP=Build/DerivedData/Build/Products/Debug-iphonesimulator/BO2IOSCS.app
BUNDLE=com.r347h4ck3r.BO2IOSCS
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE" AUTOTEST > Build/RuntimeLogs/launch.log 2>&1
sleep 13
xcrun simctl io "$UDID" screenshot Build/RuntimeLogs/simulator.png >/dev/null 2>&1 || true
xcrun simctl spawn "$UDID" log show --last 3m --style compact --predicate 'eventMessage CONTAINS "[BO2IOSCS]"' > Build/RuntimeLogs/application.log 2>&1 || true
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)"
if [ -n "$DATA" ] && [ -f "$DATA/Documents/Logs/AUTOTEST_RESULT.json" ]; then
  cp "$DATA/Documents/Logs/AUTOTEST_RESULT.json" "$RESULT"
  STATUS="$(python3 -c 'import json; print(json.load(open("AUTOTEST_RESULT.json")).get("status","FAIL"))')"
else
  STATUS=FAIL
  echo '{"status":"FAIL","reason":"AUTOTEST_RESULT.json missing"}' > "$RESULT"
fi
echo "- AUTOTEST: $STATUS" >> "$REPORT"
xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
[ "$STATUS" = PASS ]
