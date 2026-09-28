#!/usr/bin/env bash
# Packages the mod into dist/FS25_HomeSpots.zip, ready to drop into the FS25 mods folder.
# Only game files go in the zip; repository files (docs, tests, tools) stay out.
set -euo pipefail

cd "$(dirname "$0")/.."

MOD_NAME="FS25_HomeSpots"
MOD_FILES=(modDesc.xml icon_homeSpots.dds icon_homeSpotHome.dds icon_homeSpotAway.dds scripts)

version=$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' modDesc.xml | head -n 1)
if [[ -z "$version" ]]; then
    echo "Could not read the version from modDesc.xml" >&2
    exit 1
fi

rm -rf dist
mkdir -p dist
zip -q -r -X "dist/${MOD_NAME}.zip" "${MOD_FILES[@]}"

echo "Built dist/${MOD_NAME}.zip (version ${version})"
