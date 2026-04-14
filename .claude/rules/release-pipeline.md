# Release Pipeline — Protected

The project has a fully-wired Apple-approved Developer ID distribution pipeline. **Do not modify any of these files without understanding the consequences** — breakage is silent and only surfaces on end-users' Macs after notarization and install.

## Protected files

| File | What it does |
|---|---|
| `scripts/release.sh` | Runs `xcodebuild archive` → `xcodebuild -exportArchive` → notarize → staple → GitHub Release |
| `macos/exportOptions.plist` | Tells xcodebuild to sign with Developer ID using automatic signing (Notifly has no App Groups so no manual provisioning profile is needed) |
| `macos/project.yml` — `DEVELOPMENT_TEAM`, bundle IDs, `ENABLE_HARDENED_RUNTIME` | Must stay consistent (release.sh overrides hardened runtime to YES at build time) |

## What not to do without coordination

1. **Do not change bundle IDs** — `com.Notiflyz.app` and `com.Notiflyz.app.cli` are registered in the Apple Developer portal.
2. **Do not change `DEVELOPMENT_TEAM`** — must stay `Q4MZVR4MU5`.
3. **Do not add entitlements** that require provisioning profiles (App Groups, iCloud, Push, HomeKit, CallKit, etc.) without:
   - Enabling the capability on the App ID at https://developer.apple.com/account/resources/identifiers/list
   - Creating a Developer ID provisioning profile with that capability
   - Installing the profile and converting `exportOptions.plist` from `signingStyle=automatic` to `manual` with a `provisioningProfiles` dictionary
   - (The other 4 Mac apps under this Apple ID already do this — see Print Status, HomeTeam, What to Watch, or Dorothy for the pattern)
4. **Do not add new app targets** — the CLI target (`NotiflyCLI`) already ships inside the main bundle at `Contents/Resources/notifly`. If you add a second executable, it needs to be signed + added to the archive flow.
5. **Do not delete or edit `macos/exportOptions.plist`** — kept minimal because Notifly has no provisioning profiles; adding provisioningProfiles to it requires the portal setup above.
6. **Do not modify `scripts/release.sh`** unless you understand the SIGPIPE-under-pipefail gotcha in the verification checks and the `STRIP_INSTALLED_PRODUCT=NO` requirement to avoid launchd POSIX error 163.

## If you need to ship

1. Commit your changes
2. Bump `MARKETING_VERSION` in `macos/project.yml`
3. `cd macos && xcodegen generate && cd .. && git checkout -- macos/Config/`
4. Commit the version bump
5. Run `./scripts/release.sh` — it archives, exports, notarizes, staples, and publishes to `jonzan0ff/Notifly` releases

## Shared infrastructure

- Developer ID Application certificate is in the login keychain (Team ID `Q4MZVR4MU5`)
- Notarytool keychain profile is named `PrintStatus-Notary` — shared across all five Mac apps (HomeTeam, What to Watch, Dorothy, Print Status, Notifly). The name is a label; it stores Apple ID + app-specific password credentials that work for any app under the same team.
- Provisioning profiles are in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` keyed by UUID. Notifly doesn't use them today but don't delete that directory — the other Mac apps rely on it.

## History

Ported from Print Status on 2026-04-14 after the widget team-identifier bug in Print Status led to establishing a unified release pipeline across all Mac apps. Notifly has the simplest version (no App Groups, no widget, automatic signing) because it has no capabilities that require a provisioning profile.
