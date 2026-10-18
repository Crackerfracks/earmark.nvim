#!/bin/sh
# contact sheet of a clip's frames, for reviewing a recording: sheet.sh CLIP [OUT.png]
d=${EARMARK_DEMOS_DIR:-/tmp/earmark-demos}/frames/$1
magick montage "$d"/[0-9]*.png -tile 3x -geometry 600x384+4+4 -background '#333' "${2:-$d/../$1-sheet.png}"
