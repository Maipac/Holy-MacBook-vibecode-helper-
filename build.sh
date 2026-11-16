#!/bin/bash
# Baut "Holy MacBook.app" in den Ordner build/.
# Voraussetzung: Xcode oder die Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Holy MacBook.app"
ICONSET="build/AppIcon.iconset"

swift build -c release
BINARY="$(swift build -c release --show-bin-path)/HolyMacBook"

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/de.lproj" "$ICONSET"

cp "$BINARY" "$APP/Contents/MacOS/HolyMacBook"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Der de.lproj-Ordner sagt macOS, dass die App deutsch ist. Dadurch erscheinen
# auch die Standard-Menüeinträge (Einstellungen, Beenden, …) auf Deutsch.
printf '"CFBundleDisplayName" = "Holy MacBook";\n' > "$APP/Contents/Resources/de.lproj/InfoPlist.strings"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
  sips -z "$((size * 2))" "$((size * 2))" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

codesign --force --sign - "$APP"

echo
echo "Fertig: $APP"
echo "Starten:      open \"$APP\""
echo "Installieren: cp -R \"$APP\" /Applications/"
