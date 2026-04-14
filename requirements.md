# Requirements: NOTIFLY

## Purpose

A smarter desktop notification system for Claude Code sessions, per project.

When Claude finishes a turn, asks a question, or stops unexpectedly, Notifly shows a desktop notification titled with the project name. The notification stays visible until dismissed — or clears automatically the moment the user starts typing in that project's VS Code window.

Replaces the current `terminal-notifier` + shell script setup.

## Problem with the current setup

* Notifications are attributed to "terminal-notifier" — there is no single named sender.
* Nothing clears notifications when the user resumes work. They accumulate on screen or auto-dismiss on a timer.
* No per-project customization (sound, enabled events, auto-clear behavior).
* No way to tell which project a notification came from except by reading the title.

## Core Behavior

### Notifications

* Title: the project folder name (e.g., `Dorothy`, `Camp Clintondale`).
* Body: a short, summarized message (≤ 120 characters). Long assistant replies get truncated to the first sentence.
* Sender: "Notifly" (a real named app, not Script Editor or terminal-notifier).
* Sticky: notifications stay on screen until dismissed, ignored, or cleared by activity.
* Grouped by project: a new Dorothy notification replaces the previous Dorothy notification. Camp Clintondale and Dorothy notifications can coexist.

### Events that trigger a notification

1. **Claude is done** — end of a normal turn. Body is a short summary of Claude's final message.
2. **Claude needs attention** — Claude is waiting on the user (permission prompt, blocking question). Body is Claude's actual prompt.
3. **Claude stopped unexpectedly** — error or unexpected halt. Body says so, plus the last message if available.

Each event type can be individually enabled or disabled in settings.

### Auto-clear on activity

When the user starts typing in the VS Code window that matches a project, Notifly clears any pending notifications tagged with that project.

* "Typing" means any keyboard input that modifies a file in that workspace.
* Debounce: a burst of typing counts as one clear event. Minimum 500 ms between clears.
* Only clears notifications for the matching project — notifications for other projects are untouched.
* If the same project is open in two VS Code windows, typing in either clears Notifly's notification for that project.

### Manual dismissal

* Click the notification → mark it cleared and bring the matching VS Code window to the foreground.
* Swipe away / close → mark cleared, do not focus VS Code.

## Menu Bar App

Notifly runs as a background menu bar app. It is always on when the user is logged in.

* Menu bar icon: simple, monochrome. Same visual weight as other menu bar apps in this toolkit (HomeTeam, Print Status).
* Click → dropdown showing:
  * Version number
  * Check for Updates (or Install Update when a new release is available)
  * Quit Notifly

No settings window. All behavior is fixed defaults:

* All three events enabled
* Glass sound on every notification
* Sticky until dismissed or cleared by typing
* Auto-clear debounce: 500 ms

## How Claude Code talks to Notifly

Notifly ships a small command-line tool that Claude Code hooks call directly, replacing the current `terminal-notifier` command:

```
notifly send --project "Dorothy" --event stop --message "Pushed rename to main."
```

The CLI sends the request to the running Notifly app over a local channel (Unix socket or file-watch — whichever is simplest and most reliable). The app handles the rest.

If the Notifly app is not running when the CLI is called, the CLI should launch it silently and then deliver the event.

## How VS Code talks to Notifly

Notifly ships a VS Code extension that watches for typing in the active workspace.

* On activation, the extension registers the workspace folder name with Notifly.
* On any text-document change in that workspace, the extension sends a "user active" ping to Notifly (debounced).
* Notifly clears notifications for that project on receipt.

The VS Code extension and the Notifly app must agree on the project name — use the workspace folder basename.

## Auto-Update

Follow the existing auto-update pattern used by HomeTeam, Print Status, and What to Watch.

* GitHub Releases with semver tags (`v1.0.0`)
* Release asset: zipped `.app` bundle
* App checks for new versions on launch and every 24 hours
* Orange dot indicator on menu bar icon when an update is available
* Install Update button in Settings → About

## Version 1 Scope

* macOS only (macOS 14+).
* Menu bar app + CLI + VS Code extension.
* Three Claude Code events (Done, Needs attention, Stopped unexpectedly).
* Auto-clear on VS Code typing.
* Fixed defaults — no settings window.

## Out of Scope for v1

* Windows or Linux support.
* Non-Claude-Code notification sources.
* Any user-facing settings or preferences.
* Notification history.
* Rich notification actions (reply, quick buttons).
* Detecting activity in editors other than VS Code.

## Product Tone

* Calm. One notification per project at a time. Nothing ever stacks.
* Out of the way. The user should never have to dismiss a stale notification manually after they've already resumed work.
* Named. Every notification clearly identifies which project Claude is talking about.
