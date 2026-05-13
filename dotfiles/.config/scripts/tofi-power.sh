#!/bin/sh
# SuperLite OS — Power Menu

CHOICE=$(printf "Shutdown\nReboot\nLogout\nLock" | tofi \
    --width=200 --height=200 \
    --font-size=16 \
    --prompt="Power: " \
    --num-results=4)

case "$CHOICE" in
    Shutdown) poweroff ;;
    Reboot)   reboot ;;
    Logout)   labwc --exit ;;
    Lock)     swaylock -c 0f0f23 ;;
esac
