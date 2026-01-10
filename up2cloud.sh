#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

viewing_dir='1. Для просмотра и интернета'
printing_dir='2. Для печати и дизайна'
cloud=mailru
skip_cloud_dirs='^WPJA.com_Pics|^Мастер-классы|^Разное|^ПФ|^Копии|^Backups|^Calls'

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

regenerate_thumbnail=true
vpn_services_to_restart=""
caffeinate_pid=""

log_info() { echo -e "${GREEN}$*${NC}" >&2; }
log_warn() { echo -e "${YELLOW}$*${NC}" >&2; }
log_error() { echo -e "${RED}$*${NC}" >&2; }

check_command() {
    command -v "$1" >/dev/null 2>&1 || {
        if [[ -n "${2:-}" ]]; then
            log_error "$1 is not installed. You can install it using Homebrew with: brew install $2"
        else
            log_error "$1 is not installed."
        fi
        exit 1
    }
}

preflight() {
    echo -e ""
    declare -A commands=(
        [magick]="imagemagick"
        [rclone]="rclone"
        [gum]="gum"
        [scutil]=""
        [caffeinate]=""
        [pbcopy]=""
        [pbpaste]=""
        [curl]="curl"
        [afplay]=""
    )
    for cmd in "${!commands[@]}"; do
        check_command "$cmd" "${commands[$cmd]}"
    done

    if [[ ! -x ~/veter_scripts/goresize ]]; then
        log_error "Custom script goresize not found or not executable. Please download it from github.com/pavelveter"
        exit 1
    fi

    if [[ ! -x ~/veter_scripts/imgcat ]]; then
        log_error "Custom script imgcat not found or not executable. Please download it from github.com/pavelveter"
        exit 1
    fi

    if ! rclone listremotes | grep -q "^${cloud}:"; then
        log_error "rclone is not configured with remote ${cloud}. Configure with rclone config."
        exit 1
    fi

    if [[ -z "${TG_API:-}" || -z "${TG_CHAT:-}" ]]; then
        log_error "Telegram environment variables TG_API and TG_CHAT must be set."
        exit 1
    fi
}

prompt_thumbnail_action() {
    if [[ -f thumbnail.jpg ]]; then
        if ! choice=$(printf '%s\n' "Overwrite" "Keep existing" | gum choose --header "thumbnail.jpg exists. Overwrite?"); then
            log_error "Selection cancelled."
            exit 1
        fi
        if [[ "${choice}" == "Keep existing" ]]; then
            regenerate_thumbnail=false
            log_warn "Keeping existing thumbnail.jpg"
        else
            log_warn "Will overwrite thumbnail.jpg"
        fi
    fi
}

ensure_source_images() {
    if ! find . -maxdepth 1 -type f -name "*.jpg" ! -name "thumbnail.jpg" | grep -q .; then
        if [[ -d "${printing_dir}" ]] && find "${printing_dir}" -type f -name "*.jpg" | grep -q .; then
            log_warn "No .jpg files found in the current directory, but found in ${printing_dir}."
        else
            log_error "No .jpg files found in the current directory and in ${printing_dir}. Exiting."
            read -rp "Press Enter to continue or Ctrl-C to exit"
        fi
    fi

    mkdir -p "${printing_dir}"
    find . -maxdepth 1 -type f -name "*.jpg" ! -name "thumbnail.jpg" -exec mv {} "${printing_dir}/" \;
}

choose_remote() {
    local remotes_output remotes rem_dir loc_dir
    loc_dir=$(basename "$(pwd)")
    if [[ $# -eq 0 ]]; then
        remotes_output=$(rclone lsf "${cloud}:" --dirs-only --format p | sed 's:/$::' | grep -v -E "${skip_cloud_dirs}" || true)
        if [[ -z "${remotes_output}" ]]; then
            log_error "No remote directories found on ${cloud} after filtering."
            exit 1
        fi
        mapfile -t remotes <<< "${remotes_output}"
        echo -e "\nPlease, select the directory to upload" >&2
        if ! rem_dir=$(printf '%s\n' "${remotes[@]}" | gum choose --header "Remote directories on ${cloud}" --limit 1); then
            log_error "Selection cancelled."
            exit 1
        fi
        echo -e "${GREEN}" >&2
        read -rp "Press ENTER to upload to ${cloud}:/${rem_dir}/${loc_dir}" >&2
        echo -e "${NC}" >&2
    else
        rem_dir="$1"
        if ! rclone lsd "${cloud}:/${rem_dir}" &>/dev/null; then
            log_error "Remote directory ${rem_dir} does not exist. Exiting."
            exit 1
        fi
    fi
    printf '%s\n' "${rem_dir}"
}

get_file_list() {
    if [[ ! -d "$1" ]]; then
        mkdir -p "$1"
    fi
    find "$1" -maxdepth 1 -type f -name "*.jpg" -exec basename {} \; | sort
}

maybe_resize() {
    local viewing_files printing_files
    viewing_files=$(get_file_list "${viewing_dir}")
    printing_files=$(get_file_list "${printing_dir}")
    if [[ "${viewing_files}" != "${printing_files}" ]]; then
        log_info "Making little copies of the images for fast view..."
        ~/veter_scripts/goresize -c 79 -h 2000 -w 2000 -i "${printing_dir}" -o "${viewing_dir}"
    else
        log_warn "File lists in ${viewing_dir} and ${printing_dir} are identical. Skipping resize.\n"
    fi
}

build_thumbnail() {
    log_info "Making preview image..."
    mapfile -t files < <(find "${viewing_dir}" -maxdepth 1 -type f -name "*.jpg" | awk 'BEGIN {srand()} {print rand(), $0}' | sort -n | cut -d' ' -f2- | head -n 10)
    if [[ ${#files[@]} -eq 0 ]]; then
        log_warn "No images in ${viewing_dir} to build preview. Skipping thumbnail."
    elif [[ "${regenerate_thumbnail}" == true ]]; then
        gum spin --spinner pulse --title "Building thumbnail..." -- magick montage "${files[@]}" -geometry "236x311^>" -gravity center -extent 236x311 -tile 5x2 -background white -bordercolor white -border 2 thumbnail.jpg
        ~/veter_scripts/imgcat -W 600px thumbnail.jpg
    else
        log_warn "Reusing existing thumbnail.jpg"
    fi
}

cleanup_dsstore() {
    find . -name ".DS_Store" -delete
}

vpn_active() {
    local list_output service status
    list_output=$(scutil --nc list 2>/dev/null || true)
    if printf '%s\n' "${list_output}" | grep -Eiq '\((Connected|Connecting|Подключено|Соединено)\)'; then
        return 0
    fi
    while IFS= read -r service; do
        status=$(scutil --nc status "${service}" 2>/dev/null || true)
        if printf '%s\n' "${status}" | grep -Eiq 'Connected|Connecting|Подключено|Соединено'; then
            return 0
        fi
    done < <(printf '%s\n' "${list_output}" | sed -n 's/.*"\([^"]\+\)".*/\1/p')
    if ifconfig 2>/dev/null | grep -q '^utun[0-9]\+'; then
        return 0
    fi
    return 1
}

get_connected_vpn_services() {
    scutil --nc list 2>/dev/null | awk '/\((Connected|Connecting|Подключено|Соединено)\)/ {for(i=1;i<=NF;i++){if($i ~ /\".*\"/){gsub(/"/, "", $i); print $i}}}'
}

stop_vpn_service() {
    scutil --nc stop "$1" >/dev/null 2>&1 || true
}

start_vpn_service() {
    scutil --nc start "$1" >/dev/null 2>&1 || true
}

maybe_toggle_vpn() {
    if vpn_active; then
        local connected_vpns
        connected_vpns=$(get_connected_vpn_services || true)
        if gum confirm "VPN is connected. Turn it off for upload and restore afterwards?"; then
            vpn_services_to_restart="${connected_vpns}"
            while IFS= read -r svc; do
                [[ -z "${svc}" ]] && continue
                log_warn "Stopping VPN: ${svc}"
                stop_vpn_service "${svc}"
            done <<< "${connected_vpns}"
        else
            log_warn "VPN is currently connected (detected via scutil). Upload may be slower or blocked. Press any key to continue, or Ctrl-C to abort."
            read -r -n 1 -s
            echo
        fi
    fi
}

start_caffeinate() {
    caffeinate -dimsu >/dev/null 2>&1 &
    caffeinate_pid=$!
}

stop_caffeinate() {
    if [[ -n "${caffeinate_pid}" ]]; then
        kill "${caffeinate_pid}" 2>/dev/null || true
        caffeinate_pid=""
    fi
}

restore_vpn_if_needed() {
    if [[ -n "${vpn_services_to_restart}" ]]; then
        while IFS= read -r svc; do
            [[ -z "${svc}" ]] && continue
            log_warn "Starting VPN: ${svc}"
            start_vpn_service "${svc}"
        done <<< "${vpn_services_to_restart}"
    fi
}

cleanup() {
    stop_caffeinate
    restore_vpn_if_needed
}

ensure_remote_dirs() {
    local rem_dir loc_dir
    rem_dir="$1"
    loc_dir="$2"
    log_info "Checking and creating remote directories if not exists..."
    if ! rclone lsd "${cloud}:/${rem_dir}/${loc_dir}" &>/dev/null; then
        rclone mkdir "${cloud}:/${rem_dir}/${loc_dir}" || { log_error "Failed to create main remote directory"; exit 1; }
    fi
    if ! rclone lsd "${cloud}:/${rem_dir}/${loc_dir}/${viewing_dir}" &>/dev/null; then
        rclone mkdir "${cloud}:/${rem_dir}/${loc_dir}/${viewing_dir}" || { log_error "Failed to create viewing directory"; exit 1; }
    fi
    if ! rclone lsd "${cloud}:/${rem_dir}/${loc_dir}/${printing_dir}" &>/dev/null; then
        rclone mkdir "${cloud}:/${rem_dir}/${loc_dir}/${printing_dir}" || { log_error "Failed to create printing directory"; exit 1; }
    fi
}

sync_to_cloud() {
    local rem_dir loc_dir
    rem_dir="$1"
    loc_dir="$2"
    log_info "Syncing..."
    rclone sync "${viewing_dir}/" "${cloud}:/${rem_dir}/${loc_dir}/${viewing_dir}" --progress --transfers=20 || { log_error "Failed to sync viewing directory"; exit 1; }
    rclone sync "${printing_dir}/" "${cloud}:/${rem_dir}/${loc_dir}/${printing_dir}" --progress --transfers=20 || { log_error "Failed to sync printing directory"; exit 1; }
}

share_and_notify() {
    local rem_dir loc_dir link
    rem_dir="$1"
    loc_dir="$2"
    log_info "Getting link..."
    link=$(rclone link "${cloud}:/${rem_dir}/${loc_dir}" | sed 's|https://cloud.mail.ru/public/|pavelveter.com/x/|g') || { log_error "Failed to get link"; exit 1; }
    printf '%s' "${link}" | pbcopy || { log_error "Failed to copy link"; exit 1; }
    echo -e "\nLink:\e[92m ${link} \e[39m.\n"

    curl --silent -X POST "https://api.telegram.org/bot${TG_API}/sendPhoto" \
         -F "chat_id=${TG_CHAT}" \
         -F "photo=@thumbnail.jpg" \
         --form-string "caption=${loc_dir}, фотографии готовы, вот ссылка: ${link}" \
         -F "disable_notification=true" > /dev/null 2>&1 || { log_error "Failed to send link to Telegram"; exit 1; }

    afplay /System/Library/Sounds/Submarine.aiff || { log_error "Failed to play sound"; exit 1; }
}

main() {
    preflight
    prompt_thumbnail_action
    ensure_source_images

    loc_dir=$(basename "$(pwd)")
    rem_dir=$(choose_remote "$@")

    maybe_resize
    build_thumbnail
    cleanup_dsstore
    maybe_toggle_vpn

    start_caffeinate
    trap cleanup EXIT

    ensure_remote_dirs "${rem_dir}" "${loc_dir}"
    sync_to_cloud "${rem_dir}" "${loc_dir}"

    cleanup
    trap - EXIT

    share_and_notify "${rem_dir}" "${loc_dir}"
}

main "$@"
