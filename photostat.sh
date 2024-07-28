#!/usr/bin/env bash

# Path to the folder with images
directory="1. Для просмотра и интернета"

# Extract creation date, camera model, and lens model for all images
exif_data=$(exiftool -T -createdate -model -lensmodel -filename "$directory"/*.jpg | sort)

# Get creation date and time of the first and last image
first_image=$(echo "$exif_data" | head -n 1 | awk -F'\t' '{print $1}')
last_image=$(echo "$exif_data" | tail -n 1 | awk -F'\t' '{print $1}')
camera_models=$(echo "$exif_data" | awk -F'\t' '{print $2}' | sort | uniq)
lenses=$(echo "$exif_data" | awk -F'\t' '{print $3}' | sort | uniq)

# Replace colons with dots in dates and preserve colons in time
first_image_date=$(echo "$first_image" | awk '{print $1}' | sed 's/:/./g')
first_image_time=$(echo "$first_image" | awk '{print $2}')
last_image_date=$(echo "$last_image" | awk '{print $1}' | sed 's/:/./g')
last_image_time=$(echo "$last_image" | awk '{print $2}')

# Conditional date-time display
if [[ "$first_image_date" == "$last_image_date" ]]; then
    echo "Shooting was at       ${first_image_date}, from ${first_image_time} to ${last_image_time}"
else
    echo "Shooting was at       from ${first_image_date}, ${first_image_time} to ${last_image_date}, ${last_image_time}"
fi

# Convert dates to UNIX time format
first_time=$(date -j -f "%Y.%m.%d %H:%M:%S" "${first_image_date} ${first_image_time}" "+%s" 2>/dev/null)
last_time=$(date -j -f "%Y.%m.%d %H:%M:%S" "${last_image_date} ${last_image_time}" "+%s" 2>/dev/null)

# Check if date conversion was successful
if [[ -z "$first_time" || -z "$last_time" ]]; then
    echo "Failed to parse dates. Ensure that the dates are in the correct format."
    exit 1
fi

# Calculate duration in minutes
duration=$(( (last_time - first_time) / 60 ))

# Count number of files
num_files=$(find "$directory" -maxdepth 1 -type f -name "*.jpg" | wc -l | xargs)

# Calculate frames per minute with floating-point precision
if [[ $duration -gt 0 ]]; then
    # Use bc for floating-point division
    frames_per_minute=$(echo "scale=2; $num_files / $duration" | bc)
    echo "Duration of shooting: $duration minutes"
    echo "Number of jpgs:       $num_files"
    echo "Frames per minute:    $frames_per_minute"
else
    echo "Duration is zero or less. Cannot calculate frames per minute."
fi

# Print camera models and lenses
echo -e "\nCameras used:"
echo "$camera_models"

echo -e "\nLenses used:"
echo "$lenses"

# Calculate the time passed since the last photo was taken
current_time=$(date "+%s")
time_since_shooting=$((current_time - last_time))
days_since=$((time_since_shooting / 86400))
hours_since=$(( (time_since_shooting % 86400) / 3600 ))

echo -e "\nTime passed since the last photo was taken: $days_since days and $hours_since hours."
