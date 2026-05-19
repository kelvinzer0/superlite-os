#!/bin/sh
# wallpaper-fetch.sh — Fetch random wallpapers from the internet
# Usage: wallpaper-fetch.sh [count]
# Downloads wallpapers to ~/Pictures/wallpapers/

COUNT="${1:-5}"
WALLPAPER_DIR="$HOME/Pictures/wallpapers"
mkdir -p "$WALLPAPER_DIR"

echo "Fetching $COUNT random wallpapers..."

i=1
while [ "$i" -le "$COUNT" ]; do
    filename="wallpaper-$(date +%s)-$i.jpg"
    # Lorem Picsum: free random HD images, no API key needed
    if curl -sL -o "$WALLPAPER_DIR/$filename" \
        "https://picsum.photos/1920/1080" 2>/dev/null; then
        # Verify it's actually an image (not an error page)
        if file "$WALLPAPER_DIR/$filename" 2>/dev/null | grep -qi "image\|JPEG\|PNG"; then
            echo "  Downloaded: $filename"
        else
            rm -f "$WALLPAPER_DIR/$filename"
            echo "  Skipped (not an image): $filename"
        fi
    else
        echo "  Failed to download wallpaper $i"
    fi
    i=$((i + 1))
done

echo "Done. Wallpapers saved to $WALLPAPER_DIR"
