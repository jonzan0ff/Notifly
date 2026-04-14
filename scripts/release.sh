#!/bin/bash
set -euo pipefail

# Release script for Notifly.
# Uses Apple's one-pass Developer ID distribution path. No App Groups, no
# widget, no provisioning profiles — exportOptions.plist uses automatic signing
# and Xcode picks up the installed Developer ID Application certificate.

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Notifly"
REPO="jonzan0ff/Notifly"
NOTARY_PROFILE="PrintStatus-Notary"  # keychain profile, shared across all Mac apps
PROJECT_SUBDIR="macos"
ARCHIVE_PATH="/tmp/${APP_NAME}.xcarchive"
EXPORT_DIR="/tmp/${APP_NAME}-export"
EXPORT_OPTIONS="${PROJECT_DIR}/${PROJECT_SUBDIR}/exportOptions.plist"

VERSION=$(grep 'MARKETING_VERSION:' "${PROJECT_DIR}/${PROJECT_SUBDIR}/project.yml" | head -1 | sed 's/.*"\(.*\)"/\1/')
ZIP_PATH="/tmp/${APP_NAME}-${VERSION}.zip"

echo "==> Releasing ${APP_NAME} v${VERSION}"

if [ -z "$(git -C "${PROJECT_DIR}" status --porcelain)" ]; then
    echo "    working tree clean"
else
    echo "    ERROR: working tree has uncommitted or untracked changes. Commit first." >&2
    exit 1
fi

if gh release view "v${VERSION}" --repo "${REPO}" >/dev/null 2>&1; then
    echo "    ERROR: release v${VERSION} already exists. Bump MARKETING_VERSION." >&2
    exit 1
fi

echo "==> Killing any running DerivedData build"
pkill -f "DerivedData.*${APP_NAME}" 2>/dev/null || true

echo "==> Archiving (xcodebuild archive)"
rm -rf "${ARCHIVE_PATH}" "${EXPORT_DIR}"
xcodebuild archive \
    -project "${PROJECT_DIR}/${PROJECT_SUBDIR}/${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    ENABLE_HARDENED_RUNTIME=YES \
    STRIP_INSTALLED_PRODUCT=NO \
    DEPLOYMENT_POSTPROCESSING=NO \
    COPY_PHASE_STRIP=NO \
    > /tmp/${APP_NAME}-archive.log 2>&1 || { tail -30 /tmp/${APP_NAME}-archive.log; exit 1; }

echo "==> Exporting with Developer ID (xcodebuild -exportArchive)"
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    > /tmp/${APP_NAME}-export.log 2>&1 || { tail -30 /tmp/${APP_NAME}-export.log; exit 1; }

APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1 | tail -5

SIG_INFO=$(codesign -dvv "${APP_PATH}" 2>&1)

echo "$SIG_INFO" | grep -q "Authority=Developer ID Application" \
    || { echo "ERROR: not signed with Developer ID" >&2; exit 1; }
echo "$SIG_INFO" | grep -q "flags.*runtime" \
    || { echo "ERROR: hardened runtime not enabled" >&2; exit 1; }

echo "==> Zipping"
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo "==> Submitting to Apple notary service"
xcrun notarytool submit "${ZIP_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"

echo "==> Re-zipping stapled app"
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo "==> Creating GitHub release"
gh release create "v${VERSION}" "${ZIP_PATH}" \
    --repo "${REPO}" \
    --title "v${VERSION}" \
    --notes "Notarized release." \
    --latest

echo "==> Cleaning up"
rm -f "${ZIP_PATH}"
rm -rf "${ARCHIVE_PATH}" "${EXPORT_DIR}"

echo "==> Done. v${VERSION} is live."
echo "    Run 'open /Applications/${APP_NAME}.app' to trigger the in-app updater."
