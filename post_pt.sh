#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob nocaseglob

jpeg_dir="JPEG"
jpeg_ignored_file="${jpeg_dir}/.DS_Store"

if [[ ! -d "${jpeg_dir}" ]]; then
    echo "Directory ${jpeg_dir} not found." >&2
    exit 1
fi

rm -f "${jpeg_ignored_file}"

current_files=( *.jpg *.jpeg )
jpeg_files=( "${jpeg_dir}"/*.jpg "${jpeg_dir}"/*.jpeg )

if (( ${#current_files[@]} == 0 )); then
    echo "No JPG files found in the current directory." >&2
    exit 1
fi

if (( ${#jpeg_files[@]} == 0 )); then
    echo "No JPG files found in ${jpeg_dir}." >&2
    exit 1
fi

mapfile -t current_names_sorted < <(printf '%s\n' "${current_files[@]}" | LC_ALL=C sort)
mapfile -t jpeg_names_sorted < <(
    for path in "${jpeg_files[@]}"; do
        basename "${path}"
    done | LC_ALL=C sort
)

missing_in_jpeg=()
for file in "${current_names_sorted[@]}"; do
    if [[ ! -f "${jpeg_dir}/${file}" ]]; then
        missing_in_jpeg+=( "${file}" )
    fi
done

missing_in_current=()
for file in "${jpeg_names_sorted[@]}"; do
    if [[ ! -f "${file}" ]]; then
        missing_in_current+=( "${file}" )
    fi
done

if (( ${#missing_in_jpeg[@]} > 0 || ${#missing_in_current[@]} > 0 )); then
    echo "JPG file lists do not match between the current directory and ${jpeg_dir}." >&2
    if (( ${#missing_in_jpeg[@]} > 0 )); then
        echo "Missing in ${jpeg_dir}:" >&2
        printf '%s\n' "${missing_in_jpeg[@]}" >&2
    fi
    if (( ${#missing_in_current[@]} > 0 )); then
        echo "Missing in current directory:" >&2
        printf '%s\n' "${missing_in_current[@]}" >&2
    fi
    exit 1
fi

mv -f "${jpeg_files[@]}" .
rmdir "${jpeg_dir}"
