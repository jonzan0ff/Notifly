#!/bin/bash
# Notifly QA menu bar popover screenshots.
# Usage: ./scripts/qa_menubar_screenshots.sh <version>

set -euo pipefail

VERSION="${1:?Usage: qa_menubar_screenshots.sh <version>}"
VERSION="${VERSION#v}"
QA_HOST="qa@iMac.local"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCREENSHOTS_DIR="$PROJECT_DIR/qa/screenshots"

mkdir -p "$SCREENSHOTS_DIR"

echo "==> Notifly menu bar QA: v${VERSION}"

echo "==> Rsync to QA Mac"
rsync -az --exclude='.git' --exclude='DerivedData' --exclude='vscode-extension/.vscode-test' --exclude='vscode-extension/node_modules' "$PROJECT_DIR/" "$QA_HOST:Projects/Notifly/"

echo "==> Run MenuBarPopoverSnapshotTests on QA Mac"
ssh "$QA_HOST" 'security unlock-keychain -p "anthropic" ~/Library/Keychains/login.keychain-db && cd ~/Projects/Notifly && rm -rf macos/Tests/__PopoverSnapshots__ && xcodebuild test -project macos/Notifly.xcodeproj -scheme Notifly -destination "platform=macOS,arch=arm64" -only-testing NotiflyTests/MenuBarPopoverSnapshotTests -allowProvisioningUpdates 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5'

echo "==> Pull PNGs"
TMP_PULL="$(mktemp -d)"
rsync -az "$QA_HOST:Projects/Notifly/macos/Tests/__PopoverSnapshots__/" "$TMP_PULL/"

rm -f "$SCREENSHOTS_DIR"/v${VERSION}_menubar_*.png

count=0
for src in "$TMP_PULL"/*.png; do
    [ -f "$src" ] || continue
    scenario=$(basename "$src" .png)
    dest="$SCREENSHOTS_DIR/v${VERSION}_menubar_${scenario}.png"
    cp "$src" "$dest"
    echo "    $(basename "$dest")"
    count=$((count + 1))
done

rm -rf "$TMP_PULL"

if [ "$count" -eq 0 ]; then
    echo "ERROR: no PNGs were generated" >&2
    exit 1
fi

echo "==> Wrote $count menu bar screenshots to $SCREENSHOTS_DIR"
