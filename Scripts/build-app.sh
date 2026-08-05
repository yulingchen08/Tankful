#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."

APP_NAME="Tankful"
PRODUCT="TankfulApp"
# Ships inside the bundle so the status-line command keeps working wherever the app lives.
BRIDGE="TankfulBridge"
# Inside .build (hidden) so Spotlight and Launchpad never list the artifact as a second app.
APP_DIR=".build/${APP_NAME}.app"

swift build -c release --product "${PRODUCT}"
swift build -c release --product "${BRIDGE}"
BIN_PATH="$(swift build -c release --product "${PRODUCT}" --show-bin-path)"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}/${PRODUCT}" "${APP_DIR}/Contents/MacOS/${PRODUCT}"
cp "${BIN_PATH}/${BRIDGE}" "${APP_DIR}/Contents/MacOS/${BRIDGE}"
cp "Sources/${PRODUCT}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
# The app loads these through Bundle.main; the SwiftPM resource bundle is useless in a
# bundle built elsewhere because its accessor hardcodes the build machine's .build path.
cp "Sources/${PRODUCT}/Resources/PanelIcon.png" "${APP_DIR}/Contents/Resources/"
cp "Sources/${PRODUCT}/Resources/MenuIcon.png" "${APP_DIR}/Contents/Resources/"

# Finder and the Dock read the icon from an icns, generated here from the master PNG
# so the repo carries a single icon source.
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "${ICONSET_DIR}"
for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" "Sources/${PRODUCT}/Resources/AppIcon.png" \
        --out "${ICONSET_DIR}/icon_${size}x${size}.png" > /dev/null
    sips -z "$((size * 2))" "$((size * 2))" "Sources/${PRODUCT}/Resources/AppIcon.png" \
        --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns -o "${APP_DIR}/Contents/Resources/AppIcon.icns" "${ICONSET_DIR}"
rm -rf "${ICONSET_DIR:h}"

codesign --force --sign - "${APP_DIR}"

echo "Built ${PWD}/${APP_DIR}"
