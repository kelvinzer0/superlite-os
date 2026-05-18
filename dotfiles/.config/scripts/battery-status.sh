#!/bin/sh
# Auto-detect battery and output waybar JSON
# Works on any hardware - hides if no battery found

BAT_PATH=""
for bat in /sys/class/power_supply/BAT* /sys/class/power_supply/battery* /sys/class/power_supply/BATT*; do
    if [ -d "$bat" ] && [ -f "$bat/capacity" ]; then
        BAT_PATH="$bat"
        break
    fi
done

if [ -z "$BAT_PATH" ]; then
    exit 0
fi

CAPACITY=$(cat "$BAT_PATH/capacity" 2>/dev/null)
STATUS=$(cat "$BAT_PATH/status" 2>/dev/null)

if [ -z "$CAPACITY" ]; then
    exit 0
fi

CLASS="battery"
ICON=""

case "$STATUS" in
    Charging)
        CLASS="battery charging"
        TEXT="+${CAPACITY}%"
        ;;
    Full)
        CLASS="battery plugged"
        TEXT="+${CAPACITY}%"
        ;;
    *)
        if [ "$CAPACITY" -le 5 ]; then
            CLASS="battery critical"
        elif [ "$CAPACITY" -le 15 ]; then
            CLASS="battery warning"
        fi
        TEXT="${CAPACITY}%"
        ;;
esac

echo "{\"text\": \"$TEXT\", \"class\": \"$CLASS\", \"tooltip\": \"${CAPACITY}% ($STATUS)\"}"
