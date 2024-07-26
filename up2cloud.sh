#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

viewing_dir='1. Для просмотра и интернета'
printing_dir='2. Для печати и дизайна'
cloud=mailru
skip_cloud_dirs='^WPJA.com_Pics|^Мастер-классы|^Разное|^ПФ|^Копии'

# Define color codes
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e ""

# Function to check for a command and provide installation instructions if not found
check_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo -e "${RED}$1 is not installed. You can install it using Homebrew with: brew install $2${NC}"
        exit 1
    }
}

# List of required commands and their installation instructions
declare -A commands=(
    [magick]="imagemagick"
    [rclone]="rclone"
)

# Check for required commands
for cmd in "${!commands[@]}"; do
    if [[ -n "${commands[$cmd]}" ]]; then
        check_command "$cmd" "${commands[$cmd]}"
    fi
done

# Check if the custom goresize script exists
if [[ ! -x ~/veter_scripts/goresize ]]; then
    echo -e "${RED}Custom script goresize not found or not executable. Please download it from github.com/pavelveter${NC}"
    exit 1
fi

if ! rclone listremotes | grep -q "^${cloud}:"; then
    echo -e "${RED}rclone is not configured with remote ${cloud}. Configure with rclone config.${NC}"
    exit 1
fi

# Check for the presence of .jpg files in the current directory, excluding thumbnail.jpg
if ! find . -maxdepth 1 -type f -name "*.jpg" ! -name "thumbnail.jpg" | grep -q .; then
    # Check if the printing directory exists and contains .jpg files
    if [[ -d "${printing_dir}" ]] && find "${printing_dir}" -type f -name "*.jpg" | grep -q .; then
        echo -e "${YELLOW}No .jpg files found in the current directory, but found in ${printing_dir}.${NC}"
    else
        echo -e "${RED}No .jpg files found in the current directory and in ${printing_dir}. Exiting.${NC}"
        exit 1
    fi
fi

# Create the printing directory and move files
mkdir -p "${printing_dir}"
find . -maxdepth 1 -type f -name "*.jpg" ! -name "thumbnail.jpg" -exec mv {} "${printing_dir}/" \;

loc_dir=$(basename "$(pwd)")

# Check for command line parameters
if [[ $# -eq 0 ]]; then
    # Get the list of directories on the remote server
    remotes_output=$(rclone lsd "${cloud}:" | cut -c44- | grep -v -E "${skip_cloud_dirs}")

    # Initialize array
    remotes=()

    # Fill the array with lines
    while IFS= read -r line; do
        remotes+=("$line")
    done <<< "$remotes_output"

    echo -e "\nPlease, select the directory to upload"

    # Display the list of directories for selection
    select rem_dir in "${remotes[@]}"; do
        if [[ -z ${rem_dir} ]]; then
            echo -e "${YELLOW}You entered the wrong number, please try again${NC}"
        else
            break
        fi
    done

    echo -e "${GREEN}"
    read -rp "Press ENTER to upload to ${cloud}:/${rem_dir}/${loc_dir}"
    echo -e "${NC}"

else
    rem_dir="$1"
    
    # Check if the specified directory exists on the remote server
    if ! rclone lsd "${cloud}:/${rem_dir}" &>/dev/null; then
        echo -e "${RED}Remote directory ${rem_dir} does not exist. Exiting.${NC}"
        exit 1
    fi
fi

# Function to get the list of files in a directory
get_file_list() {
    if [[ ! -d "$1" ]]; then
        echo -e "${RED}$1 not found${NC}"
        return
    fi
    find "$1" -maxdepth 1 -type f -name "*.jpg" | cut -d/ -f2 | sort
}

# Get the list of files in both directories
viewing_files=$(get_file_list "${viewing_dir}")
printing_files=$(get_file_list "${printing_dir}")

# Compare the lists of files
if [[ "${viewing_files}" != "${printing_files}" ]]; then
    echo -e "${GREEN}Making little copies of the images for fast view...${NC}"
    ~/veter_scripts/goresize -c 79 -h 1920 -w 1920 -i "${printing_dir}" -o "${viewing_dir}"
else
    echo -e "${YELLOW}File lists in ${viewing_dir} and ${printing_dir} are identical. Skipping resize.${NC}\n"
fi

echo -e "${GREEN}Making preview image...${NC}"
mapfile -t files < <(find "${viewing_dir}" -maxdepth 1 -type f -name "*.jpg" | awk 'BEGIN {srand()} {print rand(), $0}' | sort -n | cut -d' ' -f2- | head -n 10)
magick montage "${files[@]}" -geometry '236x311^>' -gravity center -extent 236x311 -tile 5x2 -background white -bordercolor white -border 2 thumbnail.jpg
~/veter_scripts/imgcat -W 600px thumbnail.jpg

find . -name ".DS_Store" -delete

# Check and create remote directories if they do not exist
echo -e "${GREEN}Checking and creating remote directories if not exists...${NC}"
if ! rclone lsd "${cloud}:/${rem_dir}/${loc_dir}" &>/dev/null; then
    rclone mkdir "${cloud}:/${rem_dir}/${loc_dir}" || { echo -e "${RED}Failed to create main remote directory${NC}"; exit 1; }
fi

if ! rclone lsd "${cloud}:/${rem_dir}/${loc_dir}/${viewing_dir}" &>/dev/null; then
    rclone mkdir "${cloud}:/${rem_dir}/${loc_dir}/${viewing_dir}" || { echo -e "${RED}Failed to create viewing directory${NC}"; exit 1; }
fi

if ! rclone lsd "${cloud}:/${rem_dir}/${loc_dir}/${printing_dir}" &>/dev/null; then
    rclone mkdir "${cloud}:/${rem_dir}/${loc_dir}/${printing_dir}" || { echo -e "${RED}Failed to create printing directory${NC}"; exit 1; }
fi

echo -e "${GREEN}Syncing...${NC}"
rclone sync "${viewing_dir}/" "${cloud}:/${rem_dir}/${loc_dir}/${viewing_dir}" --progress --transfers=20 || { echo -e "${RED}Failed to sync viewing directory${NC}"; exit 1; }
rclone sync "${printing_dir}/" "${cloud}:/${rem_dir}/${loc_dir}/${printing_dir}" --progress --transfers=20 || { echo -e "${RED}Failed to sync printing directory${NC}"; exit 1; }

echo -e "${GREEN}Getting link...${NC}"
rclone link "${cloud}:/${rem_dir}/${loc_dir}" | sed 's|https://cloud.mail.ru/public/|pavelveter.com/x/|g' | pbcopy || { echo -e "${RED}Failed to get link${NC}"; exit 1; }

echo -e "\nLink:\e[92m $(pbpaste) \e[39m.\n"

curl --silent -X POST "https://api.telegram.org/bot${TG_API}/sendPhoto" \
     -F "chat_id=${TG_CHAT}" \
     -F "photo=@thumbnail.jpg" \
     -F "caption=${loc_dir}, фотографии готовы, вот ссылка: $(pbpaste)" \
     -F "disable_notification=true" > /dev/null 2>&1 || { echo -e "${RED}Failed to send link to Telegram${NC}"; exit 1; }

afplay /System/Library/Sounds/Submarine.aiff || { echo -e "${RED}Failed to play sound${NC}"; exit 1; }
