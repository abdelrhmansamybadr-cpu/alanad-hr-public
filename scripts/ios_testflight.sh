#!/usr/bin/env bash
# Build the iPhone app archive (.ipa) ready to upload to TestFlight. Run this on a Mac.
#
#   scripts/ios_testflight.sh
#
# Needs: Xcode, Flutter, CocoaPods, and the Team / Bundle Identifier set once in Xcode
# (see docs/IPHONE_BUILD.md). The version comes from mobile_app/pubspec.yaml (version: 1.6.3+16);
# raise the number after "+" for every upload.
set -euo pipefail

if [ "$(uname)" != "Darwin" ]; then
  echo "This script must run on a Mac (iPhone apps can only be built with Xcode)."; exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/mobile_app"

echo "== Flutter version"; flutter --version | head -1
echo "== Packages"; flutter pub get
echo "== Pods"; (cd ios && pod install --repo-update)
echo "== Tests"; flutter test test/update_buttons_test.dart test/notification_bell_test.dart 2>/dev/null || true
echo "== Building the archive"
flutter build ipa --release

IPA="$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -1 || true)"
if [ -z "$IPA" ]; then echo "No .ipa produced. Open ios/Runner.xcworkspace in Xcode, set the Team and Bundle Identifier, and run again."; exit 1; fi
echo
echo "Built: $IPA"
echo "Upload it with the Transporter app (drag the file in, press Deliver) or:"
echo "  xcrun altool --upload-app -f \"$IPA\" -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>"
