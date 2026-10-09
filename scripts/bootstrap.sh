#!/usr/bin/env bash
# Generates the Xcode project and resolves packages.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f Config/Release.xcconfig ]; then
  cp Config/Release.example.xcconfig Config/Release.xcconfig
  echo "Created Config/Release.xcconfig from the example (test ad IDs). Fill in real IDs before release."
fi

command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen"; exit 1; }
xcodegen generate
xcodebuild -resolvePackageDependencies -project DengeNoktasi.xcodeproj -scheme DengeNoktasi
