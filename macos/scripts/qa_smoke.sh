#!/usr/bin/env bash
# qa_smoke.sh — live IPC + screenshot integration test for Notifly.
#
# Runs on the QA Mac. Builds the app, launches it, fires one of each event
# type via the CLI, captures a screenshot of the live notification stack,
# verifies the process survived all IPC traffic, and cleans up.
#
# Usage:
#   ./macos/scripts/qa_smoke.sh [version]
#
# Outputs (relative to project root):
#   qa/screenshots/v<version>_notification-stack.png
#   qa/screenshots/v<version>_menu-bar.png
#   qa/screenshots/v<version>_after-active.png
#   qa/screenshots/v<version>_after-clear.png
#
# Exit codes:
#   0 — all checks passed
#   1 — build failed, IPC error, or process died

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="${1:-dev}"
SCREENSHOT_DIR="$PROJECT_ROOT/qa/screenshots"
LOG="/tmp/notifly_smoke.log"

red()   { printf "\033[31m%s\033[0m\n" "$*" >&2; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
blue()  { printf "\033[34m%s\033[0m\n" "$*"; }

fail() { red "FAIL: $*"; cleanup; exit 1; }

cleanup() {
  pkill -x Notifly 2>/dev/null || true
  rm -f "$HOME/Library/Application Support/Notifly/notifly.sock"
}

# 0. Pre-flight — keychain unlock for signing
if [[ "$(uname -s)" == "Darwin" ]]; then
  security unlock-keychain -p "anthropic" "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null || true
fi

# 1. Build
blue "[1/8] building Notifly v$VERSION on $(hostname)"
cd "$PROJECT_ROOT/macos"
xcodebuild -project Notifly.xcodeproj -scheme Notifly -configuration Debug \
           -destination "platform=macOS,arch=arm64" \
           -allowProvisioningUpdates build > /tmp/notifly_build.log 2>&1
if [ $? -ne 0 ]; then
  red "build output:"
  tail -40 /tmp/notifly_build.log
  fail "xcodebuild failed"
fi
green "      build OK"

# 2. Locate the .app bundle
APP=$(find "$HOME/Library/Developer/Xcode/DerivedData/Notifly-"* -name "Notifly.app" -type d 2>/dev/null | head -1)
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  fail "could not find Notifly.app in DerivedData"
fi
CLI="$APP/Contents/Resources/notifly"
if [ ! -x "$CLI" ]; then
  fail "CLI binary not embedded at $CLI"
fi
green "[2/8] app=$APP"

# 3. Clean any prior run + launch fresh
cleanup
"$APP/Contents/MacOS/Notifly" > "$LOG" 2>&1 &
PID=$!
sleep 1
if ! ps -p $PID > /dev/null; then
  red "launch log:"
  cat "$LOG"
  fail "Notifly died immediately on launch"
fi
green "[3/8] launched PID=$PID"

# 4. Send one of each event type. For Camp Clintondale and Notifly, also pass
# --icon if a per-project icon exists, so the screenshot exercises the icon
# loading path in NotificationCardView.
blue "[4/8] sending three test events via CLI"

NOTIFLY_ICON="$PROJECT_ROOT/.claude/icon.png"
CAMP_ICON="$HOME/Projects/Camp Clintondale/.claude/icon.png"
[ ! -f "$CAMP_ICON" ] && CAMP_ICON="/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/.claude/icon.png"

ICON_ARG=""
[ -f "$NOTIFLY_ICON" ] && ICON_ARG="--icon $NOTIFLY_ICON"

"$CLI" send --project "Dorothy" --event attention --message "Run supabase db push against production now? This will apply 3 pending migrations." || fail "CLI send (attention) failed"

if [ -f "$CAMP_ICON" ]; then
  "$CLI" send --project "Camp Clintondale" --event done --message "Pushed guest check-in rename to main. All 42 Playwright tests passed." --icon "$CAMP_ICON" || fail "CLI send (done) failed"
else
  "$CLI" send --project "Camp Clintondale" --event done --message "Pushed guest check-in rename to main. All 42 Playwright tests passed." || fail "CLI send (done) failed"
fi

if [ -f "$NOTIFLY_ICON" ]; then
  "$CLI" send --project "Notifly" --event stopped --message "Hit a snag in the IPC layer. Re-run after fixing." --icon "$NOTIFLY_ICON" || fail "CLI send (stopped) failed"
else
  "$CLI" send --project "Notifly" --event stopped --message "Hit a snag in the IPC layer. Re-run after fixing." || fail "CLI send (stopped) failed"
fi
sleep 1

if ! ps -p $PID > /dev/null; then
  red "log tail:"
  tail -20 "$LOG"
  fail "Notifly died after IPC traffic — REGRESSION FOR SIGPIPE INCIDENT"
fi
green "      process alive after 3 sends"

# 5. Capture screenshots
mkdir -p "$SCREENSHOT_DIR"

WIDTH=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null | awk -F', ' '{print $3}')
[ -z "$WIDTH" ] && WIDTH=2240

blue "[5/8] capturing screenshots (screen width=$WIDTH)"
osascript -e 'tell application "Finder" to activate' 2>/dev/null
sleep 1

screencapture -x -R $((WIDTH - 460)),28,460,520 "$SCREENSHOT_DIR/v${VERSION}_notification-stack.png"
screencapture -x -R $((WIDTH - 1200)),0,1200,50 "$SCREENSHOT_DIR/v${VERSION}_menu-bar.png"
green "      stack + menu-bar captured"

# 6. notifly active for one project — verify only that one disappears
blue "[6/8] testing notifly active --project Dorothy"
"$CLI" active --project "Dorothy" || fail "CLI active failed"
sleep 0.5
osascript -e 'tell application "Finder" to activate' 2>/dev/null
sleep 0.5
screencapture -x -R $((WIDTH - 460)),28,460,520 "$SCREENSHOT_DIR/v${VERSION}_after-active.png"
green "      after-active captured"

# 7. notifly clear — verify everything disappears
blue "[7/8] testing notifly clear"
"$CLI" clear || fail "CLI clear failed"
sleep 0.5
osascript -e 'tell application "Finder" to activate' 2>/dev/null
sleep 0.5
screencapture -x -R $((WIDTH - 460)),28,460,520 "$SCREENSHOT_DIR/v${VERSION}_after-clear.png"
green "      after-clear captured"

if ! ps -p $PID > /dev/null; then
  fail "Notifly died after clear traffic"
fi

# 8. Cleanup
blue "[8/8] cleanup"
cleanup
green "      QA Mac clean"

echo
green "✓ Notifly v$VERSION smoke test PASSED"
echo "  screenshots in $SCREENSHOT_DIR"
ls -la "$SCREENSHOT_DIR"/v${VERSION}_*.png 2>/dev/null | sed 's|^|  |'
