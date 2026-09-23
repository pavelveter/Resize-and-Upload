#!/usr/bin/env bash
#
# cptoys.sh — Backup the current directory to the Toys external volume.
#
# Copies the current working directory to:
#   /Volumes/Toys/Photos @ Toys/@The Present/$(basename "$PWD")
#
# Update semantics: files missing at target or differing by size are copied;
# identical files are skipped. .DS_Store / ._ * / .localized are never copied.
#
# Dependencies: gum, rsync
#

set -euo pipefail

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

SPIN_STTY_FILE="${TMP_DIR}/spin-stty.txt"

restore_tty_and_cleanup() {
    if [[ -f "${SPIN_STTY_FILE}" ]]; then
        # A gum spin is (or was) in progress: drain any pending terminal
        # capability replies before they get echoed, then restore the tty.
        stty -icanon min 0 time 1 </dev/tty 2>/dev/null || true
        local drain_line
        for drain_line in 1 2; do
            IFS= read -r -t 1 -n 4096 drain_line </dev/tty 2>/dev/null || break
        done
        stty "$(cat "${SPIN_STTY_FILE}")" </dev/tty 2>/dev/null || true
        rm -f "${SPIN_STTY_FILE}"
    fi
    rm -rf "${TMP_DIR}"
}
trap restore_tty_and_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

log() {
    printf '%s\n' "$*"
}

die() {
    printf '%s: %s\n' "${SCRIPT_NAME}" "$*" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

gum_confirm() {
    gum confirm "$1"
}

gum_spin() {
    # gum spin (bubbletea v2) probes the terminal for capabilities
    # (synchronized updates mode 2026, unicode core mode 2027, kitty keyboard
    # "?u") but runs with stdin disabled, so nothing consumes the replies.
    # Once the spinner exits, the tty line discipline echoes them and they
    # show up as garbage like "^[[?2026;2$y". Mute the echo while gum runs
    # and drain any pending replies before restoring the tty. The EXIT trap
    # (restore_tty_and_cleanup) covers an interrupted spin.
    local spin_saved_stty=""
    local spin_rc=0
    local drain_line

    if [[ -t 2 ]]; then
        spin_saved_stty="$(stty -g </dev/tty 2>/dev/null)" || spin_saved_stty=""
        if [[ -n "${spin_saved_stty}" ]]; then
            printf '%s\n' "${spin_saved_stty}" > "${SPIN_STTY_FILE}"
            stty -echo </dev/tty
            # gum_spin runs in a command-substitution subshell, where the
            # parent traps are reset, so arm local ones to restore the tty
            # even if interrupted mid-spin. The saved state goes through a
            # file so that the main shell's EXIT trap can restore the tty
            # too, whichever process dies first.
            trap 'if [[ -f "${SPIN_STTY_FILE}" ]]; then stty "$(cat "${SPIN_STTY_FILE}")" </dev/tty 2>/dev/null; rm -f "${SPIN_STTY_FILE}"; fi' EXIT
            trap 'exit 130' INT
            trap 'exit 143' TERM
        fi
    fi

    SSH_TTY="${SSH_TTY:-/dev/null}" gum spin "$@" || spin_rc=$?

    if [[ -n "${spin_saved_stty}" ]]; then
        rm -f "${SPIN_STTY_FILE}"
        stty -icanon min 0 time 1 </dev/tty
        for drain_line in 1 2 3; do
            IFS= read -r -t 1 -n 4096 drain_line </dev/tty 2>/dev/null || break
        done
        stty "${spin_saved_stty}" </dev/tty
        trap restore_tty_and_cleanup EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
    fi
    return "${spin_rc}"
}

gum_choose_single() {
    local header="$1"
    shift
    printf '%s\n' "$@" | gum choose --header "${header}" --limit 1
}

gum_note() {
    gum style --border rounded --padding "0 1" "$1"
}

file_size_bytes() {
    stat -f '%z' "$1"
}

available_bytes() {
    df -Pk "$1" | awk 'NR==2 {print $4 * 1024}'
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

format_eta() {
    # Remaining time as HH:MM:SS; hours shown only when non-zero.
    local seconds="$1"
    local hours=$(( seconds / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$(( seconds % 60 ))
    if (( hours > 0 )); then
        printf '%02d:%02d:%02d' "${hours}" "${minutes}" "${secs}"
    else
        printf '%02d:%02d' "${minutes}" "${secs}"
    fi
}

term_cols() {
    local cols="${COLUMNS:-}"
    if [[ -z "${cols}" ]]; then
        cols="$(tput cols 2>/dev/null || printf '80')"
    fi
    [[ "${cols}" =~ ^[0-9]+$ ]] || cols=80
    (( cols < 20 )) && cols=20
    printf '%s\n' "${cols}"
}

fit_rel() {
    # Truncate rel to at most avail visible cells, keeping the basename
    # (the part that identifies the file). Length math uses ${#}, which
    # overcounts multibyte chars on some bash builds — that only makes
    # the line shorter, never wider, so the one-line guarantee holds.
    # Ponytail: tail-preserving truncation; upgrade path is middle-
    # ellipsis with wcwidth-aware measuring if names need exact fit.
    local rel="$1"
    local avail="$2"
    local base head_len
    (( avail < 8 )) && avail=8
    if (( ${#rel} <= avail )); then
        printf '%s' "${rel}"
        return
    fi
    base="$(basename -- "${rel}")"
    if (( ${#base} + 2 >= avail )); then
        printf '%s…' "${base:0:avail-1}"
        return
    fi
    head_len=$(( avail - ${#base} - 2 ))
    printf '%s…/%s' "${rel:0:head_len}" "${base}"
}

find_files() {
    local root="$1"
    find "${root}" -type f \
        ! -name '.DS_Store' \
        ! -name '._*' \
        ! -name '.localized' \
        -print0
}

collect_files() {
    local root="$1"
    local file
    local rel
    local size

    : > "${MANIFEST_FILE}"

    while IFS= read -r -d '' file; do
        rel="${file#"${root}"/}"
        size="$(file_size_bytes "${file}")"
        printf '%s\t%s\t%s\n' "${file}" "${rel}" "${size}" >> "${MANIFEST_FILE}"
    done < <(find_files "${root}")

    [[ -s "${MANIFEST_FILE}" ]] || die "no files to back up in ${root}"
}

manifest_file_count() {
    awk 'END {print NR}' "${MANIFEST_FILE}"
}

ensure_volume_ready() {
    [[ -d "${TOYS_VOLUME}" ]] || die "volume is not mounted: ${TOYS_VOLUME}"
    [[ -d "${TARGET_ROOT}" ]] || die "target root not found: ${TARGET_ROOT}"
}

# Compares manifest entries against the target. Emits "duplicates;changed;missing".
inspect_target() {
    local target_dir="$1"
    local duplicate_count=0
    local changed_count=0
    local missing_count=0
    local source_file
    local rel
    local source_size
    local target_size

    while IFS=$'\t' read -r source_file rel source_size; do
        if [[ -f "${target_dir}/${rel}" ]]; then
            target_size="$(file_size_bytes "${target_dir}/${rel}")"
            if [[ "${source_size}" == "${target_size}" ]]; then
                ((duplicate_count += 1))
            else
                ((changed_count += 1))
            fi
        else
            ((missing_count += 1))
        fi
    done < "${MANIFEST_FILE}"

    printf '%s;%s;%s\n' "${duplicate_count}" "${changed_count}" "${missing_count}"
}

# Emits "count;bytes" for files that need copying (missing or size-changed).
files_to_copy() {
    local target_dir="$1"
    local source_file
    local rel
    local source_size
    local target_size
    local total=0
    local bytes=0

    while IFS=$'\t' read -r source_file rel source_size; do
        if [[ -f "${target_dir}/${rel}" ]]; then
            target_size="$(file_size_bytes "${target_dir}/${rel}")"
            if [[ "${source_size}" == "${target_size}" ]]; then
                continue
            fi
        fi
        total=$(( total + 1 ))
        bytes=$(( bytes + source_size ))
    done < "${MANIFEST_FILE}"

    printf '%s;%s\n' "${total}" "${bytes}"
}

ensure_free_space() {
    local needed="$1"
    local available

    available="$(available_bytes "${TARGET_DIR}")"
    if (( available < needed )); then
        die "not enough free space on Toys: need $(format_bytes "${needed}"), available $(format_bytes "${available}")"
    fi

    gum_note "$(style_ok "Free space is enough.") Need $(style_info "$(format_bytes "${needed}")"), available $(style_info "$(format_bytes "${available}")")."
}

copy_files() {
    local target_dir="$1"
    local source_file
    local rel
    local source_size
    local target_size
    local total_files
    local copied_files=0
    local copied_bytes=0
    local elapsed
    local speed_bytes
    local start_ts
    local percent
    local status_line
    local copied_fmt
    local total_fmt
    local speed_fmt
    local eta_fmt
    local cols
    local counter
    local pct_txt
    local sizes_txt
    local speed_txt
    local fixed_len
    local avail
    local rel_disp

    # Count only the entries that need copying, so the progress counter
    # reads [copied/needed] the way cpflash.sh does.
    total_files=0
    while IFS=$'\t' read -r source_file rel source_size; do
        if [[ -f "${target_dir}/${rel}" ]]; then
            target_size="$(file_size_bytes "${target_dir}/${rel}")"
            if [[ "${source_size}" == "${target_size}" ]]; then
                continue
            fi
        fi
        total_files=$(( total_files + 1 ))
    done < "${MANIFEST_FILE}"
    start_ts="$(date +%s)"

    while IFS=$'\t' read -r source_file rel source_size; do
        if [[ -f "${target_dir}/${rel}" ]]; then
            target_size="$(file_size_bytes "${target_dir}/${rel}")"
            if [[ "${source_size}" == "${target_size}" ]]; then
                continue
            fi
        fi

        copied_files=$(( copied_files + 1 ))
        mkdir -p "${target_dir}/$(dirname -- "${rel}")"
        rsync -a --human-readable -- "${source_file}" "${target_dir}/${rel}"

        copied_bytes=$(( copied_bytes + source_size ))
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

        # Dynamic ETA: remaining bytes at the average speed so far,
        # recalculated after every file. On the last copied file, show the
        # total elapsed copy time instead of a pointless 00:00.
        if (( copied_files == total_files )); then
            eta_fmt="$(format_eta "${elapsed}")"
        elif (( speed_bytes > 0 )); then
            eta_fmt="$(format_eta $(( (TOTAL_BYTES_TO_COPY - copied_bytes) / speed_bytes )))"
        else
            eta_fmt="--:--"
        fi

        # Single updating line: truncate rel so the visible line never
        # exceeds the terminal width (narrow terminals wrapped it into
        # new lines). On very narrow terminals fall back to a compact
        # line that keeps counter, file tail, percent and ETA.
        cols="$(term_cols)"
        counter="[${copied_files}/${total_files}]"
        pct_txt="$(printf '%3s%%' "${percent}")"
        sizes_txt="${copied_fmt} / ${total_fmt}"
        speed_txt="${speed_fmt}/s"
        fixed_len=$(( ${#counter} + 1 + 2 + 4 + 2 + ${#sizes_txt} + 2 + ${#speed_txt} + 2 + ${#eta_fmt} ))
        avail=$(( cols - fixed_len - 1 ))
        if (( avail >= 12 )); then
            rel_disp="$(fit_rel "${rel}" "${avail}")"
            status_line="$(printf '%s[%s/%s]%s %s%s%s  %s%3s%%%s  %s%s%s%s / %s%s%s  %s%s/s%s  %s%s%s' \
                "${COLOR_DIM}" \
                "${copied_files}" \
                "${total_files}" \
                "${COLOR_RESET}" \
                "${COLOR_BLUE}" \
                "${rel_disp}" \
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
                "${COLOR_RESET}" \
                "${COLOR_YELLOW}" \
                "${eta_fmt}" \
                "${COLOR_RESET}")"
        else
            avail=$(( cols - ${#counter} - 1 - 4 - 2 - ${#eta_fmt} - 2 ))
            rel_disp="$(fit_rel "${rel}" "${avail}")"
            status_line="$(printf '%s[%s/%s]%s %s%s%s  %s%s%s  %s%s%s' \
                "${COLOR_DIM}" \
                "${copied_files}" \
                "${total_files}" \
                "${COLOR_RESET}" \
                "${COLOR_BLUE}" \
                "${rel_disp}" \
                "${COLOR_RESET}" \
                "${COLOR_GREEN}" \
                "${pct_txt}" \
                "${COLOR_RESET}" \
                "${COLOR_YELLOW}" \
                "${eta_fmt}" \
                "${COLOR_RESET}")"
        fi
        printf '\r\033[2K%s' "${status_line}"
    done < "${MANIFEST_FILE}"

    printf '\n'
}

main() {
    require_cmd gum
    require_cmd rsync
    require_cmd find
    require_cmd df
    require_cmd stat

    local duplicate_count
    local changed_count
    local missing_count
    local total_count
    local copy_count
    local copy_bytes

    ensure_volume_ready
    collect_files "${SOURCE_DIR}"
    total_count="$(manifest_file_count)"

    gum_spin --spinner line --title "Checking existing files..." -- \
        bash "$0" --internal-inspect-target "${SOURCE_DIR}" "${TARGET_DIR}" \
        > "${TMP_DIR}/target_stats.txt"
    IFS=';' read -r duplicate_count changed_count missing_count <<< "$(cat "${TMP_DIR}/target_stats.txt")"

    if (( missing_count == 0 && changed_count == 0 )); then
        gum_note "All $(style_info "${total_count} files") are already backed up. Nothing to copy."
        exit 0
    fi

    gum_spin --spinner line --title "Calculating required space..." -- \
        bash "$0" --internal-files-to-copy "${SOURCE_DIR}" "${TARGET_DIR}" \
        > "${TMP_DIR}/needed.txt"
    IFS=';' read -r copy_count copy_bytes <<< "$(cat "${TMP_DIR}/needed.txt")"
    TOTAL_BYTES_TO_COPY="${copy_bytes}"

    gum_note "Found $(style_path "${SOURCE_NAME}") | $(style_info "${total_count} files") | $(style_ok "${copy_count} to copy") ($(style_info "$(format_bytes "${copy_bytes}")"))"

    if ! gum_confirm "$(style_warn "Copy ${copy_count} files ($(format_bytes "${copy_bytes}")) to ${TARGET_DIR}?")"; then
        exit 1
    fi

    mkdir -p "${TARGET_DIR}"
    ensure_free_space "${copy_bytes}"

    copy_files "${TARGET_DIR}"
    gum_note "$(style_ok "Copy complete:") $(style_path "${TARGET_DIR}")"
}

if [[ "${1:-}" == "--internal-inspect-target" ]]; then
    collect_files "$2"
    inspect_target "$3"
    exit 0
fi

if [[ "${1:-}" == "--internal-files-to-copy" ]]; then
    collect_files "$2"
    files_to_copy "$3"
    exit 0
fi

main "$@"
