#!/bin/sh
# Open files with appropriate handler
# PDF → browser, Office → auto-upload to Google Docs/Sheets/Slides

FILE="$1"

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    echo "Usage: open-with-web.sh <file>"
    exit 1
fi

BASENAME=$(basename "$FILE")
EXT="${BASENAME##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
UPLOAD_SCRIPT="$HOME/.config/scripts/google-upload.sh"

case "$EXT_LOWER" in
    pdf)
        xdg-open "$FILE"
        ;;
    doc|docx|odt|rtf)
        if [ -f "$HOME/.config/google-drive/token.json" ]; then
            "$UPLOAD_SCRIPT" "$FILE"
        else
            notify-send "Google Drive" "Setup belum ada, buka Google Docs manual"
            xdg-open "https://docs.google.com/document/create"
        fi
        ;;
    xls|xlsx|ods|csv)
        if [ -f "$HOME/.config/google-drive/token.json" ]; then
            "$UPLOAD_SCRIPT" "$FILE"
        else
            notify-send "Google Drive" "Setup belum ada, buka Google Sheets manual"
            xdg-open "https://sheets.google.com/create"
        fi
        ;;
    ppt|pptx|odp)
        if [ -f "$HOME/.config/google-drive/token.json" ]; then
            "$UPLOAD_SCRIPT" "$FILE"
        else
            notify-send "Google Drive" "Setup belum ada, buka Google Slides manual"
            xdg-open "https://slides.google.com/create"
        fi
        ;;
    *)
        xdg-open "$FILE"
        ;;
esac
