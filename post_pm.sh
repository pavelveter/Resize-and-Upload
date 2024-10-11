#!/bin/bash

mkdir +
mkdir -

for i in *.XMP; do
    if (( 1 == $(awk -F '[=]' '/photomechanic:ColorClass=/ {print $2}' "${i}" | tr -d '"') )); then
        mv "${i%.*}".CR2 +; mv "${i}" +;
    fi;
done

mv IMG_* -/

mv - "- $(pwd | grep -o '[^/]*$')"
mv + "+ $(pwd | grep -o '[^/]*$')"

#find . -name "*.XMP" -delete
