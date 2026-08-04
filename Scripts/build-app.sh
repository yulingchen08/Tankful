#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."

APP_NAME="Tankful"
PRODUCT="TankfulApp"
# Ships inside the bundle so the status-line command keeps working wherever the app lives.
BRIDGE="TankfulBridge"
APP_DIR="build/${APP_NAME}.app"

swift build -c release --product "${PRODUCT}"
swift build -c release --product "${BRIDGE}"
BIN_PATH="$(swift build -c release --product "${PRODUCT}" --show-bin-path)"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}/${PRODUCT}" "${APP_DIR}/Contents/MacOS/${PRODUCT}"
cp "${BIN_PATH}/${BRIDGE}" "${APP_DIR}/Contents/MacOS/${BRIDGE}"
cp "Sources/${PRODUCT}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"

codesign --force --sign - "${APP_DIR}"

echo "Built ${PWD}/${APP_DIR}"
