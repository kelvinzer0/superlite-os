#!/bin/sh
# Upload file to Google Drive and open in Google Docs/Sheets/Slides
# Requires: google-drive-setup.sh sudah dijalankan sekali

CONFIG_DIR="$HOME/.config/google-drive"
CREDENTIALS="$CONFIG_DIR/credentials.json"
TOKEN_FILE="$CONFIG_DIR/token.json"

if [ ! -f "$TOKEN_FILE" ]; then
    echo "Error: Belum setup Google Drive. Jalankan google-drive-setup.sh"
    notify-send "Google Drive" "Belum setup. Jalankan google-drive-setup.sh"
    exit 1
fi

FILE="$1"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    echo "Usage: google-upload.sh <file>"
    exit 1
fi

BASENAME=$(basename "$FILE")
EXT="${BASENAME##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

# Get fresh access token (refresh if needed)
ACCESS_TOKEN=$(python3 -c "import json; d=json.load(open('$TOKEN_FILE')); print(d.get('access_token',''))" 2>/dev/null)
REFRESH_TOKEN=$(python3 -c "import json; d=json.load(open('$TOKEN_FILE')); print(d.get('refresh_token',''))" 2>/dev/null)
CLIENT_ID=$(python3 -c "import json; d=json.load(open('$CREDENTIALS')); print(d['installed']['client_id'])" 2>/dev/null)
CLIENT_SECRET=$(python3 -c "import json; d=json.load(open('$CREDENTIALS')); print(d['installed']['client_secret'])" 2>/dev/null)

# Refresh token if expired
REFRESH_RESPONSE=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${CLIENT_SECRET}" \
    -d "refresh_token=${REFRESH_TOKEN}" \
    -d "grant_type=refresh_token")

NEW_ACCESS_TOKEN=$(python3 -c "import json; d=json.loads('$(echo "$REFRESH_RESPONSE" | sed "s/'/\\\\'/g")'); print(d.get('access_token',''))" 2>/dev/null)
if [ -n "$NEW_ACCESS_TOKEN" ]; then
    ACCESS_TOKEN="$NEW_ACCESS_TOKEN"
fi

if [ -z "$ACCESS_TOKEN" ]; then
    echo "Error: Gagal mendapatkan access token"
    notify-send "Google Drive" "Gagal autentikasi. Jalankan google-drive-setup.sh"
    exit 1
fi

# Determine MIME type and Google conversion
case "$EXT_LOWER" in
    doc|docx|odt|rtf)
        MIME_TYPE="application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        CONVERT="true"
        GOOGLE_MIME="application/vnd.google-apps.document"
        OPEN_URL="https://docs.google.com/document/d/"
        SERVICE="Google Docs"
        ;;
    xls|xlsx|ods|csv)
        MIME_TYPE="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        CONVERT="true"
        GOOGLE_MIME="application/vnd.google-apps.spreadsheet"
        OPEN_URL="https://docs.google.com/spreadsheets/d/"
        SERVICE="Google Sheets"
        ;;
    ppt|pptx|odp)
        MIME_TYPE="application/vnd.openxmlformats-officedocument.presentationml.presentation"
        CONVERT="true"
        GOOGLE_MIME="application/vnd.google-apps.presentation"
        OPEN_URL="https://docs.google.com/presentation/d/"
        SERVICE="Google Slides"
        ;;
    pdf)
        MIME_TYPE="application/pdf"
        CONVERT="false"
        OPEN_URL="https://drive.google.com/file/d/"
        SERVICE="Google Drive"
        ;;
    *)
        MIME_TYPE="application/octet-stream"
        CONVERT="false"
        OPEN_URL="https://drive.google.com/file/d/"
        SERVICE="Google Drive"
        ;;
esac

notify-send "Uploading to $SERVICE" "$BASENAME"

# Upload file to Google Drive
if [ "$CONVERT" = "true" ]; then
    # Upload with conversion to Google format
    RESPONSE=$(curl -s -X POST \
        "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -F "metadata={\"name\":\"$BASENAME\",\"mimeType\":\"$GOOGLE_MIME\"};type=application/json;charset=UTF-8" \
        -F "file=@$FILE;type=$MIME_TYPE")
else
    # Upload without conversion
    RESPONSE=$(curl -s -X POST \
        "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -F "metadata={\"name\":\"$BASENAME\"};type=application/json;charset=UTF-8" \
        -F "file=@$FILE;type=$MIME_TYPE")
fi

FILE_ID=$(python3 -c "import json; d=json.loads('$(echo "$RESPONSE" | sed "s/'/\\\\'/g")'); print(d.get('id',''))" 2>/dev/null)

if [ -z "$FILE_ID" ]; then
    echo "Error: Gagal upload file"
    echo "Response: $RESPONSE"
    notify-send "Upload Gagal" "$BASENAME"
    exit 1
fi

# Make file accessible via link
curl -s -X POST \
    "https://www.googleapis.com/drive/v3/files/$FILE_ID/permissions" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"role":"reader","type":"anyone"}' > /dev/null

# Open in browser
xdg-open "${OPEN_URL}${FILE_ID}"
notify-send "Berhasil dibuka di $SERVICE" "$BASENAME"
