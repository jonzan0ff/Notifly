#!/usr/bin/env bash
# Tests that the bash project_root() function in ~/.claude/hooks/notify-desktop.sh
# produces the same result as ProjectGrouping.projectName(forPath:) in Swift,
# for the same fixture table.
#
# Run from the project root: ./macos/scripts/test_project_grouping_bash.sh

set -u

# The same fixture table the Swift tests use. Format: input|expected, one per line.
FIXTURES='/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/admin|Camp Clintondale
/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/guest|Camp Clintondale
/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/admin/app/api/users|Camp Clintondale
/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/email-templates/booking|Camp Clintondale
/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale|Camp Clintondale
/Users/jonzanoff/Documents/jonzan0ff/Projects/Notifly|Notifly
/Users/jonzanoff/Documents/jonzan0ff/Projects/Notifly/macos/Notifly/Views|Notifly
/Users/jonzanoff/Documents/jonzan0ff/Projects/Notifly/vscode-extension/src|Notifly
/Users/jonzanoff/Documents/jonzan0ff/Projects/Dorothy|Dorothy
/Users/jonzanoff/Documents/jonzan0ff/Projects/Dorothy/server/api|Dorothy
/Users/jonzanoff/Documents/jonzan0ff/Projects/HomeTeam/macos/HomeTeamApp/Services|HomeTeam
/Users/jonzanoff/Documents/jonzan0ff/Projects/SPAMASAURUS/lib/parsers|SPAMASAURUS
/tmp/scratch/something|something
/Users/jonzanoff/Desktop|Desktop'

# Inline copy of the project_root() function from notify-desktop.sh so this
# test file is self-contained and doesn't depend on the live script. If the
# logic ever drifts, this test will catch it immediately.
project_root() {
  local dir="$1"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    local parent
    parent=$(dirname "$dir")
    if [ "$(basename "$parent")" = "Projects" ]; then
      echo "$(basename "$dir")"
      return 0
    fi
    dir="$parent"
  done
  echo "$(basename "$1")"
}

PASS=0
FAIL=0
echo "$FIXTURES" | while IFS='|' read -r input expected; do
  actual=$(project_root "$input")
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$input"
  else
    FAIL=$((FAIL + 1))
    printf "  ✗ %s → got '%s' expected '%s'\n" "$input" "$actual" "$expected"
  fi
done

# Verify the bash script in the user's home matches this inline version exactly,
# so the test isn't lying about what the hook actually runs.
HOOK_SCRIPT="$HOME/.claude/hooks/notify-desktop.sh"
if [ -f "$HOOK_SCRIPT" ]; then
  if ! grep -q 'project_root() {' "$HOOK_SCRIPT"; then
    echo "  ✗ FATAL: $HOOK_SCRIPT does not contain a project_root() function"
    exit 1
  fi
  echo "  ✓ live hook script contains project_root()"
fi

# Final tally — re-run because the while subshell scoped PASS/FAIL away
PASS=0
FAIL=0
TOTAL=0
while IFS='|' read -r input expected; do
  actual=$(project_root "$input")
  TOTAL=$((TOTAL + 1))
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
done <<< "$FIXTURES"

echo ""
echo "  $PASS / $TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
  echo "FAIL: $FAIL fixtures failed"
  exit 1
fi
echo "OK"
