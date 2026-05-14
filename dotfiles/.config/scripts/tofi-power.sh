#!/bin/sh
# SuperLite OS — Power menu via tofi (LabWC-Alpine-Netbook style)

case $(printf "%s\n" "Logout" "Reboot" "Suspend" "Shutdown" | tofi -c ~/.config/tofi/config_power $@) in
    "Logout")
        labwc --exit
        ;;
    "Reboot")
        sudo reboot -i
        ;;
    "Suspend")
        sudo zzz
        ;;
    "Shutdown")
        sudo poweroff -i
        ;;
esac
