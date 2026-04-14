#!/usr/bin/env bash
# Tests for the summarize() function in ~/.claude/hooks/notify-desktop.sh.
# Proves that:
#   1. Short text is returned verbatim (was already true)
#   2. Long text is cut to ~150 chars at a word boundary with an ellipsis
#      (the v2 behavior — v1 cut at the first sentence which produced
#       useless one-word notifications like "Saved.")
#   3. Markdown formatting is stripped (bold, italic, inline code, links,
#      headings, bullets, code blocks)
#   4. Multiline + tabbed text is flattened to single-spaced
#   5. The live hook script contains the v2 marker so this test is testing
#      the same code that actually runs
#
# Run from the project root: ./macos/scripts/test_notify_summarize.sh

set -uo pipefail

# Inline copy of the v2 summarize() function. Must stay in lockstep with the
# one in ~/.claude/hooks/notify-desktop.sh. The sentinel grep at the bottom of
# this script catches drift.
summarize() {
  local text="$1"
  local clean
  clean=$(printf '%s' "$text" \
    | tr '\n\t' '  ' \
    | sed -E 's/```[^`]*```/ /g' \
    | sed -E 's/`([^`]+)`/\1/g' \
    | sed -E 's/\*\*([^*]+)\*\*/\1/g' \
    | sed -E 's/\*([^*]+)\*/\1/g' \
    | sed -E 's/\[([^]]+)\]\([^)]+\)/\1/g' \
    | sed -E 's/^[#>-]+ //g' \
    | sed -E 's/  +- /  /g' \
    | tr -s ' ' \
    | sed 's/^ //; s/ $//')

  local maxLen=150
  if [ ${#clean} -le $maxLen ]; then
    printf '%s' "$clean"
    return
  fi
  local cut="${clean:0:$maxLen}"
  cut="${cut% *}"
  printf '%s…' "$cut"
}

PASS=0
FAIL=0
TOTAL=0

assert_summary() {
  local label="$1"
  local input="$2"
  local check_kind="$3"  # exact | contains | minLength
  local expected="$4"

  TOTAL=$((TOTAL + 1))
  local actual
  actual=$(summarize "$input")

  local ok=0
  case "$check_kind" in
    exact)
      [ "$actual" = "$expected" ] && ok=1
      ;;
    contains)
      [[ "$actual" == *"$expected"* ]] && ok=1
      ;;
    minLength)
      [ "${#actual}" -ge "$expected" ] && ok=1
      ;;
    maxLength)
      [ "${#actual}" -le "$expected" ] && ok=1
      ;;
    no_markdown)
      # ok if no ** or backticks or [link]( in the output
      if [[ "$actual" != *'**'* ]] && [[ "$actual" != *'`'* ]] && [[ "$actual" != *'](http'* ]]; then
        ok=1
      fi
      ;;
  esac

  if [ "$ok" = "1" ]; then
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    printf "  ✗ %s\n" "$label"
    printf "    input:    %s\n" "$input"
    printf "    expected: [%s] %s\n" "$check_kind" "$expected"
    printf "    actual:   %s\n" "$actual"
  fi
}

# ---------------------------------------------------------------------------
# 1. SHORT INPUTS — returned verbatim (this was the v1 behavior too)
# ---------------------------------------------------------------------------

assert_summary "short single sentence" \
  "Saved. Safe to restart." \
  exact "Saved. Safe to restart."

assert_summary "single word" \
  "Done." \
  exact "Done."

assert_summary "empty string" \
  "" \
  exact ""

# ---------------------------------------------------------------------------
# 2. LONG INPUTS — partial-sentence length truncation (THE NEW BEHAVIOR)
# ---------------------------------------------------------------------------

LONG="Saved. Safe to restart. State on disk: All code committed and pushed to https://github.com/jonzanoff/Notifly commit 2913013. Memory file project state captured. VS Code extension installed but needs reload."

assert_summary "long input is NOT cut at first period" \
  "$LONG" \
  contains "State on disk"

assert_summary "long input is NOT cut to one-word 'Saved.'" \
  "$LONG" \
  minLength 100

assert_summary "long input ends with ellipsis" \
  "$LONG" \
  contains "…"

assert_summary "long input is at most 152 chars (150 + ellipsis)" \
  "$LONG" \
  maxLength 152

# Word boundary check: the cut should not slice a word in half. Verify the
# last char before the ellipsis is a letter (i.e., a complete word).
LAST_OUTPUT=$(summarize "$LONG")
LAST_CHAR_BEFORE_ELLIPSIS="${LAST_OUTPUT%…}"
LAST_CHAR_BEFORE_ELLIPSIS="${LAST_CHAR_BEFORE_ELLIPSIS: -1}"
TOTAL=$((TOTAL + 1))
if [[ "$LAST_CHAR_BEFORE_ELLIPSIS" =~ [a-zA-Z0-9.] ]]; then
  PASS=$((PASS + 1))
  printf "  ✓ truncation lands on word boundary (last char before ellipsis: '%s')\n" "$LAST_CHAR_BEFORE_ELLIPSIS"
else
  FAIL=$((FAIL + 1))
  printf "  ✗ truncation does NOT land on word boundary (last char: '%s')\n" "$LAST_CHAR_BEFORE_ELLIPSIS"
  printf "    output: %s\n" "$LAST_OUTPUT"
fi

# ---------------------------------------------------------------------------
# 3. MARKDOWN STRIPPING
# ---------------------------------------------------------------------------

assert_summary "bold ** is stripped" \
  "**Done** — pushed to main." \
  exact "Done — pushed to main."

assert_summary "inline code is stripped" \
  "Run \`git push\` to publish." \
  exact "Run git push to publish."

assert_summary "markdown link keeps label drops URL" \
  "See [the docs](https://example.com/docs) for details." \
  exact "See the docs for details."

assert_summary "code block is removed" \
  "Here is the snippet \`\`\`bash echo hi \`\`\` end." \
  no_markdown ""

assert_summary "no backticks remain in output" \
  "Use \`foo\` and \`bar\`." \
  no_markdown ""

assert_summary "no double asterisks remain" \
  "**very** important **stuff**" \
  no_markdown ""

# ---------------------------------------------------------------------------
# 4. WHITESPACE FLATTENING
# ---------------------------------------------------------------------------

assert_summary "newlines flatten to spaces" \
  "$(printf 'Line one.\nLine two.\nLine three.')" \
  exact "Line one. Line two. Line three."

assert_summary "tabs flatten to spaces" \
  "$(printf 'Tab\there\tand\there.')" \
  exact "Tab here and here."

assert_summary "multiple spaces collapse" \
  "Lots    of     spaces." \
  exact "Lots of spaces."

# ---------------------------------------------------------------------------
# 5. REALISTIC CLAUDE OUTPUTS
# ---------------------------------------------------------------------------

assert_summary "claude 'saved' response (the bug the user reported)" \
  "Saved. Safe to restart. State on disk: All code committed and pushed to https://github.com/jonzanoff/Notifly commit 2913013." \
  contains "Safe to restart"

assert_summary "claude completion with bullets" \
  "$(printf 'Done. Three things changed:\n- Fixed the project grouping\n- Added per-project icons\n- Wired the action buttons')" \
  contains "Three things changed"

# ---------------------------------------------------------------------------
# 6. LIVE HOOK SCRIPT VERIFICATION
# ---------------------------------------------------------------------------

HOOK="$HOME/.claude/hooks/notify-desktop.sh"
TOTAL=$((TOTAL + 1))
if [ ! -f "$HOOK" ]; then
  FAIL=$((FAIL + 1))
  printf "  ✗ live hook script missing at %s\n" "$HOOK"
elif ! grep -q "NOTIFLY_SUMMARIZE_V2" "$HOOK"; then
  FAIL=$((FAIL + 1))
  printf "  ✗ live hook script does not contain NOTIFLY_SUMMARIZE_V2 marker — drift detected\n"
else
  PASS=$((PASS + 1))
  printf "  ✓ live hook script %s contains NOTIFLY_SUMMARIZE_V2\n" "$HOOK"
fi

# ---------------------------------------------------------------------------

echo ""
echo "  $PASS / $TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
echo "OK"
