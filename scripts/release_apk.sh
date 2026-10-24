#!/usr/bin/env bash
# Build the Android app and publish it so installed apps update themselves.
#
# Usage:  HR_FTP_PASS='...' scripts/release_apk.sh "What's new in this version"
#
# Before running, bump `version:` in mobile_app/pubspec.yaml (e.g. 1.0.2+3).
# The number after "+" (versionCode) MUST increase on every release, otherwise
# installed apps will not see an update.
#
# Publishes to:  <host>/app/alanad/AlAnad-HR.apk  and  <host>/app/alanad/version.json
# Optional env:  HR_FTP_HOST, HR_FTP_USER, HR_FTP_DIR, HR_SITE_URL
set -euo pipefail

: "${HR_FTP_PASS:?Set HR_FTP_PASS (FTP password) in the environment}"
HR_FTP_HOST="${HR_FTP_HOST:?set HR_FTP_HOST}"
HR_FTP_USER="${HR_FTP_USER:?set HR_FTP_USER}"
HR_FTP_DIR="${HR_FTP_DIR:-domains/quadrocloud.net/public_html/public_html/AlanadHR}"
HR_SITE_URL="${HR_SITE_URL:-https://alanadhr.quadrocloud.net}"
# Apps released before the move to the dedicated server still read the old manifest: also publish it there once.
HR_LEGACY_DIR="${HR_LEGACY_DIR:-}"
NOTES="${1:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/mobile_app"

VERSION_LINE="$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}')"
VERSION_NAME="${VERSION_LINE%%+*}"
VERSION_CODE="${VERSION_LINE##*+}"
echo "Releasing $VERSION_NAME (code $VERSION_CODE)"

flutter build apk --release
APK="build/app/outputs/flutter-apk/app-release.apk"
SHA="$(sha256sum "$APK" | awk '{print $1}')"

TMP="$(mktemp -d)"
NOTES_ESC="${NOTES//\/\\}"; NOTES_ESC="${NOTES_ESC//\"/\\\"}"
cat > "$TMP/version.json" <<JSON
{
  "versionCode": $VERSION_CODE,
  "versionName": "$VERSION_NAME",
  "apkUrl": "$HR_SITE_URL/app/alanad/AlAnad-HR-$VERSION_NAME.apk",
  "sha256": "$SHA",
  "notes": "$NOTES_ESC",
  "mandatory": ${HR_MANDATORY:-false}
}
JSON

FTP="ftp://$HR_FTP_HOST/$HR_FTP_DIR/app/alanad"
echo "Uploading APK..."
# Every release gets its own file name: the host's CDN caches files by URL, and a re-used name made phones receive an
# OLD cached APK ("the downloaded file is invalid"). AlAnad-HR.apk stays as the "latest" link for manual downloads only.
curl -sS --fail --ftp-create-dirs -T "$APK" -u "$HR_FTP_USER:$HR_FTP_PASS" "$FTP/AlAnad-HR-$VERSION_NAME.apk"
curl -sS --fail -T "$APK" -u "$HR_FTP_USER:$HR_FTP_PASS" "$FTP/AlAnad-HR.apk"
echo "Publishing version.json..."   # last, so apps never see a version whose APK is missing
curl -sS --fail -T "$TMP/version.json" -u "$HR_FTP_USER:$HR_FTP_PASS" "$FTP/version.json"
if [ -n "$HR_LEGACY_DIR" ]; then
  curl -sS --fail --ftp-create-dirs -T "$TMP/version.json" -u "$HR_FTP_USER:$HR_FTP_PASS" "ftp://$HR_FTP_HOST/$HR_LEGACY_DIR/app/alanad/version.json"
  echo "Legacy manifest published."
fi

cp "$APK" "$HOME/Desktop/AlAnad-HR-v$VERSION_NAME.apk" 2>/dev/null || true
echo "Done. Live manifest:"; curl -s "$HR_SITE_URL/app/alanad/version.json"; echo
rm -rf "$TMP"
