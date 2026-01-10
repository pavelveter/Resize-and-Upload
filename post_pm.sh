#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob nocaseglob

photo_exts=(cr2 cr3 arw dng nef raf orf rw2 srw pef raw rwl mos mdc mef mrw dcr kdc erf srf x3f crw crw2 tif tiff jpg jpeg heic heif png webp)
have_file_cmd=true
if ! command -v file >/dev/null 2>&1; then
    have_file_cmd=false
fi

current_dir_name="${PWD##*/}"
selected_dir="+ ${current_dir_name}"
rejected_dir="- ${current_dir_name}"

mkdir -p "${selected_dir}" "${rejected_dir}"

xmp_files=( *.XMP )
if (( ${#xmp_files[@]} == 0 )); then
    echo "No XMP files found, nothing to do."
    exit 0
fi

for xmp in "${xmp_files[@]}"; do
    color_class=$(awk -F '=' '/photomechanic:ColorClass=/ {gsub(/"/,"",$2); print $2; exit}' "${xmp}")
    if [[ "${color_class:-0}" -ne 1 ]]; then
        continue
    fi

    base="${xmp%.XMP}"
    moved_any=false

    for ext in "${photo_exts[@]}"; do
        for candidate in "${base}.${ext}"; do
            [[ -f "${candidate}" ]] || continue
            mv "${candidate}" "${selected_dir}"
            moved_any=true
        done
    done

    if [[ "${have_file_cmd}" == true ]]; then
        for candidate in "${base}".*; do
            [[ "${candidate}" == "${xmp}" ]] && continue
            [[ -f "${candidate}" ]] || continue
            mime_type=$(file -b --mime-type "${candidate}" || true)
            if [[ "${mime_type}" == image/* ]]; then
                mv "${candidate}" "${selected_dir}"
                moved_any=true
            fi
        done
    fi

    if [[ "${moved_any}" == false ]]; then
        echo "Warning: no photo files found for ${xmp}" >&2
    fi

    mv "${xmp}" "${selected_dir}"
done

if compgen -G 'IMG_*' > /dev/null; then
    mv IMG_* "${rejected_dir}"
fi

# Uncomment if you want XMP files removed after processing
# find . -name "*.XMP" -delete
