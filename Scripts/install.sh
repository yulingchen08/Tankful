#!/bin/zsh
set -euo pipefail

# One-command install: downloads the latest prebuilt Tankful.app, puts it in
# /Applications, wires up the Claude bridge and launches the app. Designed to be
# piped from curl, but also runs from a checkout (--zip skips the download).
#
#   curl -fsSL https://raw.githubusercontent.com/yulingchen08/Tankful/main/Scripts/install.sh | zsh

REPO="yulingchen08/Tankful"
APP="/Applications/Tankful.app"
ZIP_PATH=""

while (( $# > 0 )); do
    case "$1" in
        --zip)
            (( $# >= 2 )) || { print -ru2 -- "--zip needs a value"; exit 2 }
            ZIP_PATH="$2"; shift 2 ;;
        *) print -ru2 -- "Unknown argument: $1"; exit 2 ;;
    esac
done

# Both executables target macOS 15+; proceeding on an older system would wire a
# bridge into settings.json that cannot even launch.
OS_VERSION="$(sw_vers -productVersion)"
if (( ${OS_VERSION%%.*} < 15 )); then
    print -u2 "Tankful needs macOS 15 or newer; this Mac is on ${OS_VERSION}."
    exit 1
fi

# The bridge installer runs on the python3 that ships with Apple's Command Line
# Tools; without them /usr/bin/python3 is only a stub that pops an install dialog.
if ! xcode-select -p > /dev/null 2>&1; then
    print -u2 "Apple's Command Line Tools are needed (for python3, used by the bridge setup)."
    print -u2 "Accept the dialog that just opened (or run: xcode-select --install),"
    print -u2 "then re-run this installer."
    xcode-select --install > /dev/null 2>&1 || true
    exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

if [[ -z "${ZIP_PATH}" ]]; then
    echo "Downloading the latest Tankful release…"
    ZIP_PATH="${WORK_DIR}/Tankful.zip"
    curl -fsSL -o "${ZIP_PATH}" \
        "https://github.com/${REPO}/releases/latest/download/Tankful.zip"
fi

# A still-running copy would keep stale code alive after the swap below.
osascript -e 'tell application "Tankful" to quit' > /dev/null 2>&1 || true

echo "Installing to ${APP}…"
ditto -x -k "${ZIP_PATH}" "${WORK_DIR}/unpacked"
[[ -d "${WORK_DIR}/unpacked/Tankful.app" ]] || {
    print -u2 "The archive does not contain Tankful.app."
    exit 1
}
rm -rf "${APP}"
ditto "${WORK_DIR}/unpacked/Tankful.app" "${APP}"
# curl downloads carry no quarantine flag, but clear it in case the zip arrived
# through a browser or AirDrop first.
xattr -rd com.apple.quarantine "${APP}" 2> /dev/null || true

# From a checkout the sibling script is the exact version being worked on; piped
# from curl there is no sibling, so fetch the script the same way the zip came.
BRIDGE_INSTALLER="${0:A:h}/install-claude-bridge.sh"
if [[ ! -f "${BRIDGE_INSTALLER}" ]]; then
    BRIDGE_INSTALLER="${WORK_DIR}/install-claude-bridge.sh"
    curl -fsSL -o "${BRIDGE_INSTALLER}" \
        "https://raw.githubusercontent.com/${REPO}/main/Scripts/install-claude-bridge.sh"
fi
echo "Setting up the Claude bridge…"
zsh "${BRIDGE_INSTALLER}" --bridge-path "${APP}/Contents/MacOS/TankfulBridge"

open "${APP}"
echo ""
echo "Done. Tankful is running in your menu bar (top-right of the screen)."
echo "Claude numbers appear after your next Claude Code session gets a response;"
echo "Codex numbers appear once you have used Codex CLI on this machine."
