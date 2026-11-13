#!/bin/sh
# Builds the Joy-Con probe as an unsigned IPA: dm/ios/tools/joycon_probe/main.m.
#   dm/ios/tools/joycon_probe/build.sh [output folder]
# The app is ad-hoc signed only on its executable, as the NSP script's unsigned IPAs are; a
# sideloader signs the bundle for the device.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-$here/build}
app="$out/Payload/JoyConProbe.app"

rm -rf "$out"
mkdir -p "$app"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -fobjc-arc -O1 -g \
    -framework UIKit -framework GameController -framework CoreGraphics \
    -o "$app/JoyConProbe" "$here/main.m"
rm -rf "$app"/*.dSYM            # clang -g leaves one beside the binary; an app bundle holds none
cp "$here/Info.plist" "$app/Info.plist"
codesign --force --sign - "$app/JoyConProbe"
(cd "$out" && zip -qr "$out/JoyConProbe.ipa" Payload)
rm -rf "$out/Payload"
echo "$out/JoyConProbe.ipa"
