#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

readonly SCRIPT_NAME="$(basename "$0")"
readonly TOYS_VOLUME="/Volumes/Toys"
readonly TARGET_ROOT="${TOYS_VOLUME}/Photos @ Toys/@The Present"
readonly SOURCE_DIR="${PWD}"
readonly SOURCE_NAME="$(basename "${SOURCE_DIR}")"
readonly TARGET_DIR="${TARGET_ROOT}/${SOURCE_NAME}"
readonly TMP_DIR="$(mktemp -d)"
readonly MANIFEST_FILE="${TMP_DIR}/manifest.tsv"
TOTAL_BYTES_TO_COPY=0

if [[ -t 1 ]]; then
    readonly COLOR_RESET=$'\033[0m'
    readonly COLOR_DIM=$'\033[2m'
    readonly COLOR_BLUE=$'\033[34m'
    readonly COLOR_CYAN=$'\033[36m'
    readonly COLOR_GREEN=$'\033[32m'
    readonly COLOR_YELLOW=$'\033[33m'
else
    readonly COLOR_RESET=''
    readonly COLOR_DIM=''
    readonly COLOR_BLUE=''
    readonly COLOR_CYAN=''
    readonly COLOR_GREEN=''
    readonly COLOR_YELLOW=''
fi

style_warn() {
    printf '%s%s%s' "${COLOR_YELLOW}" "$1" "${COLOR_RESET}"
}

style_info() {
    printf '%s%s%s' "${COLOR_CYAN}" "$1" "${COLOR_RESET}"
}

style_path() {
    printf '%s%s%s' "${COLOR_BLUE}" "$1" "${COLOR_RESET}"
}

style_ok() {
    printf '%s%s%s' "${COLOR_GREEN}" "$1" "${COLOR_RESET}"
}

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

die() {
    printf '%s: %s\n' "${SCRIPT_NAME}" "$*" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

gum_note() {
    gum style --border rounded --padding "0 1" "$1"
}

gum_confirm() {
    gum confirm "$1"
}

available_bytes() {
    local path="$1"
    df -Pk "${path}" | awk 'NR==2 {print $4 * 1024}'
}

path_size_bytes() {
    local path="$1"
    du -sk "${path}" | awk '{print $1 * 1024}'
}

format_bytes() {
    local bytes="$1"
    local units=(B KB MB GB TB)
    local unit_index=0
    local value="${bytes}"

    while (( value >= 1024 && unit_index < ${#units[@]} - 1 )); do
        value=$(( value / 1024 ))
        ((unit_index += 1))
    done

    printf '%s %s' "${value}" "${units[unit_index]}"
}

format_megabytes() {
    local bytes="$1"
    awk -v bytes="${bytes}" 'BEGIN {printf "%.1f MB", bytes / 1048576}'
}

collect_items() {
    local path
    local base
    local size
    local kind

    : > "${MANIFEST_FILE}"

    for path in "${SOURCE_DIR}"/1.* "${SOURCE_DIR}"/2.* "${SOURCE_DIR}"/thumbnail.jpg; do
        [[ -e "${path}" ]] || continue
        base="$(basename "${path}")"
        if [[ -d "${path}" ]]; then
            kind="dir"
        elif [[ -f "${path}" ]]; then
            kind="file"
        else
            continue
        fi
        size="$(path_size_bytes "${path}")"
        printf '%s\t%s\t%s\t%s\n' "${path}" "${base}" "${kind}" "${size}" >> "${MANIFEST_FILE}"
    done

    [[ -s "${MANIFEST_FILE}" ]] || die "nothing to copy: expected 1.*, 2.* or thumbnail.jpg in ${SOURCE_DIR}"
}

manifest_count() {
    awk 'END {print NR}' "${MANIFEST_FILE}"
}

total_bytes() {
    awk -F '\t' '{sum += $4} END {print sum + 0}' "${MANIFEST_FILE}"
}

ensure_volume_ready() {
    [[ -d "${TOYS_VOLUME}" ]] || die "volume is not mounted: ${TOYS_VOLUME}"
    [[ -d "${TARGET_ROOT}" ]] || die "target root not found: ${TARGET_ROOT}"
}

ensure_free_space() {
    local needed="$1"
    local available

    available="$(available_bytes "${TOYS_VOLUME}")"
    if (( available < needed )); then
        die "not enough free space on Toys: need $(format_bytes "${needed}"), available $(format_bytes "${available}")"
    fi

    gum_note "$(style_ok "Free space is enough.") Need $(style_info "$(format_bytes "${needed}")"), available $(style_info "$(format_bytes "${available}")")."
}

copy_items() {
    local total_items
    local copied_items=0
    local copied_bytes=0
    local start_ts
    local elapsed
    local speed_bytes
    local percent
    local status_line
    local source_path
    local base
    local kind
    local size
    local copied_fmt
    local total_fmt
    local speed_fmt

    total_items="$(manifest_count)"
    start_ts="$(date +%s)"

    while IFS=$'\t' read -r source_path base kind size; do
        copied_items=$(( copied_items + 1 ))
        if [[ "${kind}" == "dir" ]]; then
            mkdir -p "${TARGET_DIR}/${base}"
            rsync -a --human-readable -- "${source_path}/" "${TARGET_DIR}/${base}/"
        else
            rsync -a --human-readable -- "${source_path}" "${TARGET_DIR}/${base}"
        fi

        copied_bytes=$(( copied_bytes + size ))
        elapsed=$(( $(date +%s) - start_ts ))
        if (( elapsed <= 0 )); then
            elapsed=1
        fi
        speed_bytes=$(( copied_bytes / elapsed ))
        if (( TOTAL_BYTES_TO_COPY > 0 )); then
            percent=$(( copied_bytes * 100 / TOTAL_BYTES_TO_COPY ))
        else
            percent=100
        fi

        copied_fmt="$(format_megabytes "${copied_bytes}")"
        total_fmt="$(format_megabytes "${TOTAL_BYTES_TO_COPY}")"
        speed_fmt="$(format_megabytes "${speed_bytes}")"

        status_line="$(printf '%s[%s/%s]%s %s%s%s  %s%3s%%%s  %s%s%s%s / %s%s%s  %s%s/s%s' \
            "${COLOR_DIM}" \
            "${copied_items}" \
            "${total_items}" \
            "${COLOR_RESET}" \
            "${COLOR_BLUE}" \
            "${base}" \
            "${COLOR_RESET}" \
            "${COLOR_GREEN}" \
            "${percent}" \
            "${COLOR_RESET}" \
            "${COLOR_CYAN}" \
            "${copied_fmt}" \
            "${COLOR_RESET}" \
            "${COLOR_DIM}" \
            "${total_fmt}" \
            "${COLOR_RESET}" \
            "${COLOR_YELLOW}" \
            "${speed_fmt}" \
            "${COLOR_RESET}")"
        printf '\r\033[2K%s' "${status_line}"
    done < "${MANIFEST_FILE}"

    printf '\n'
}

main() {
    require_cmd gum
    require_cmd rsync
    require_cmd df
    require_cmd du

    ensure_volume_ready
    collect_items
    TOTAL_BYTES_TO_COPY="$(total_bytes)"

    gum_note "Copying $(style_info "$(manifest_count) items") from $(style_path "${SOURCE_DIR}") to $(style_path "${TARGET_DIR}")"
    ensure_free_space "${TOTAL_BYTES_TO_COPY}"

    if ! gum_confirm "$(style_warn "Copy selected items to Toys?")"; then
        exit 1
    fi

    mkdir -p "${TARGET_DIR}"
    copy_items
    gum_note "$(style_ok "Copy complete:") $(style_path "${TARGET_DIR}")"
}

main "$@"
