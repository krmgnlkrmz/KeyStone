#!/usr/bin/env bash
# Prints the resolved Google Mobile Ads / UMP versions and their Swift-facing names,
# so code is written against the real module surface instead of remembered names.
set -uo pipefail
ROOT="${1:-SourcePackages}"
echo "== Resolved artifacts"
find "$ROOT/artifacts" -maxdepth 3 -name "*.xcframework" 2>/dev/null
for fw in $(find "$ROOT/artifacts" -path "*ios-arm64_x86_64-simulator*" -name "*.framework" -maxdepth 6 2>/dev/null); do
  echo "== $fw"
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$fw/Info.plist" 2>/dev/null
  if [ -d "$fw/Headers" ]; then
    grep -h -E "NS_SWIFT_NAME|^@interface|^@protocol|^typedef NS_ENUM|^- \(|^\+ \(" "$fw"/Headers/*.h \
      | grep -E -i "MobileAds|start|Banner|Interstitial|Rewarded|FullScreen|Request|AdSize|AdaptiveBanner|ConsentInformation|ConsentForm|RequestParameters|canRequestAds|privacyOptions|presentFromViewController|loadWith|NS_SWIFT_NAME" \
      | sed 's/^[ \t]*//' | sort -u | head -250
  fi
  find "$fw/Modules" -name "*.swiftinterface" 2>/dev/null | head -3 | while read f; do echo "-- $f"; head -150 "$f"; done
done
echo "== SKAdNetwork list (Google)"
./scripts/update-skadnetworks.sh --print || true
