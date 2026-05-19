#!/bin/sh
# recolor-icons.sh — Recolor SVG icons and convert to PNG
# Usage: recolor-icons.sh [accent-color]
# Default accent: #22AA99 (SuperLite teal)

ICON_DIR="$HOME/.icons/superlite/scalable"
PNG_DIR="$HOME/.icons/superlite/48x48"
ACCENT="${1:-#22AA99}"

# Derived colors (lighter/darker variants)
# Teal palette: accent=#22AA99, light=#5EEAD4, dark=#0F766E, muted=#94A3B8
LIGHT=$(echo "$ACCENT" | sed 's/#\(..\)\(..\)\(..\)/printf "#%02x%02x%02x" $((0x\1+60>255?255:0x\1+60)) $((0x\2+60>255?255:0x\2+60)) $((0x\3+60>255?255:0x\3+60))/e' 2>/dev/null || echo "#5EEAD4")
DARK=$(echo "$ACCENT" | sed 's/#\(..\)\(..\)\(..\)/printf "#%02x%02x%02x" $((0x\1-30<0?0:0x\1-30)) $((0x\2-30<0?0:0x\2-30)) $((0x\3-30<0?0:0x\3-30))/e' 2>/dev/null || echo "#0F766E")

if [ ! -d "$ICON_DIR" ]; then
    echo "Icon dir not found: $ICON_DIR"
    exit 1
fi

echo "Recoloring SVGs in $ICON_DIR (accent=$ACCENT)..."

# Recolor folder icons to use accent color
find "$ICON_DIR/places" -name "*.svg" 2>/dev/null | while read f; do
    sed -i \
        -e "s/fill=\"#8B5CF6\"/fill=\"$ACCENT\"/g" \
        -e "s/fill=\"#7C3AED\"/fill=\"$DARK\"/g" \
        -e "s/fill=\"#6D28D9\"/fill=\"$DARK\"/g" \
        -e "s/fill=\"#A78BFA\"/fill=\"$LIGHT\"/g" \
        -e "s/fill=\"#34D399\"/fill=\"$ACCENT\"/g" \
        -e "s/fill=\"#10B981\"/fill=\"$DARK\"/g" \
        -e "s/fill=\"#60A5FA\"/fill=\"$ACCENT\"/g" \
        -e "s/fill=\"#3B82F6\"/fill=\"$DARK\"/g" \
        -e "s/fill=\"#F87171\"/fill=\"$ACCENT\"/g" \
        -e "s/fill=\"#EF4444\"/fill=\"$DARK\"/g" \
        -e "s/fill=\"#F472B6\"/fill=\"$ACCENT\"/g" \
        -e "s/fill=\"#EC4899\"/fill=\"$DARK\"/g" \
        -e "s/fill=\"#FBBF24\"/fill=\"$ACCENT\"/g" \
        -e "s/fill=\"#F59E0B\"/fill=\"$DARK\"/g" \
        "$f"
done

# Recolor mimetype icons
find "$ICON_DIR/mimetypes" -name "*.svg" 2>/dev/null | while read f; do
    sed -i \
        -e "s/fill=\"#D1FAE5\"/fill=\"#CCFBF1\"/g" \
        -e "s/fill=\"#A7F3D0\"/fill=\"#99F6E4\"/g" \
        -e "s/fill=\"#10B981\"/fill=\"$ACCENT\"/g" \
        -e "s/fill=\"#DDD6FE\"/fill=\"#CCFBF1\"/g" \
        -e "s/fill=\"#C4B5FD\"/fill=\"#99F6E4\"/g" \
        -e "s/fill=\"#8B5CF6\"/fill=\"$ACCENT\"/g" \
        -e "s/fill=\"#FDE68A\"/fill=\"#CCFBF1\"/g" \
        -e "s/fill=\"#FCD34D\"/fill=\"#99F6E4\"/g" \
        -e "s/fill=\"#F59E0B\"/fill=\"$ACCENT\"/g" \
        -e "s/fill=\"#E2E8F0\"/fill=\"#F0FDFA\"/g" \
        -e "s/fill=\"#CBD5E1\"/fill=\"#CCFBF1\"/g" \
        -e "s/fill=\"#94A3B8\"/fill=\"$DARK\"/g" \
        -e "s/fill=\"#FECACA\"/fill=\"#CCFBF1\"/g" \
        -e "s/fill=\"#FCA5A5\"/fill=\"#99F6E4\"/g" \
        -e "s/fill=\"#EF4444\"/fill=\"$ACCENT\"/g" \
        "$f"
done

# Convert SVGs to PNGs
echo "Converting SVGs to PNG..."
mkdir -p "$PNG_DIR"/{actions,devices,mimetypes,places}

if command -v rsvg-convert >/dev/null 2>&1; then
    for subdir in actions devices mimetypes places; do
        [ -d "$ICON_DIR/$subdir" ] || continue
        mkdir -p "$PNG_DIR/$subdir"
        for svg in "$ICON_DIR/$subdir"/*.svg; do
            [ -f "$svg" ] || continue
            name=$(basename "$svg" .svg)
            rsvg-convert -w 48 -h 48 "$svg" -o "$PNG_DIR/$subdir/$name.png" 2>/dev/null && \
                echo "  $subdir/$name.png" || echo "  WARN: failed $svg"
        done
    done
elif command -v convert >/dev/null 2>&1; then
    for subdir in actions devices mimetypes places; do
        [ -d "$ICON_DIR/$subdir" ] || continue
        mkdir -p "$PNG_DIR/$subdir"
        for svg in "$ICON_DIR/$subdir"/*.svg; do
            [ -f "$svg" ] || continue
            name=$(basename "$svg" .svg)
            convert -background none -resize 48x48 "$svg" "$PNG_DIR/$subdir/$name.png" 2>/dev/null && \
                echo "  $subdir/$name.png" || echo "  WARN: failed $svg"
        done
    done
else
    echo "WARN: Neither rsvg-convert nor convert found. Skipping PNG conversion."
    echo "Install librsvg or imagemagick for SVG->PNG conversion."
fi

echo "Done. Restart Thunar/file manager to see changes."
