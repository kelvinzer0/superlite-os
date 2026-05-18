#!/bin/sh
# Open files with appropriate handler
# PDF → browser, Office → Google Docs/Sheets/Slides

FILE="$1"

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    echo "Usage: open-with-web.sh <file>"
    exit 1
fi

BASENAME=$(basename "$FILE")
EXT="${BASENAME##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

case "$EXT_LOWER" in
    pdf)
        xdg-open "$FILE"
        ;;
    doc|docx|odt|rtf)
        notify-send "Opening in Google Docs" "$BASENAME"
        xdg-open "https://docs.google.com/document/create"
        ;;
    xls|xlsx|ods|csv)
        notify-send "Opening in Google Sheets" "$BASENAME"
        xdg-open "https://sheets.google.com/create"
        ;;
    ppt|pptx|odp)
        notify-send "Opening in Google Slides" "$BASENAME"
        xdg-open "https://slides.google.com/create"
        ;;
    *)
        xdg-open "$FILE"
        ;;
esac
