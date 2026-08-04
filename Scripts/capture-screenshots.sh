#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."

APP_BIN="build/Tankful.app/Contents/MacOS/TankfulApp"
OUT_DIR="docs"

Scripts/build-app.sh
mkdir -p "${OUT_DIR}"

echo "Note: screencapture needs Screen Recording permission for your terminal"
echo "(System Settings > Privacy & Security > Screen Recording). Without it the"
echo "captures silently show only the desktop wallpaper."

APP_PID=""
FAKE_HOME=""
cleanup() {
    [[ -n "${APP_PID}" ]] && kill "${APP_PID}" 2>/dev/null || true
    [[ -n "${FAKE_HOME}" ]] && rm -rf "${FAKE_HOME}"
}
trap cleanup EXIT

write_fixtures() {
    local home="$1"
    local now_iso reset_5h_epoch reset_wk_epoch reset_5h_iso reset_wk_iso
    now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reset_5h_epoch="$(date -u -v+2H +%s)"
    reset_wk_epoch="$(date -u -v+3d +%s)"
    reset_5h_iso="$(date -u -v+2H +%Y-%m-%dT%H:%M:%SZ)"
    reset_wk_iso="$(date -u -v+3d +%Y-%m-%dT%H:%M:%SZ)"

    local codex_dir="${home}/.codex/sessions/$(date -u +%Y/%m/%d)"
    mkdir -p "${codex_dir}"
    local codex_file="${codex_dir}/rollout-$(date -u +%Y-%m-%dT%H-%M-%S)-$(uuidgen | tr '[:upper:]' '[:lower:]').jsonl"
    cat > "${codex_file}" <<EOF
{"timestamp":"${now_iso}","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":59.0,"window_minutes":300,"resets_at":${reset_5h_epoch}},"secondary":{"used_percent":9.0,"window_minutes":10080,"resets_at":${reset_wk_epoch}},"plan_type":"team","rate_limit_reached_type":null}}}
EOF

    local tankful_dir="${home}/Library/Application Support/Tankful"
    mkdir -p "${tankful_dir}"
    cat > "${tankful_dir}/claude-rate-limits.json" <<EOF
{"version":1,"capturedAt":"${now_iso}","source":"statusline","windows":[{"id":"five_hour","usedPercent":42,"resetsAt":"${reset_5h_iso}"},{"id":"seven_day","usedPercent":10,"resetsAt":"${reset_wk_iso}"}],"extraWindows":[{"id":"seven_day_opus","usedPercent":12,"resetsAt":"${reset_wk_iso}"}]}
EOF

    echo '{"oauthAccount":{"organizationType":"claude_max"}}' > "${home}/.claude.json"
}

for mode in light dark; do
    FAKE_HOME="$(mktemp -d)"
    write_fixtures "${FAKE_HOME}"

    TANKFUL_PROBE_HOME="${FAKE_HOME}" TANKFUL_PROBE_APPEARANCE="${mode}" \
        "${APP_BIN}" > "${FAKE_HOME}/app.log" 2>&1 &
    APP_PID=$!

    rect_file="${FAKE_HOME}/probe-capture-rect.txt"
    waited=0
    while [[ ! -s "${rect_file}" ]]; do
        if (( waited >= 75 )); then
            echo "Timed out waiting for the panel (${mode}). App log:" >&2
            cat "${FAKE_HOME}/app.log" >&2 || true
            exit 1
        fi
        sleep 0.2
        (( waited += 1 ))
    done

    out="${OUT_DIR}/screenshot-${mode}.png"
    screencapture -x -R "$(cat "${rect_file}")" "${out}"

    kill "${APP_PID}" 2>/dev/null || true
    wait "${APP_PID}" 2>/dev/null || true
    APP_PID=""
    rm -rf "${FAKE_HOME}"
    FAKE_HOME=""

    if [[ ! -s "${out}" ]]; then
        echo "Capture failed: ${out} is missing or empty" >&2
        exit 1
    fi
    echo "Captured ${out} ($(sips -g pixelWidth -g pixelHeight "${out}" | awk '/pixel/ {printf "%s ", $2}'))"
done

echo "Done. Inspect both images before publishing: open ${OUT_DIR}/screenshot-light.png ${OUT_DIR}/screenshot-dark.png"
