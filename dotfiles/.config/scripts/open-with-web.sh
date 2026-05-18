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
    doc|docx|odt|rtf|xls|xlsx|ods|csv|ppt|pptx|odp)
        if [ -f "$HOME/.config/google-drive/token.json" ]; then
            "$UPLOAD_SCRIPT" "$FILE"
        else
            notify-send "Google Drive" "Belum setup. Jalankan: google-drive-setup.sh"
            xdg-open "$FILE"
        fi
        ;;
    *)
        xdg-open "$FILE"
        ;;
esac
