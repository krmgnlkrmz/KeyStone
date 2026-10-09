#!/usr/bin/env bash
# Regenerates DengeNoktasi.xcodeproj from project.yml. Only needed after editing project.yml: the
# generated project is committed, and CI fails when it no longer matches project.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

want=$(cat .xcodegen-version)
command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen (the project is generated with $want)"; exit 1; }
have=$(xcodegen --version | sed 's/[^0-9.]//g')
[ "$have" = "$want" ] || echo "warning: xcodegen $have; the committed project comes from $want (.xcodegen-version), so CI may see a difference"
xcodegen generate
