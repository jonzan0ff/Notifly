#!/bin/bash
#
# qa_engagement_e2e.sh — REAL end-to-end engagement test for Notifly.
#
# Runs on the QA Mac. Launches the real Notifly app, the real VS Code with
# the real installed Notifly extension, and the real Claude Code extension.
# Drives a scripted scenario remotely (ssh qa@iMac.local) and asserts PASS/FAIL by parsing
# the Notifly app's NSLog output for "[NotificationStackManager] suppressing
# card" lines.
#
# Cases tested (each is a deliberate regression target for a specific bug):
#
#   A. CODING SAFETY (regression for the v0.1.5 ship-bug):
#      VS Code window focused + a NON-Claude file is the active tab + a
#      Notifly card is sent. The card MUST appear (must NOT be suppressed).
#      Editing source files is normal coding work and must never silence
#      Stop-event notifications.
#
#   B. CLAUDE ENGAGEMENT (the actual user requirement):
#      VS Code window focused + the Claude Code webview is the active tab
#      + heartbeat has had time to fire + a Notifly card is sent. The card
#      MUST be suppressed (must NOT appear).
#
#   C. BASELINE:
#      VS Code is hidden, Finder frontmost, a Notifly card is sent. The
#      card MUST appear regardless of any prior suppression state.
#
# Exit code: 0 if all three cases pass, 1 if any fails. Suitable for CI.

set -uo pipefail

QA=qa@iMac.local
WORKSPACE=/Users/qa/Projects/Notifly
APP=/Users/qa/Library/Developer/Xcode/DerivedData/Notifly-hdppmqzbzeigamawsmntqaigboim/Build/Products/Debug/Notifly.app
CLI=$APP/Contents/Resources/notifly
SOCKET='/Users/qa/Library/Application Support/Notifly/notifly.sock'
APP_LOG=/tmp/notifly-engagement-e2e.log
EXT_LOG=/tmp/notifly-vscode-extension.log
SOURCE_FILE='/Users/qa/Projects/Notifly/vscode-extension/src/extension.ts'

PASS_COUNT=0
FAIL_COUNT=0

green() { printf '\033[1;32m%s\033[0m' "$1"; }
red()   { printf '\033[1;31m%s\033[0m' "$1"; }
blue()  { printf '\033[1;34m%s\033[0m' "$1"; }
say()   { printf '%s %s\n' "$(blue "[e2e]")" "$*"; }

# Mark a case PASS or FAIL with a one-line evidence string and bump counters.
record() {
  local name="$1" outcome="$2" evidence="$3"
  if [ "$outcome" = "PASS" ]; then
    printf '  %s  %s — %s\n' "$(green PASS)" "$name" "$evidence"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf '  %s  %s — %s\n' "$(red FAIL)" "$name" "$evidence"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# Look up whether a specific Notifly card (identified by its unique message
# string) was suppressed by the server. Suppression happens synchronously on
# the same dispatch queue as IPC handling, so the "suppressing card" log line
# appears immediately after the matching "rx ... \"message\":\"<msg>\"" line.
#
# Echoes "SUPPRESSED" or "NOT_SUPPRESSED" or "MISSING".
check_suppressed() {
  local logfile="$1"
  local unique_message="$2"
  awk -v msg="$unique_message" '
    /\[IPCServer\] rx/ && index($0, "\"message\":\"" msg "\"") {
      saw = 1
      next
    }
    saw && /suppressing card for/ { print "SUPPRESSED"; printed = 1; exit }
    saw && /\[IPCServer\] rx/ { print "NOT_SUPPRESSED"; printed = 1; exit }
    END {
      if (!printed) {
        if (saw) print "NOT_SUPPRESSED"
        else print "MISSING"
      }
    }
  ' "$logfile"
}

ssh qa@iMac.local 'security unlock-keychain -p anthropic ~/Library/Keychains/login.keychain-db' >/dev/null || {
  red "FAIL"; printf ' could not unlock QA keychain\n'; exit 1
}

say "clean slate"
ssh qa@iMac.local 'osascript -e "tell application \"Visual Studio Code\" to quit"' 2>/dev/null || true
sleep 1
ssh qa@iMac.local 'pkill -9 -f "Visual Studio Code"' 2>/dev/null || true
ssh qa@iMac.local 'pkill -9 -f "Code Helper"' 2>/dev/null || true
ssh qa@iMac.local 'pkill -9 -x Notifly' 2>/dev/null || true
ssh qa@iMac.local "rm -f $APP_LOG $EXT_LOG '$SOCKET' /tmp/case-*.png"
sleep 2

say "build Notifly fresh"
ssh qa@iMac.local "cd /Users/qa/Projects/Notifly/macos && PATH=\$HOME/bin:\$PATH xcodebuild -project Notifly.xcodeproj -scheme Notifly -configuration Debug -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates build 2>&1 | tail -3"

say "launch Notifly with NSLog → file"
ssh qa@iMac.local "nohup $APP/Contents/MacOS/Notifly > $APP_LOG 2>&1 &"
sleep 3
ssh qa@iMac.local "test -S '$SOCKET'" || { echo "FAIL: notifly never created socket"; exit 1; }

say "launch VS Code on workspace"
ssh qa@iMac.local "open -na 'Visual Studio Code' --args '$WORKSPACE'"
sleep 8
ssh qa@iMac.local 'osascript -e "tell application \"Visual Studio Code\" to activate"' 2>/dev/null || true
sleep 2

# =========================================================================
say "$(blue 'CASE A — coding safety: source file focused, NO Claude tab')"
# Open the source file so the active tab is a regular .ts file. Do NOT open
# Claude Code at all — we want a clean state where the only active tab is
# the source file.
ssh qa@iMac.local "open -a 'Visual Studio Code' '$SOURCE_FILE'"
sleep 4
ssh qa@iMac.local 'osascript -e "tell application \"Visual Studio Code\" to activate"' 2>/dev/null || true
sleep 2

# Type into the file (a real edit). The fixed extension must NOT fire any
# active ping in response — file editing is no longer an engagement signal.
ssh qa@iMac.local 'osascript -e "tell application \"System Events\" to keystroke \"// e2e probe\""' 2>/dev/null || true
sleep 2

# Send the card. Mark a "since" epoch right before so we only count any
# suppression lines that fire as a result of THIS send.
SINCE_A=$(date +%s)
ssh qa@iMac.local "$CLI send --project Notifly --event done --message 'A: coding safety'"
sleep 2

scp "qa@iMac.local:$APP_LOG" "$APP_LOG" 2>/dev/null
STATE_A=$(check_suppressed "$APP_LOG" "A: coding safety")

ssh qa@iMac.local 'osascript -e "tell application \"Finder\" to activate"' 2>/dev/null || true
sleep 1
ssh qa@iMac.local 'screencapture -x -R 900,0,1000,500 /tmp/case-A.png' 2>/dev/null
scp qa@iMac.local:/tmp/case-A.png /tmp/case-A.png 2>/dev/null

case "$STATE_A" in
  NOT_SUPPRESSED) record "A coding safety" PASS "card received and NOT suppressed (correct)" ;;
  SUPPRESSED)     record "A coding safety" FAIL "card was suppressed — file editing must NOT silence cards" ;;
  MISSING)        record "A coding safety" FAIL "card was never received by Notifly app" ;;
esac

# Settle and continue.
ssh qa@iMac.local 'osascript -e "tell application \"Visual Studio Code\" to activate"' 2>/dev/null || true
sleep 2

# =========================================================================
say "$(blue 'CASE B — Claude engagement: Claude tab focused, heartbeat firing')"
# Open the Claude Code webview as a tab. After the open, the Claude tab is
# the active tab in its tab group, so the new extension's window-focus and
# heartbeat signals should both fire pingIfEngaged → sendActive("Notifly").
ssh qa@iMac.local 'osascript -e "tell application \"Visual Studio Code\" to activate" -e "delay 0.3" -e "tell application \"System Events\" to keystroke \"p\" using {command down, shift down}" -e "delay 0.4" -e "tell application \"System Events\" to keystroke \"Claude Code: Open in New Tab\"" -e "delay 0.4" -e "tell application \"System Events\" to key code 36"' 2>/dev/null || true
sleep 6  # let the heartbeat fire at least twice

# Now send a card. With heartbeat keeping the suppression window fresh,
# this MUST be suppressed.
SINCE_B=$(date +%s)
ssh qa@iMac.local "$CLI send --project Notifly --event done --message 'B: claude engaged'"
sleep 2

scp "qa@iMac.local:$APP_LOG" "$APP_LOG" 2>/dev/null
STATE_B=$(check_suppressed "$APP_LOG" "B: claude engaged")

ssh qa@iMac.local 'osascript -e "tell application \"Finder\" to activate"' 2>/dev/null || true
sleep 1
ssh qa@iMac.local 'screencapture -x -R 900,0,1000,500 /tmp/case-B.png' 2>/dev/null
scp qa@iMac.local:/tmp/case-B.png /tmp/case-B.png 2>/dev/null

case "$STATE_B" in
  SUPPRESSED)     record "B claude engaged" PASS "card was correctly suppressed (heartbeat in window)" ;;
  NOT_SUPPRESSED) record "B claude engaged" FAIL "card was NOT suppressed — extension is not firing engagement pings" ;;
  MISSING)        record "B claude engaged" FAIL "card was never received by Notifly app" ;;
esac

# =========================================================================
say "$(blue 'CASE C — baseline: VS Code hidden, Finder frontmost')"
ssh qa@iMac.local 'osascript -e "tell application \"System Events\" to set visible of process \"Code\" to false"' 2>/dev/null || true
sleep 6  # drain the suppression window

SINCE_C=$(date +%s)
ssh qa@iMac.local "$CLI send --project Notifly --event done --message 'C: baseline'"
sleep 2

scp "qa@iMac.local:$APP_LOG" "$APP_LOG" 2>/dev/null
STATE_C=$(check_suppressed "$APP_LOG" "C: baseline")

ssh qa@iMac.local 'screencapture -x -R 900,0,1000,500 /tmp/case-C.png' 2>/dev/null
scp qa@iMac.local:/tmp/case-C.png /tmp/case-C.png 2>/dev/null

case "$STATE_C" in
  NOT_SUPPRESSED) record "C baseline" PASS "card received and NOT suppressed (correct)" ;;
  SUPPRESSED)     record "C baseline" FAIL "card suppressed in baseline state — suppression window leaked" ;;
  MISSING)        record "C baseline" FAIL "card never received" ;;
esac

# =========================================================================
say "teardown"
ssh qa@iMac.local 'osascript -e "tell application \"Visual Studio Code\" to quit"' 2>/dev/null || true
ssh qa@iMac.local 'pkill -9 -x Notifly' 2>/dev/null || true
ssh qa@iMac.local 'pkill -9 -f "Visual Studio Code"' 2>/dev/null || true

echo
say "result: $(green "$PASS_COUNT pass") / $(red "$FAIL_COUNT fail")"
echo "  app log:      $APP_LOG"
echo "  screenshots:  /tmp/case-A.png /tmp/case-B.png /tmp/case-C.png"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
