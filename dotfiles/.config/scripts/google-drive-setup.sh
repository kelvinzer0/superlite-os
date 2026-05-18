#!/bin/sh
# Google Drive OAuth2 Setup
# Run this once to authenticate with Google Drive
# Requires: credentials.json from Google Cloud Console

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/google-drive"
CREDENTIALS="$CONFIG_DIR/credentials.json"
TOKEN_FILE="$CONFIG_DIR/token.json"

mkdir -p "$CONFIG_DIR"

if [ ! -f "$CREDENTIALS" ]; then
    echo "=== Google Drive Setup ==="
    echo ""
    echo "1. Buka https://console.cloud.google.com"
    echo "2. Buat project baru (atau pilih yang sudah ada)"
    echo "3. Enable Google Drive API:"
    echo "   - APIs & Services > Library > search 'Google Drive API' > Enable"
    echo "4. Buat OAuth credentials:"
    echo "   - APIs & Services > Credentials > Create Credentials > OAuth client ID"
    echo "   - Application type: Desktop app"
    echo "   - Download JSON, rename ke 'credentials.json'"
    echo "5. Copy credentials.json ke: $CREDENTIALS"
    echo ""
    echo "Setelah itu, jalankan script ini lagi."
    exit 1
fi

# Extract client_id and client_secret from credentials.json
CLIENT_ID=$(python3 -c "import json; d=json.load(open('$CREDENTIALS')); print(d['installed']['client_id'])" 2>/dev/null)
CLIENT_SECRET=$(python3 -c "import json; d=json.load(open('$CREDENTIALS')); print(d['installed']['client_secret'])" 2>/dev/null)

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo "Error: Gagal membaca credentials.json"
    exit 1
fi

REDIRECT_URI="urn:ietf:wg:oauth:2.0:oob"
SCOPE="https://www.googleapis.com/auth/drive.file"
AUTH_URL="https://accounts.google.com/o/oauth2/v2/auth?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&response_type=code&scope=${SCOPE}&access_type=offline&prompt=consent"

echo "=== Google Drive Authorization ==="
echo ""
echo "Buka URL berikut di browser:"
echo ""
echo "$AUTH_URL"
echo ""
echo "Setelah authorize, copy kode yang diberikan dan paste di sini:"
printf "Code: "
read AUTH_CODE

if [ -z "$AUTH_CODE" ]; then
    echo "Error: Kode kosong"
    exit 1
fi

# Exchange code for tokens
TOKEN_RESPONSE=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "code=${AUTH_CODE}" \
    -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${CLIENT_SECRET}" \
    -d "redirect_uri=${REDIRECT_URI}" \
    -d "grant_type=authorization_code")

# Save token
echo "$TOKEN_RESPONSE" > "$TOKEN_FILE"

ACCESS_TOKEN=$(python3 -c "import json; d=json.load(open('$TOKEN_FILE')); print(d.get('access_token',''))" 2>/dev/null)
REFRESH_TOKEN=$(python3 -c "import json; d=json.load(open('$TOKEN_FILE')); print(d.get('refresh_token',''))" 2>/dev/null)

if [ -n "$ACCESS_TOKEN" ] && [ -n "$REFRESH_TOKEN" ]; then
    echo ""
    echo "✓ Berhasil terotentikasi!"
    echo "Token tersimpan di: $TOKEN_FILE"
else
    echo ""
    echo "✗ Gagal mendapatkan token. Coba lagi."
    exit 1
fi
