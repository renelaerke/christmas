#!/bin/zsh
# Builds build/JuleHygge.app (ad-hoc signed). The app icon is drawn by the app itself, so the repo has no image files.
set -euo pipefail
cd "${0:A:h}"
# UNIVERSAL=1 builds one binary for both Apple Silicon and Intel (used by the GitHub release workflow).
ARCHS=()
if [[ "${UNIVERSAL:-0}" == 1 ]]; then ARCHS=(--arch arm64 --arch x86_64); fi
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/JuleHygge"
APP=build/JuleHygge.app
ICONSET=build/JuleHygge.iconset
rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"
cp "$BIN" "$APP/Contents/MacOS/JuleHygge"
cp Info.plist "$APP/Contents/Info.plist"
# VERSION=x.y.z stamps the app (the GitHub workflow passes the release tag). Without it the app is 0.0.0,
# which the app's self-update treats as a developer build that never updates itself.
VERSION="${VERSION:-0.0.0}"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then echo "VERSION skal se ud som 1.2.3, fik '$VERSION'" >&2; exit 1; fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
if [[ "$VERSION" != 0.0.0 ]]; then /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"; fi
"$BIN" --icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/JuleHygge.icns"
# The one sound file: the recording of geese for the autumn theme (see assets/lyd/KILDER.md).
cp ../assets/lyd/gaes-flok.wav "$APP/Contents/Resources/gaes-flok.wav"
# The menu's languages (assets/sprog/README.md): every file there goes along.
mkdir -p "$APP/Contents/Resources/sprog"
cp ../assets/sprog/*.ini "$APP/Contents/Resources/sprog/"
# The one model file: tells clothes from skin and hair for the camera costume (see assets/model/KILDER.md).
xcrun coremlcompiler compile ../assets/model/selfie_multiclass_256x256.mlpackage "$APP/Contents/Resources" >/dev/null
# The model's licence goes with it (Apache 2.0); the menu shows it (Licenses.swift).
cp licenses/Apache-2.0.txt "$APP/Contents/Resources/Apache-2.0.txt"
codesign --force --sign - "$APP" >/dev/null
echo "Bygget: $PWD/$APP (version $VERSION)"
