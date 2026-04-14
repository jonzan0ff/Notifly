# QA Plan: Notifly

> Implements the strategy defined in the QA Master Standards (`~/.claude/rules/qa-standards.md`). This file contains Notifly-specific test layers, fixtures, and engineering rules.

> Goal: eliminate UAT guesswork. Every behavior that can be asserted in code should be. Manual UAT only covers what automation structurally cannot reach (visual pixel polish, the actual menu bar interaction, real Claude Code hook integration).

---

## Execution environment

All tests, builds, and screenshots run on the **QA Mac** (`qa@iMac.local`) via SSH. See `~/.claude/rules/qa-mac.md` for the sync/build pattern. **Never run tests on the dev machine** — it interrupts the user's work, and Notifly draws floating notification windows on the active screen.

The dev machine is for compile-checking only (`xcodebuild build`). Execution, smoke tests, and screenshot capture happen exclusively on the QA Mac.

---

## What's different about Notifly's test surface

Notifly is **simpler** than HomeTeam, Print Status, or What to Watch:

- No widget extension → no App Group, no WidgetKit OS integration, no provisioning gymnastics.
- No external API → no network smoke tests, no rate limits, no schema drift.
- No settings UI → no onboarding flows, no preferences persistence.

Notifly is **harder** in two specific ways:

1. **Floating window UI** — the notification stack is an `NSWindow` at `.statusBar` level, not a regular app window. XCUITest can't easily reach it. Test via screenshot capture + visual diff.
2. **Local IPC** — Unix domain socket between the `notifly` CLI, the VS Code extension, and the app process. Test via real socket round-trips, not mocks.

---

## Test pyramid

```
         ┌──────────────────────────────┐
         │   UAT (human, ~3 min)        │  ← menu bar feel, real Claude hook integration
         ├──────────────────────────────┤
         │   Live IPC + screenshot test │  ← real CLI → real socket → real card render
         │   (QA Mac, integration)      │     scripts/qa_smoke.sh
         ├──────────────────────────────┤
         │   Card snapshot tests        │  ← NotificationCardView via NSHostingView
         │   (QA Mac)                   │     pixel-comparison against baselines
         ├──────────────────────────────┤
         │   Unit tests (no IO)         │  ← models, manager, IPC parsing,
         │   (QA Mac)                   │     version compare, icon hashing
         └──────────────────────────────┘
```

---

## Layer 1 — Unit tests (no IO, no UI, instant)

Run on QA Mac via `xcodebuild test -only-testing NotiflyTests`.

### 1A. NotiflyEvent model

| Test | Asserts |
|---|---|
| `init_short_message_unchanged` | Message under 240 chars passes through verbatim |
| `init_long_message_truncated_with_ellipsis` | 500-char message → 240 chars ending in `…` |
| `init_whitespace_trimmed` | Leading/trailing whitespace stripped |
| `init_assigns_unique_id` | Two events with identical content have distinct IDs |
| `init_receivedAt_is_now` | `receivedAt` within 1s of `Date()` |
| `equatable_compares_all_fields` | Two events with same id+project+type+message+date are equal |

### 1B. NotificationStackManager

Tests for the in-memory event store. Manager runs on the main actor; tests use `XCTestExpectation` to wait for `DispatchQueue.main.async` blocks.

| Test | Asserts |
|---|---|
| `submit_adds_event_to_stack` | After submit, `events.count == 1` |
| `submit_inserts_newest_first` | Three submits → newest at index 0 |
| `submit_replaces_existing_for_same_project` | Two submits for "Dorothy" → only one remains, the second |
| `submit_keeps_other_projects` | Submit Dorothy then Camp → both remain |
| `clearProject_removes_only_matching` | After `clearProject("Dorothy")` only non-Dorothy remain |
| `clearProject_unknown_is_noop` | Clearing a project with no events leaves stack unchanged |
| `clearAll_empties_stack` | After `clearAll()` count is zero |
| `dismiss_removes_specific_event_by_id` | `dismiss(event)` removes only that event |

### 1C. ProjectIconView initials and color hashing

Tests for the deterministic project → initials and project → color logic in `NotificationCardView.swift`.

| Input project | Expected initials |
|---|---|
| `"Dorothy"` | `"DO"` |
| `"Camp Clintondale"` | `"CC"` |
| `"SPAMASAURUS"` | `"SP"` |
| `"What to Watch"` | `"WW"` |
| `"a"` | `"A"` |
| `"  "` | `""` |
| `"123"` | `"12"` |

| Test | Asserts |
|---|---|
| `colorHash_isDeterministic` | Same name → same gradient pair across calls |
| `colorHash_differentNamesProduceDifferentColors` | "Dorothy" and "SPAMASAURUS" hash to different palette indices (statistically; assert not equal for the known fixtures) |

### 1D. IPC message decoding

Tests for `IPCMessage` JSON decoding and `IPCServer.handle` dispatch.

| Test | Asserts |
|---|---|
| `decode_send_with_all_fields` | Round-trip JSON → `IPCMessage` with project/event/message |
| `decode_active_with_project` | `{"type":"active","project":"Dorothy"}` decodes |
| `decode_clear` | `{"type":"clear"}` decodes with nil project |
| `decode_unknown_type_still_decodes` | Unknown type string decodes (validation happens later in `handle`) |
| `decode_missing_type_throws` | Missing `type` key throws |
| `handle_send_with_missing_project_throws` | Throws `IPCError.badRequest` |
| `handle_send_with_invalid_event_throws` | `event: "exploded"` throws |
| `handle_active_with_empty_project_throws` | Empty string project throws |

### 1E. Project grouping (cross-implementation contract)

Three implementations must produce identical results for the same fixture table:
- **Swift** `ProjectGrouping.projectName(forPath:)` → `NotiflyTests/ProjectGroupingTests`
- **Bash** `project_root()` in `~/.claude/hooks/notify-desktop.sh` → `macos/scripts/test_project_grouping_bash.sh`
- **TypeScript** `projectRootForPath()` in `vscode-extension/src/extension.ts` → `vscode-extension/test/projectGrouping.test.js`

If you add a fixture row to one, you MUST add it to all three. The test scripts each ALSO grep the live source files to verify the function exists and hasn't drifted from the inline test copy.

| Input path | Expected project |
|---|---|
| `Camp Clintondale/admin` | `Camp Clintondale` |
| `Camp Clintondale/guest` | `Camp Clintondale` |
| `Camp Clintondale/admin/app/api/users` | `Camp Clintondale` |
| `Camp Clintondale/email-templates/booking` | `Camp Clintondale` |
| `Notifly/macos/Notifly/Views` | `Notifly` |
| `Dorothy/server/api` | `Dorothy` |
| `HomeTeam/macos/HomeTeamApp/Services` | `HomeTeam` |
| `/tmp/scratch/something` | `something` (fallback) |

This proves Camp Clintondale's guest/admin sub-repos always collapse to a single notification stack entry — never two competing ones.

### 1F. Per-project icon loading

`NotiflyEventIconTests` proves that:
- An `iconPath` provided at event construction round-trips through the model
- A real PNG file at the path loads as a non-nil `NSImage` with the expected dimensions
- A missing path returns nil from the loader (no crash)
- The `iconPath` field round-trips through `IPCMessage` JSON encoding
- The real per-project icons at `Camp Clintondale/.claude/icon.png` and `Notifly/.claude/icon.png` exist on disk and load (skipped on machines that don't have them)

This proves that when the hook script passes `--icon /path/to/icon.png`, the path makes it all the way to `NSImage(contentsOfFile:)` and produces a real image.

### 1G. Card action wiring

`CardActionTests` proves that:
- The dismiss callback wired through `NotificationStackView.handleDismiss` actually removes the event from the manager
- The click callback (which dismisses the card and focuses VS Code) actually clears the card from the manager
- Dismissing one card leaves all other cards untouched
- The card view holds at least two closure-typed properties (smoke test against future regressions where someone hard-codes an action)

This proves the action buttons are wired to real state changes — addressing the user's complaint "the action buttons don't do anything". The follow-up integration test (Layer 3) proves the SwiftUI buttons actually receive clicks through the `NSPanel` host.

### 1H. Notify-desktop summarize() function

The bash hook in `~/.claude/hooks/notify-desktop.sh` runs `summarize()` on every Claude assistant message before passing it as the `--message` arg to `notifly send`. The v2 implementation is partial-sentence length with word-boundary truncation — v1 cut at the first sentence boundary, which produced useless one-word notifications like "Saved." when the assistant response started with a short opener.

`macos/scripts/test_notify_summarize.sh` covers:

| Test | Asserts |
|---|---|
| `short single sentence` | "Saved. Safe to restart." passes through verbatim |
| `single word` | "Done." passes through verbatim |
| `empty string` | "" passes through |
| `long input not cut at first period` | A 200-char input containing "State on disk" still includes that phrase |
| `long input not cut to one-word 'Saved.'` | Output is at least 100 chars |
| `long input ends with ellipsis` | Truncated output ends with `…` |
| `long input ≤ 152 chars` | 150 + ellipsis cap |
| `truncation lands on word boundary` | Last char before ellipsis is alphanumeric |
| `bold ** stripped` | `**Done**` → `Done` |
| `inline code stripped` | `` `git push` `` → `git push` |
| `markdown link strips URL keeps label` | `[docs](url)` → `docs` |
| `code block removed` | ` ```bash echo hi``` ` produces no backticks in output |
| `newlines flatten to spaces` | Multi-line input becomes single-spaced |
| `tabs flatten to spaces` | Tab-separated text becomes single-spaced |
| `multiple spaces collapse` | `"a    b"` → `"a b"` |
| `live hook contains NOTIFLY_SUMMARIZE_V2` | Sentinel grep against `~/.claude/hooks/notify-desktop.sh` proves the test isn't testing a stale copy |

The sentinel marker is the v2 contract — if anyone edits the live hook and removes the marker (or downgrades to a v1 implementation), this test fails immediately.

### 1I. UpdateService version comparison

| local | remote | isNewer |
|---|---|---|
| `0.1.0` | `0.1.1` | true |
| `0.1.0` | `0.2.0` | true |
| `0.1.0` | `1.0.0` | true |
| `0.1.0` | `0.1.0` | false |
| `0.2.0` | `0.1.9` | false |
| `0.10.0` | `0.9.0` | false |
| `0.1.0` | `0.1.0.1` | true (4-segment > 3-segment) |
| `1.0` | `1.0.0` | false |

---

## Layer 2 — Snapshot tests (no IO, visual regression)

Render `NotificationCardView` via `NSHostingView` → `bitmapImageRepForCachingDisplay` → PNG, compare to committed baseline.

Reference PNGs live in `qa/baselines/cards/`. Toggle `recordMode` in `CardSnapshotTests.swift` to re-record after intentional visual changes.

**Baselines must be recorded on the QA Mac.** Font hinting and SwiftUI rendering can differ between machines. If baselines were ever recorded on the dev machine, re-record them on the QA Mac.

### 2A. Card scenarios (per event type, plus edge cases)

| Fixture | Event | Project | Notes |
|---|---|---|---|
| `card_done_short` | done | "Dorothy" | One-line message, green pill |
| `card_done_long` | done | "Camp Clintondale" | 240-char message, 3-line truncation |
| `card_attention_short` | attention | "SPAMASAURUS" | Orange pill + outer glow |
| `card_attention_with_question` | attention | "What to Watch" | Question with backtick `code` |
| `card_stopped_short` | stopped | "HomeTeam" | Red pill |
| `card_long_project_name` | done | "A Very Long Project Name That Should Truncate" | Title ellipsis |
| `card_two_letter_project` | done | "X" | Single-letter initial |
| `card_unicode_project` | done | "café" | Unicode initials |

---

## Layer 3 — Live IPC + screenshot test (integration, on QA Mac)

The single most important test for Notifly. Exercises the entire stack: real CLI → real Unix socket → real app process → real `NSWindow` → real screenshot.

Lives in `macos/scripts/qa_smoke.sh`. Run before every build via the agent.

```bash
# 1. Kill any running Notifly + clear socket
pkill -x Notifly; rm -f ~/Library/Application\ Support/Notifly/notifly.sock

# 2. Launch the DerivedData build
"$APP/Contents/MacOS/Notifly" > /tmp/notifly_smoke.log 2>&1 &

# 3. Send one of each event type
"$APP/Contents/Resources/notifly" send --project "Dorothy" --event attention --message "..."
"$APP/Contents/Resources/notifly" send --project "Camp Clintondale" --event done --message "..."
"$APP/Contents/Resources/notifly" send --project "SPAMASAURUS" --event stopped --message "..."

# 4. Activate Finder (otherwise menu bar icons render dimmed)
osascript -e 'tell application "Finder" to activate'

# 5. Capture screenshot of the card region
WIDTH=$(... screen width ...)
screencapture -x -R $((WIDTH - 460)),28,460,500 qa/screenshots/v<VER>_notification-stack.png

# 6. Capture menu bar region
screencapture -x -R $((WIDTH - 1200)),0,1200,50 qa/screenshots/v<VER>_menu-bar.png

# 7. Send notifly active to clear one project
"$APP/Contents/Resources/notifly" active --project "Dorothy"
sleep 0.5
screencapture -x -R $((WIDTH - 460)),28,460,500 qa/screenshots/v<VER>_after-active.png

# 8. Send notifly clear
"$APP/Contents/Resources/notifly" clear

# 9. Verify process still alive (regression for SIGPIPE incident)
ps -p $PID > /dev/null || fail "process died after IPC traffic"

# 10. Cleanup
pkill -x Notifly; rm -f ~/Library/Application\ Support/Notifly/notifly.sock
```

### Test cases covered by this script

| Case | Asserts |
|---|---|
| Single attention card renders | top-right card visible after send |
| Stack of 3 cards renders | three cards stacked, newest on top |
| `notifly active --project X` clears X | only X removed, others remain |
| `notifly clear` empties stack | no cards visible after clear |
| Process survives N IPC round-trips | regression for SIGPIPE — process alive after all sends |
| Menu bar icon visible | bell icon present in right-side menu bar capture |
| Update dot when applicable | when `availableUpdate` is set, orange dot present |

### Screenshot description discipline

Per `~/.claude/rules/agent-behavior.md`, after every screenshot capture, the agent must describe in specific detail what is visible: card count, project names, pill colors, icon colors, text content, hover states. Generic claims like "looks correct" are a failed QA check.

---

## Layer 3B — Auto-clear-on-typing (live IPC, on QA Mac)

The other "PROVE it works" integration test. Lives in `macos/scripts/test_auto_clear.sh`. Builds, launches the app, sends three test cards, then writes the same JSON the VS Code extension would write (`{"type":"active","project":"Camp Clintondale"}`) directly to the Unix socket via Python, and verifies via screenshot that exactly the targeted card disappears while the other two remain.

This bypasses the requirement of having a real VS Code window open during the test, but exercises the **same code path** — the IPC message format, the IPCServer dispatch, the `NotificationStackManager.clearProject` flow, and the SwiftUI re-render. If a regression breaks any of those, this test fails.

The test ALSO verifies the process survives the active message (regression for the SIGPIPE incident) and that the screenshot shows the expected delta — Camp Clintondale gone, Dorothy + SPAMASAURUS still visible.

The companion XCUITest for the actual SwiftUI button click event-routing through the `NSPanel` host is tracked as a future test layer; for v0.1.0 the unit-level button-callback contract (Layer 1G) plus this active-message round-trip provide enough proof.

---

## Layer 4 — VS Code extension end-to-end test (automated)

Lives at `vscode-extension/test/integration/`. Uses `@vscode/test-electron` to download an isolated VS Code, load the Notifly extension at dev-path, and run a Mocha suite that fires **real in-editor edits** via `TextEditor.edit()`. A mock Unix socket server runs inside the test process at a temp path (via `NOTIFLY_SOCKET_PATH` env var override) so the test doesn't interfere with the running Notifly app.

**Run:** `cd vscode-extension && npm run test:integration` (needs `node` — install to QA Mac via the direct tarball method, not Homebrew).

### Tests

| Test | Asserts |
|---|---|
| `extension is activated after VS Code launch` | `vscode.extensions.getExtension("notiflyz.notifly-vscode").isActive` is true after `onStartupFinished` |
| `editing a file fires an active ping with the right project name` | `editor.edit()` on a file at `.../Projects/TestProject/hello.txt` produces exactly one `{"type":"active","project":"TestProject"}` message on the mock socket within the debounce window |
| `a second edit within debounce is suppressed, a later edit goes through` | Rapid follow-up edit produces no additional message; an edit past the 500ms debounce produces one |

This is the **only** test that actually proves the full auto-clear chain end-to-end. The earlier `test_auto_clear.sh` script exercised the IPC **server** side but simulated the extension by writing bytes directly to the socket — it did not prove the extension itself fires on typing. Layer 4 is that proof.

### Rule

**Never claim a user-facing interaction works end-to-end without a test in this layer.** A contract test on a wire format is not an end-to-end test. If you add a new IPC message or a new VS Code event handler, add a test here that runs the real handler inside a real VS Code instance.

---

## Engineering rules (QA-driven)

1. **All tests run on QA Mac** — never run XCTest, screenshot capture, or end-to-end flows on the dev machine. Sync via rsync, build and test via SSH.
2. **SIGPIPE must be ignored at startup** — `signal(SIGPIPE, SIG_IGN)` in `IPCServer.start()` and at the top of the `notifly` CLI's `send()`. A process that writes to a closed-peer socket dies otherwise. (Logged as an incident on 2026-04-13.)
3. **Distinct Xcode target names** — never give two targets in the same project names that differ only in case. APFS is case-insensitive; intermediates collide. Use `PRODUCT_NAME` to control the on-disk binary name. (Logged as an incident on 2026-04-13.)
4. **All NSWindow / SwiftUI mutations on main thread** — IPC handlers run on a background dispatch queue, but `NotificationStackManager.submit/clearProject/clearAll/dismiss` always dispatch their state changes onto `DispatchQueue.main`.
5. **Deterministic icon coloring** — `ProjectIconView.gradientColors` must produce the same color pair for the same project name across runs. This is observable in screenshots and any change is a visual regression.
6. **Message truncation at 240 chars** — long messages are truncated in the model, not the view, so the test surface is the same as the runtime surface.
7. **One stack entry per project** — submitting a new event for an existing project must replace the old one, not stack on top of it. The product is "calm."
8. **Pre-build smoke test is mandatory** — run `scripts/qa_smoke.sh` before every release. Catches regressions in the IPC server (SIGPIPE, JSON parsing, threading) and in the SwiftUI render path simultaneously.
9. **Baselines belong to QA Mac** — committed baseline PNGs in `qa/baselines/` must be generated on the QA Mac, not the dev machine.
10. **Non-sandboxed app, on purpose** — Notifly is `com.apple.security.app-sandbox: false` (empty entitlements). It needs to write to a Unix socket outside its container and launch other processes (the CLI). Do not enable sandboxing without rethinking the IPC story.

---

## What NOT to automate (leave for UAT)

| Item | Why |
|---|---|
| Menu bar icon click feel | Subjective; AppKit `NSStatusItem` interaction not easily scriptable |
| Real Claude Code hook integration | Requires a real Claude Code session firing real events; out of scope for unit/integration |
| VS Code extension auto-clear under real typing | Requires a real VS Code window with the extension installed and a human typing |
| Notification dim mode (under another window) | macOS `NSWindow` at `.statusBar` level doesn't dim like widgets; verify visually |
| Multi-display behavior | The window pins to `NSScreen.main`; verify on a multi-monitor setup as part of UAT |

---

## UAT checklist — minimum per handoff

### App
- [ ] Launch fresh → menu bar shows monochrome bell icon
- [ ] Click bell → menu shows "Notifly v0.1.0", "Check for Updates…", "Quit Notifly"
- [ ] No window appears (background-only app)
- [ ] No dock icon (LSUIElement)

### CLI
- [ ] `notifly send --project "X" --event done --message "test"` returns 0 immediately
- [ ] If the app isn't running, the CLI launches it silently and the message still arrives
- [ ] `notifly send` for three different projects produces a stack of 3 cards
- [ ] `notifly send` for the same project replaces (not stacks) the existing card
- [ ] `notifly active --project "X"` removes X's card, leaves others
- [ ] `notifly clear` empties the stack
- [ ] Bad arguments print usage and exit non-zero

### Cards
- [ ] Each event type has the correct accent color (green/orange/red)
- [ ] Attention card has a subtle outer glow
- [ ] Long messages are truncated to 3 lines with ellipsis
- [ ] Hovering a card reveals the action buttons (focus, copy, dismiss)
- [ ] Clicking a card brings the matching VS Code window forward
- [ ] Cards survive 60+ seconds of inactivity

### Auto-update
- [ ] On launch, `AppState.shared.checkForUpdate()` is invoked
- [ ] When `availableUpdate != nil`, the menu bar icon shows an orange dot
- [ ] When `availableUpdate != nil`, the menu shows "Install Update" instead of "Check for Updates…"
- [ ] Clicking "Install Update" downloads, replaces `/Applications/Notifly.app`, and relaunches *(verify after first real release)*

### VS Code extension
- [ ] Install the `.vsix` (or symlink for dev) into VS Code
- [ ] Open a workspace, fire a notifly send for that workspace's folder name → card appears
- [ ] Type in any file in that workspace → card auto-clears within 500ms
- [ ] Type in a different workspace → that workspace's card unaffected

---

## CI pipeline

```
Every build (agent runs on QA Mac via SSH):
  1. rsync project to QA Mac
  2. xcodebuild -scheme Notifly build                        ← compile + asset catalog
  3. xcodebuild test -only-testing NotiflyTests              ← unit tests
  4. xcodebuild test -only-testing NotiflyTests/CardSnapshotTests  ← snapshot tests
  5. macos/scripts/qa_smoke.sh                                ← live IPC + screenshot
  6. Commit any updated qa/screenshots/v*.png

Pre-release:
  7. UAT checklist (human, ~3 min on the dev machine via DerivedData handoff)
```
