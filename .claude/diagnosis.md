## Issue
Three related bugs in Notifly v0.1.1 that together hijack the user's dev-machine workflow: (1) the NotificationStackWindowController panel was sized to full-screen-height at `.statusBar` level with `ignoresMouseEvents=false`, silently intercepting clicks across ~20% of the screen; (2) the notifly CLI auto-launches the Notifly app whenever the socket is missing, which turned every Claude Code Stop hook into a resurrection mechanism for a just-killed app; (3) there was no automated test for either (panel geometry or CLI no-launch contract), so both shipped silently.

## Is this addressing the symptom or the problem?
Root cause for all three:
- **Panel geometry**: the panel frame is now recomputed on every `manager.$events` change via Combine. Size = `NSHostingView.fittingSize` of the current SwiftUI stack. When events is empty, the panel is `orderOut`'d from the window server entirely so it can't intercept mouse events anywhere. The SwiftUI side decides what the cards look like, and the AppKit side follows. No hit-test shims, no magic numbers.
- **CLI auto-launch**: `launchAppIfNeeded()` is deleted from NotiflyCLI/main.swift. The CLI now does exactly one thing: try to send, fail silently, exit 0. The user (or their login items) owns the app's lifecycle. This is the standard architecture for a stateless CLI that talks to a user-managed daemon.
- **Test coverage**: adding `NotificationStackWindowControllerTests` with explicit assertions that the panel is invisible when empty, sane-sized when non-empty, and never near the full screen height. The next regression will fail the test before it reaches the user.

No symptom-level patching. The original `/tmp/notifly-disabled` kill-switch I wrote earlier was a hack; it's now reverted because the CLI fix makes it unnecessary.

## Is the solution elegant, or a hack?
Elegant. Net code change is: (a) delete ~25 lines of `launchAppIfNeeded` + retry loop from the CLI (the CLI is strictly simpler now — fewer responsibilities, cleaner contract); (b) replace the `repositionToTopRight` full-height sizing with a Combine subscription that uses `NSHostingView.fittingSize`, matching the AppKit frame to the SwiftUI content exactly. Both reduce the surface area of the code rather than adding special cases. The only trade-off is ~10pt between-card gap regions technically still land on the panel (not click-through), but those are 10×420 strips the user would rarely hit precisely, and eliminating them would require per-card hit-testing which is disproportionate for v0.1.2.
