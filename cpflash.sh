#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly PHOTOS_DIR="${HOME}/Photos"
readonly TMP_DIR="$(mktemp -d)"
readonly MANIFEST_FILE="${TMP_DIR}/manifest.tsv"
readonly STATE_DIR="${HOME}/.cache/goresize"
readonly LAST_TARGET_FILE="${STATE_DIR}/cpflash-last-target-dir"
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

remember_target_dir() {
    local target_dir="$1"
    mkdir -p "${STATE_DIR}"
    printf '%s\n' "${target_dir}" > "${LAST_TARGET_FILE}"
}

print_last_target_dir() {
    [[ -f "${LAST_TARGET_FILE}" ]] || return 1
    cat "${LAST_TARGET_FILE}"
}

photomechanic_app_path() {
    local app_path

    for app_path in \
        "/Applications/Photo Mechanic.app" \
        "/Applications/Photo Mechanic 6.app" \
        "/Applications/Photo Mechanic Plus.app" \
        "${HOME}/Applications/Photo Mechanic.app" \
        "${HOME}/Applications/Photo Mechanic 6.app" \
        "${HOME}/Applications/Photo Mechanic Plus.app"
    do
        [[ -d "${app_path}" ]] && {
            printf '%s\n' "${app_path}"
            return 0
        }
    done

    return 1
}

can_open_photomechanic() {
    is_macos && photomechanic_app_path >/dev/null 2>&1
}

open_in_photomechanic() {
    local target_dir="$1"
    local app_path
    local executable_name
    local executable_path

    app_path="$(photomechanic_app_path)" || return 1
    executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${app_path}/Contents/Info.plist" 2>/dev/null)" || return 1
    executable_path="${app_path}/Contents/MacOS/${executable_name}"
    [[ -x "${executable_path}" ]] || return 1

    (
        cd "${target_dir}" || exit 1
        nohup "${executable_path}" "${target_dir}" >/dev/null 2>&1 &
    )
}

is_macos() {
    [[ "$(uname -s)" == "Darwin" ]]
}

is_wsl() {
    [[ -r /proc/version ]] && grep -qi microsoft /proc/version
}

date_from_epoch() {
    local epoch="$1"
    if is_macos; then
        date -r "${epoch}" '+%Y.%m.%d'
    else
        date -d "@${epoch}" '+%Y.%m.%d'
    fi
}

latest_photo_epoch() {
    # Batch stat: one find + a handful of stat processes instead of
    # two forks per file. Output is mtimes only, so newline-safe.
    local dir="$1"
    if is_macos; then
        find "${dir}" -type f -exec stat -f '%m' {} + 2>/dev/null | awk 'BEGIN{max=0} $1>max{max=$1} END{print max}'
    else
        find "${dir}" -type f -exec stat -c '%Y' {} + 2>/dev/null | awk 'BEGIN{max=0} $1>max{max=$1} END{print max}'
    fi
}

latest_folder_for_date() {
    local prefix="$1"
    local folder_path
    local folder
    local folder_epoch
    local best_folder=""
    local best_epoch=0

    [[ -d "${PHOTOS_DIR}" ]] || return 0

    while IFS= read -r folder_path; do
        folder="$(basename "${folder_path}")"
        folder_epoch="$(latest_photo_epoch "${folder_path}")"
        if (( folder_epoch > best_epoch )); then
            best_epoch="${folder_epoch}"
            best_folder="${folder}"
        fi
    done < <(find "${PHOTOS_DIR}" -mindepth 1 -maxdepth 1 -type d -name "${prefix}, *" -print 2>/dev/null | sort -r)

    printf '%s\n' "${best_folder}"
}

datetime_from_epoch() {
    local epoch="$1"
    if is_macos; then
        date -r "${epoch}" '+%Y-%m-%d %H:%M:%S'
    else
        date -d "@${epoch}" '+%Y-%m-%d %H:%M:%S'
    fi
}

file_birth_epoch() {
    local file="$1"
    local birth
    if is_macos; then
        birth="$(stat -f '%B' "${file}" 2>/dev/null || printf '0')"
    else
        birth="$(stat -c '%W' "${file}" 2>/dev/null || printf '0')"
    fi
    if [[ "${birth}" =~ ^[0-9]+$ ]] && (( birth > 0 )); then
        printf '%s\n' "${birth}"
        return
    fi
    if is_macos; then
        stat -f '%m' "${file}"
    else
        stat -c '%Y' "${file}"
    fi
}

file_size_bytes() {
    local file="$1"
    if is_macos; then
        stat -f '%z' "${file}"
    else
        stat -c '%s' "${file}"
    fi
}

available_bytes() {
    local path="$1"
    df -Pk "${path}" | awk 'NR==2 {print $4 * 1024}'
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
    # Truncate to at most avail visible cells, keeping the tail (filename).
    # Length math uses ${#}, which overcounts multibyte chars on some bash
    # builds — that only makes the line shorter, never wider, so the
    # one-line guarantee holds.
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

append_if_dir() {
    local dir="$1"
    [[ -d "${dir}" ]] && printf '%s\n' "${dir}"
}

is_cameraish_name() {
    local path="$1"
    local name
    name="$(basename "${path}")"
    [[ "${name}" =~ ^(EOS.*DIGITAL|DIGITAL.*EOS|CANON|NIKON|SONY|NO\ NAME|UNTITLED)$ ]]
}

macos_removable_mounts() {
    local dir
    local info

    for dir in /Volumes/*; do
        [[ -d "${dir}" ]] || continue
        info="$(diskutil info "${dir}" 2>/dev/null || true)"
        if [[ -n "${info}" ]] && grep -Eq '^\s*Removable Media:\s+Removable' <<< "${info}"; then
            printf '%s\n' "${dir}"
            continue
        fi

        if is_cameraish_name "${dir}" || [[ -d "${dir}/DCIM" ]]; then
            printf '%s\n' "${dir}"
        fi
    done
}

linux_removable_mounts() {
    local line
    local path=""
    local rm=""
    local hotplug=""
    local type=""
    local mountpoint=""

    if command -v lsblk >/dev/null 2>&1; then
        while IFS= read -r line; do
            eval "${line}"
            if [[ "${type}" == "part" || "${type}" == "disk" ]] && [[ -n "${mountpoint}" ]]; then
                if [[ "${rm}" == "1" || "${hotplug}" == "1" ]]; then
                    printf '%s\n' "${mountpoint}"
                fi
            fi
        done < <(lsblk -P -o PATH,RM,HOTPLUG,TYPE,MOUNTPOINT 2>/dev/null || true)
        return
    fi

    local user_name
    user_name="$(id -un)"
    for path in \
        "/run/media/${user_name}/EOS_DIGITAL" \
        "/media/${user_name}/EOS_DIGITAL" \
        "/run/media/${user_name}/CANON" \
        "/media/${user_name}/CANON"
    do
        append_if_dir "${path}"
    done
}

mount_candidates() {
    if is_macos; then
        macos_removable_mounts | sort -u
        return
    fi

    linux_removable_mounts | sort -u
}

volume_score() {
    local mount_point="$1"
    local name
    name="$(basename "${mount_point}")"

    if [[ "${name}" =~ EOS.*DIGITAL|DIGITAL.*EOS|CANON|NO\ NAME ]]; then
        printf '100\n'
        return
    fi

    if [[ -d "${mount_point}/DCIM" ]]; then
        printf '50\n'
        return
    fi

    printf '10\n'
}

find_media_files() {
    local root="$1"
    find "${root}" -type f \
        \( \
            -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.cr2' -o -iname '*.cr3' -o \
            -iname '*.nef' -o -iname '*.arw' -o -iname '*.dng' -o -iname '*.orf' -o \
            -iname '*.raf' -o -iname '*.rw2' -o -iname '*.mp4' -o -iname '*.mov' -o \
            -iname '*.avi' -o -iname '*.mts' -o -iname '*.m2ts' \
        \) -print0
}

pick_source_mount() {
    local candidate
    local chosen=()
    local labels=()
    local label

    while IFS= read -r candidate; do
        [[ -d "${candidate}" ]] || continue
        if find_media_files "${candidate}" | awk 'BEGIN{RS="\0"} NR==1 {found=1} END{exit found?0:1}'; then
            label="$(printf '%03d | %s' "$(volume_score "${candidate}")" "${candidate}")"
            labels+=("${label}")
            chosen+=("${candidate}")
        fi
    done < <(mount_candidates | sort -u)

    (( ${#chosen[@]} > 0 )) || die "no mounted flash card with photo/video files found"

    if (( ${#chosen[@]} == 1 )); then
        printf '%s\n' "${chosen[0]}"
        return
    fi

    local selection
    selection="$(gum_choose_single "Select flash volume" "${labels[@]}")"
    printf '%s\n' "${selection#* | }"
}

collect_files() {
    # Batch sizes with one xargs-driven stat run (output order matches
    # input order, one size per line) instead of three forks per file,
    # and a single sort pass for dup detection instead of an O(n^2) grep.
    local root="$1"
    local -a files=()
    local file
    local size
    local dups

    while IFS= read -r -d '' file; do
        files+=("${file}")
    done < <(find_media_files "${root}")

    (( ${#files[@]} > 0 )) || die "no media files found on ${root}"

    if is_macos; then
        printf '%s\0' "${files[@]}" | xargs -0 stat -f '%z' 2>/dev/null > "${TMP_DIR}/sizes.txt"
    else
        printf '%s\0' "${files[@]}" | xargs -0 stat -c '%s' 2>/dev/null > "${TMP_DIR}/sizes.txt"
    fi

    {
        exec 3< "${TMP_DIR}/sizes.txt"
        for file in "${files[@]}"; do
            if ! IFS= read -r size <&3; then
                size=""
            fi
            printf '%s\t%s\t%s\n' "${file}" "${file##*/}" "${size}"
        done
        exec 3<&-
    } > "${MANIFEST_FILE}"

    dups="$(cut -f2 "${MANIFEST_FILE}" | sort | uniq -d)"
    if [[ -n "${dups}" ]]; then
        die "duplicate filename on source for flat copy: $(head -n1 <<<"${dups}")"
    fi
}

first_file_epoch() {
    # One batched stat for birth+mtime of every file; awk picks
    # birthtime with mtime fallback and the minimum, same as
    # file_birth_epoch did per file.
    if is_macos; then
        cut -f1 "${MANIFEST_FILE}" | tr '\n' '\0' | xargs -0 stat -f '%B %m' 2>/dev/null | awk '{v=($1>0?$1:$2)} NR==1||v<min{min=v} END{print min+0}'
    else
        cut -f1 "${MANIFEST_FILE}" | tr '\n' '\0' | xargs -0 stat -c '%W %Y' 2>/dev/null | awk '{v=($1>0?$1:$2)} NR==1||v<min{min=v} END{print min+0}'
    fi
}

manifest_file_count() {
    awk 'END {print NR}' "${MANIFEST_FILE}"
}

internal_default_suffix() {
    local date_prefix="$1"
    local folder
    local suffix=""

    folder="$(latest_folder_for_date "${date_prefix%%, }")"
    if [[ -n "${folder}" && "${folder}" == "${date_prefix}"* ]]; then
        suffix="${folder#${date_prefix}}"
    fi
    printf '%s\n' "${suffix}"
}

choose_target_dir() {
    local prefix="$1"
    local default_suffix="${2:-}"
    local suffix
    local folder_name

    mkdir -p "${PHOTOS_DIR}"

    while true; do
        if [[ -n "${default_suffix}" ]]; then
            suffix="$(gum input --header "Folder in ~/Photos" --prompt "${prefix}" --placeholder "session name" --value "${default_suffix}")" || exit 1
        else
            suffix="$(gum input --header "Folder in ~/Photos" --prompt "${prefix}" --placeholder "session name")" || exit 1
        fi
        [[ -n "${suffix}" ]] || {
            gum_note "$(style_warn "Folder name suffix cannot be empty.")"
            continue
        }
        [[ "${suffix}" != *"/"* ]] || {
            gum_note "$(style_warn "Folder name cannot contain '/'.")"
            continue
        }
        folder_name="${prefix}${suffix}"
        printf '%s\n' "${PHOTOS_DIR}/${folder_name}"
        return
    done
}

inspect_target() {
    local target_dir="$1"
    local duplicate_count=0
    local changed_count=0
    local missing_count=0
    local source_file
    local base
    local source_size
    local target_size

    while IFS=$'\t' read -r source_file base source_size; do
        if [[ -f "${target_dir}/${base}" ]]; then
            target_size="$(file_size_bytes "${target_dir}/${base}")"
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

bytes_to_copy() {
    local target_dir="$1"
    local mode="$2"
    local source_file
    local base
    local source_size
    local total=0

    while IFS=$'\t' read -r source_file base source_size; do
        if [[ ! -f "${target_dir}/${base}" ]]; then
            total=$(( total + source_size ))
            continue
        fi

        if [[ "${mode}" == "overwrite" ]]; then
            total=$(( total + source_size ))
            continue
        fi

        if [[ "${mode}" == "update" && "${source_size}" != "$(file_size_bytes "${target_dir}/${base}")" ]]; then
            total=$(( total + source_size ))
        fi
    done < "${MANIFEST_FILE}"

    printf '%s\n' "${total}"
}

files_to_copy_count() {
    local target_dir="$1"
    local mode="$2"
    local source_file
    local base
    local source_size
    local total=0

    while IFS=$'\t' read -r source_file base source_size; do
        if [[ ! -f "${target_dir}/${base}" ]]; then
            total=$(( total + 1 ))
            continue
        fi

        if [[ "${mode}" == "overwrite" ]]; then
            total=$(( total + 1 ))
            continue
        fi

        if [[ "${mode}" == "update" && "${source_size}" != "$(file_size_bytes "${target_dir}/${base}")" ]]; then
            total=$(( total + 1 ))
        fi
    done < "${MANIFEST_FILE}"

    printf '%s\n' "${total}"
}

ensure_free_space() {
    local target_dir="$1"
    local needed="$2"
    local available
    local choice

    while true; do
        available="$(available_bytes "${target_dir}")"
        if (( available >= needed )); then
            gum_note "$(style_ok "Free space is enough.") Need $(style_info "$(format_bytes "${needed}")"), available $(style_info "$(format_bytes "${available}")")."
            return
        fi

        gum_note "$(style_warn "Not enough free space.") Need $(style_info "$(format_bytes "${needed}")"), available $(style_info "$(format_bytes "${available}")")."
        choice="$(gum_choose_single "$(style_warn "Free space check")" "Retry" "Cancel")" || exit 1
        [[ "${choice}" == "Retry" ]] || exit 1
    done
}

copy_files() {
    local target_dir="$1"
    local mode="$2"
    local source_file
    local base
    local source_size
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
    local base_disp

    total_files="$(files_to_copy_count "${target_dir}" "${mode}")"
    start_ts="$(date +%s)"

    if (( total_files == 0 )); then
        gum_note "$(style_warn "Nothing new to copy.")"
        return
    fi

    while IFS=$'\t' read -r source_file base source_size; do
        if [[ -f "${target_dir}/${base}" ]]; then
            if [[ "${mode}" == "append" ]]; then
                continue
            fi
            if [[ "${mode}" == "update" && "${source_size}" == "$(file_size_bytes "${target_dir}/${base}")" ]]; then
                continue
            fi
        fi

        copied_files=$(( copied_files + 1 ))
        rsync -a --human-readable -- "${source_file}" "${target_dir}/${base}"

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

        # Single updating line: truncate base so the visible line never
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
            base_disp="$(fit_rel "${base}" "${avail}")"
            status_line="$(printf '%s[%s/%s]%s %s%s%s  %s%3s%%%s  %s%s%s%s / %s%s%s  %s%s/s%s  %s%s%s' \
                "${COLOR_DIM}" \
                "${copied_files}" \
                "${total_files}" \
                "${COLOR_RESET}" \
                "${COLOR_BLUE}" \
                "${base_disp}" \
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
            base_disp="$(fit_rel "${base}" "${avail}")"
            status_line="$(printf '%s[%s/%s]%s %s%s%s  %s%s%s  %s%s%s' \
                "${COLOR_DIM}" \
                "${copied_files}" \
                "${total_files}" \
                "${COLOR_RESET}" \
                "${COLOR_BLUE}" \
                "${base_disp}" \
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
    if is_macos; then
        require_cmd nohup
    fi

    local first_epoch
    local date_prefix
    local target_dir
    local target_stats
    local duplicate_count
    local changed_count
    local missing_count
    local copy_mode="update"
    local needed_bytes
    local choice
    local media_count
    local first_taken_at

    local source_root
    gum_spin --spinner line --title "Searching mounted flash cards..." -- bash "$0" --internal-pick-source > "${TMP_DIR}/source_root.txt"
    source_root="$(cat "${TMP_DIR}/source_root.txt")"
    collect_files "${source_root}"

    gum_spin --spinner line --title "Reading photo dates..." -- bash "$0" --internal-first-epoch "${source_root}" > "${TMP_DIR}/first_epoch.txt"
    first_epoch="$(cat "${TMP_DIR}/first_epoch.txt")"
    media_count="$(manifest_file_count)"
    first_taken_at="$(datetime_from_epoch "${first_epoch}")"
    date_prefix="$(date_from_epoch "${first_epoch}"), "

    gum_spin --spinner line --title "Matching existing folder in ~/Photos..." -- bash "$0" --internal-default-suffix "${date_prefix}" > "${TMP_DIR}/default_suffix.txt"

    gum_note "Found flash media at $(style_path "${source_root}") | $(style_info "${media_count} files") | first shot $(style_info "${first_taken_at}")"

    target_dir="$(choose_target_dir "${date_prefix}" "$(cat "${TMP_DIR}/default_suffix.txt")")"
    mkdir -p "${target_dir}"

    gum_spin --spinner line --title "Checking existing files..." -- bash "$0" --internal-inspect-target "${source_root}" "${target_dir}" > "${TMP_DIR}/target_stats.txt"
    target_stats="$(cat "${TMP_DIR}/target_stats.txt")"
    IFS=';' read -r duplicate_count changed_count missing_count <<< "${target_stats}"

    if (( duplicate_count > 0 || changed_count > 0 )); then
        gum_note "Target already contains $(style_info "${duplicate_count} identical files"), $(style_warn "${changed_count} changed files"), $(style_ok "${missing_count} new files")."
        if (( changed_count > 0 )); then
            choice="$(gum_choose_single "$(style_warn "Files already exist")" "Overwrite" "Cancel")" || exit 1
        else
            choice="$(gum_choose_single "$(style_warn "Files already exist")" "Append" "Overwrite" "Cancel")" || exit 1
        fi
        case "${choice}" in
            Append)
                copy_mode="append"
                ;;
            Overwrite)
                copy_mode="overwrite"
                ;;
            *)
                exit 1
                ;;
        esac
    else
        gum_note "Existing folder check: $(style_warn "${changed_count} changed files"), $(style_ok "${missing_count} new files")."
    fi

    gum_spin --spinner line --title "Calculating required space..." -- bash "$0" --internal-bytes-to-copy "${source_root}" "${target_dir}" "${copy_mode}" > "${TMP_DIR}/needed_bytes.txt"
    needed_bytes="$(cat "${TMP_DIR}/needed_bytes.txt")"
    TOTAL_BYTES_TO_COPY="${needed_bytes}"
    ensure_free_space "${target_dir}" "${needed_bytes}"
    copy_files "${target_dir}" "${copy_mode}"
    remember_target_dir "${target_dir}"
    gum_note "$(style_ok "Copy complete:") $(style_path "${target_dir}")"

    if can_open_photomechanic; then
        if gum_confirm "$(style_warn "Open copied folder in Photo Mechanic?")"; then
            open_in_photomechanic "${target_dir}"
        fi
    fi
}

if [[ "${1:-}" == "--internal-pick-source" ]]; then
    pick_source_mount
    exit 0
fi

if [[ "${1:-}" == "--internal-default-suffix" ]]; then
    internal_default_suffix "$2"
    exit 0
fi

if [[ "${1:-}" == "--internal-first-epoch" ]]; then
    collect_files "$2"
    first_file_epoch
    exit 0
fi

if [[ "${1:-}" == "--internal-inspect-target" ]]; then
    collect_files "$2"
    inspect_target "$3"
    exit 0
fi

if [[ "${1:-}" == "--internal-bytes-to-copy" ]]; then
    collect_files "$2"
    bytes_to_copy "$3" "$4"
    exit 0
fi

if [[ "${1:-}" == "--last-target-dir" ]]; then
    print_last_target_dir
    exit 0
fi

main "$@"
