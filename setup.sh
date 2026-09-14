#!/bin/bash
# One-shot project setup for macOS.
# Safe to run repeatedly, and works whether or not you've already run
# `flutter create .` — it scaffolds missing platform files, fetches packages,
# and guarantees the iOS camera permission is present.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Scaffolding platform folders (existing files are kept)"
flutter create . --platforms=ios,android,web

echo "==> Fetching packages"
flutter pub get

PLIST="ios/Runner/Info.plist"
DESC="The camera is used to scan product barcodes and QR codes on packaging."

echo "==> Ensuring iOS camera permission in $PLIST"
if /usr/libexec/PlistBuddy -c "Print :NSCameraUsageDescription" "$PLIST" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :NSCameraUsageDescription $DESC" "$PLIST"
  echo "    already present — updated description"
else
  /usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string $DESC" "$PLIST"
  echo "    added"
fi

# mobile_scanner needs iOS 12+; uncomment/set the platform line in the Podfile.
PODFILE="ios/Podfile"
if [ -f "$PODFILE" ]; then
  echo "==> Setting iOS deployment target to 12.0 in Podfile"
  sed -i '' "s/^# *platform :ios,.*/platform :ios, '12.0'/" "$PODFILE"
fi

# Android needs nothing extra: mobile_scanner injects the CAMERA permission
# via manifest merging, and recent Flutter templates already satisfy minSdk.

echo
echo "Done. Next steps:"
echo "  Chrome : flutter run -d chrome"
echo "  iPhone : open ios/Runner.xcworkspace   # set your signing Team once"
echo "           flutter devices               # find your iPhone's id"
echo "           flutter run -d <device-id>"
