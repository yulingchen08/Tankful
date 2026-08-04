#!/bin/zsh
set -euo pipefail

# Puts TankfulBridge in front of the user's existing Claude Code status line, so the
# bridge can capture rate limits and then run whatever was configured before.

REPO_ROOT="${0:A:h}/.."
SETTINGS="${HOME}/.claude/settings.json"
BRIDGE_PATH=""
MODE="install"
DRY_RUN="0"

usage() {
    cat <<'USAGE'
Usage: install-claude-bridge.sh [options]

  --dry-run            Show the change without writing anything. Combines with --uninstall.
  --uninstall          Restore the status line the bridge wrapped.
  --bridge-path <p>    Use this bridge binary instead of searching.
  --settings <p>       Settings file to edit (default: ~/.claude/settings.json).
USAGE
}

while (( $# > 0 )); do
    case "$1" in
        # Preview is independent of what is being previewed; sharing one variable would let
        # `--dry-run --uninstall` write the file.
        --dry-run) DRY_RUN="1"; shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        --bridge-path)
            (( $# >= 2 )) || { print -ru2 -- "--bridge-path needs a value"; exit 2 }
            BRIDGE_PATH="$2"; shift 2 ;;
        --settings)
            (( $# >= 2 )) || { print -ru2 -- "--settings needs a value"; exit 2 }
            SETTINGS="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) print -ru2 -- "Unknown argument: $1"; usage; exit 2 ;;
    esac
done

find_bridge() {
    if [[ -n "$BRIDGE_PATH" ]]; then
        # An explicit path that does not work is a mistake worth reporting, not a reason
        # to silently install some other binary.
        [[ -x "$BRIDGE_PATH" ]] || { print -u2 "Not an executable: ${BRIDGE_PATH}"; return 1 }
        print -r -- "${BRIDGE_PATH:A}"
        return 0
    fi

    local candidate
    for candidate in \
        "/Applications/Tankful.app/Contents/MacOS/TankfulBridge" \
        "${REPO_ROOT}/.build/Tankful.app/Contents/MacOS/TankfulBridge"
    do
        if [[ -x "$candidate" ]]; then
            print -r -- "${candidate:A}"
            return 0
        fi
    done

    [[ -f "${REPO_ROOT}/Package.swift" ]] || {
        print -u2 "No TankfulBridge found. Build the app first or pass --bridge-path."
        return 1
    }

    if [[ "$DRY_RUN" == "1" ]]; then
        # A preview must not have the side effect of a release build.
        print -r -- "<would build: swift build -c release --product TankfulBridge>"
        return 0
    fi

    print -u2 "No installed bridge found; building from source…"
    ( cd "$REPO_ROOT" && swift build -c release --product TankfulBridge ) 1>&2
    local bin_path
    bin_path="$(cd "$REPO_ROOT" && swift build -c release --product TankfulBridge --show-bin-path)"
    if [[ -x "${bin_path}/TankfulBridge" ]]; then
        print -r -- "${bin_path}/TankfulBridge"
        return 0
    fi
    print -u2 "Build produced no TankfulBridge binary."
    return 1
}

BRIDGE=""
if [[ "$MODE" == "uninstall" ]]; then
    # Only used to recognise a bridge binary that is not named TankfulBridge; searching
    # (and possibly building) makes no sense when removing.
    [[ -n "$BRIDGE_PATH" ]] && BRIDGE="${BRIDGE_PATH:A}"
else
    BRIDGE="$(find_bridge)"
fi

# The settings path, the bridge path and the mode go in through argv so no path can be
# read as Python source.
python3 - "$SETTINGS" "$MODE" "$BRIDGE" "$DRY_RUN" <<'PYTHON'
import json
import os
import sys
import tempfile
from datetime import datetime

settings_path, mode, bridge, dry_run_flag = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
dry_run = dry_run_flag == "1"
# A symlinked settings.json is normal under dotfile management; replacing the link instead
# of its target would strand every later edit.
settings_path = os.path.realpath(settings_path)

MARKERS = ("TankfulBridge",)
SEPARATOR = " -- "


def sh_quote(value):
    return "'" + value.replace("'", "'\\''") + "'"


def sh_unquote(value):
    """Inverse of sh_quote. Anything not shaped like one quoted word is returned untouched."""
    value = value.strip()
    if len(value) >= 2 and value.startswith("'") and value.endswith("'"):
        inner = value[1:-1]
        if "'" not in inner.replace("'\\''", ""):
            return inner.replace("'\\''", "'")
    return value


def leading_quoted_word(command):
    """(first word, rest) when the command opens with one single-quoted word, else None.

    Scans to the closing quote rather than splitting on the first ` -- `, which a bridge
    path containing that sequence would otherwise hijack.
    """
    if not command.startswith("'"):
        return None
    index = 1
    while index < len(command):
        if command[index] != "'":
            index += 1
        elif command[index:index + 4] == "'\\''":
            index += 4
        else:
            return command[1:index].replace("'\\''", "'"), command[index + 1:]
    return None


def wrapped_remainder(command):
    """The chained command inside a bridge-wrapped status line, or None when not ours.

    Recognition is structural: the command must *start with* the quoted bridge path. Matching
    the name anywhere in the string would claim a command like `'my-TankfulBridge.sh' -x`
    and replace the user's status line with a bare bridge.
    """
    if not isinstance(command, str):
        return None
    parsed = leading_quoted_word(command)
    if parsed is None:
        return None
    word, rest = parsed
    # The basename covers the normal install; the explicit path also catches a bridge binary
    # the user renamed, which would otherwise be wrapped a second time.
    if os.path.basename(word) not in MARKERS and not (bridge and word == bridge):
        return None
    return rest[len(SEPARATOR):] if rest.startswith(SEPARATOR) else ""


def fail(message):
    sys.stderr.write("install-claude-bridge: %s\n" % message)
    sys.exit(1)


existed = os.path.exists(settings_path)
if existed:
    with open(settings_path, "r", encoding="utf-8") as handle:
        original_text = handle.read()
    try:
        settings = json.loads(original_text) if original_text.strip() else {}
    except ValueError as error:
        # Overwriting a file we could not read would destroy settings we cannot see.
        fail("%s is not valid JSON (%s); nothing was changed." % (settings_path, error))
    if not isinstance(settings, dict):
        fail("%s does not contain a JSON object; nothing was changed." % settings_path)
else:
    if mode == "uninstall":
        fail("%s does not exist; nothing to uninstall." % settings_path)
    original_text = None
    settings = {}

status_line = settings.get("statusLine")
if status_line is not None and not isinstance(status_line, dict):
    fail("statusLine in %s is not a JSON object; nothing was changed." % settings_path)
current = status_line.get("command") if isinstance(status_line, dict) else None
remainder = wrapped_remainder(current)
installed = remainder is not None

if mode == "uninstall":
    if not installed:
        print("TankfulBridge is not installed in %s; nothing to do." % settings_path)
        sys.exit(0)
    new_command = sh_unquote(remainder) if remainder.strip() else None
else:
    if installed:
        # Re-running the installer only re-points the bridge; the wrapped command survives.
        new_command = sh_quote(bridge) + (SEPARATOR + remainder if remainder.strip() else "")
    elif isinstance(current, str) and current.strip():
        new_command = sh_quote(bridge) + SEPARATOR + sh_quote(current)
    else:
        new_command = sh_quote(bridge)

updated = dict(settings)
leftover_keys = []
if new_command is None:
    # Dropping the whole object would take any sibling key (padding, …) with it, and those
    # were never ours to remove. A statusLine with no command is inert, so leave one behind
    # rather than delete settings the user wrote.
    leftover_keys = sorted(key for key in status_line if key not in ("type", "command"))
    if leftover_keys:
        updated["statusLine"] = {key: value for key, value in status_line.items() if key != "command"}
    else:
        updated.pop("statusLine", None)
elif isinstance(status_line, dict):
    new_status = dict(status_line)
    new_status["command"] = new_command
    updated["statusLine"] = new_status
else:
    updated["statusLine"] = {"type": "command", "command": new_command}

print("settings:  %s" % settings_path)
print("old:       %s" % (current if current is not None else "(no statusLine)"))
if new_command is not None:
    print("new:       %s" % new_command)
elif leftover_keys:
    print("new:       (command removed; statusLine kept for %s)" % ", ".join(leftover_keys))
    print("note:      that statusLine now has no command; delete it by hand if you do not want it.")
else:
    print("new:       (statusLine removed)")

if new_command == current and existed:
    print("Already up to date; nothing written.")
    sys.exit(0)

if dry_run:
    untouched = sorted(key for key in settings if key != "statusLine")
    print("dry run:   nothing written. Other top-level keys untouched: %s" % (", ".join(untouched) or "(none)"))
    if isinstance(status_line, dict) and new_command is not None:
        siblings = sorted(key for key in status_line if key != "command")
        print("dry run:   other statusLine keys untouched: %s" % (", ".join(siblings) or "(none)"))
    sys.exit(0)

directory = os.path.dirname(os.path.abspath(settings_path))
os.makedirs(directory, exist_ok=True)
mode_bits = os.stat(settings_path).st_mode & 0o777 if existed else 0o600

backup_path = None
if existed:
    # Every mutating run takes one. Deciding when a backup is "needed" is exactly the
    # judgement that loses a status line when the recognition above is ever wrong; a few KB
    # of copies is the cheaper side of that trade.
    stem = "%s.tankful-backup-%s" % (settings_path, datetime.now().strftime("%Y%m%d-%H%M%S"))
    # Two installs inside one second must not have the second bury the first one's copy.
    # lexists, not exists: a dangling symlink already occupies the name.
    backup_path, suffix = stem, 1
    while os.path.lexists(backup_path):
        suffix += 1
        backup_path = "%s-%d" % (stem, suffix)
    # settings.json can hold secrets (env, apiKeyHelper), so the copy is created private and
    # never through a symlink someone else planted: O_EXCL fails rather than follow one.
    backup_fd = os.open(backup_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(backup_fd, "w", encoding="utf-8") as handle:
        handle.write(original_text)
    os.chmod(backup_path, mode_bits)

handle_fd, temp_path = tempfile.mkstemp(dir=directory, prefix=".settings-tankful-")
try:
    with os.fdopen(handle_fd, "w", encoding="utf-8") as handle:
        json.dump(updated, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    os.chmod(temp_path, mode_bits)
    os.replace(temp_path, settings_path)
except BaseException:
    if os.path.exists(temp_path):
        os.unlink(temp_path)
    raise

if backup_path:
    print("backup:    %s" % backup_path)
print("Written. Takes effect on the next statusline refresh.")
PYTHON
