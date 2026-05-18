#!/bin/bash
# recolor-icons.sh — Recolor SVG icons to match theme
# Usage: recolor-icons.sh [color]
# Example: recolor-icons.sh "#8B5CF6"

ICON_DIR="$HOME/.icons/superlite/scalable"
COLOR="${1:-#8B5CF6}"

if [ ! -d "$ICON_DIR" ]; then
    echo "Icon dir not found: $ICON_DIR"
    exit 1
fi

echo "Recoloring SVGs in $ICON_DIR to $COLOR..."

find "$ICON_DIR" -name "*.svg" | while read f; do
    # Replace common fill colors with new color
    sed -i \
        -e "s/fill=\"#8B5CF6\"/fill=\"$COLOR\"/g" \
        -e "s/fill=\"#7C3AED\"/fill=\"$COLOR\"/g" \
        -e "s/fill=\"#6D28D9\"/fill=\"$COLOR\"/g" \
        "$f"
done

echo "Done. Restart Thunar to see changes."
