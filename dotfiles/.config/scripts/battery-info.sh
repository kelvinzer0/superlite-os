#!/bin/sh
# Battery info & calibration helper
echo "=== Battery Status ==="
echo ""

# Check all batteries
for bat in /sys/class/power_supply/BAT*; do
    [ -d "$bat" ] || continue
    name=$(basename "$bat")
    echo "[$name]"
    
    if [ -f "$bat/status" ]; then
        echo "  Status:       $(cat "$bat/status")"
    fi
    if [ -f "$bat/capacity" ]; then
        echo "  Capacity:     $(cat "$bat/capacity")%"
    fi
    if [ -f "$bat/capacity_level" ]; then
        echo "  Level:        $(cat "$bat/capacity_level")"
    fi
    if [ -f "$bat/charge_full" ] && [ -f "$bat/charge_full_design" ]; then
        full=$(cat "$bat/charge_full")
        design=$(cat "$bat/charge_full_design")
        if [ "$design" -gt 0 ] 2>/dev/null; then
            health=$((full * 100 / design))
            echo "  Health:       ${health}%"
            echo "  Full:         ${full} μAh"
            echo "  Design:       ${design} μAh"
        fi
    fi
    if [ -f "$bat/voltage_now" ]; then
        v=$(cat "$bat/voltage_now")
        echo "  Voltage:      $((v / 1000)) mV"
    fi
    if [ -f "$bat/current_now" ]; then
        c=$(cat "$bat/current_now")
        echo "  Current:      $((c / 1000)) mA"
    fi
    if [ -f "$bat/power_now" ]; then
        p=$(cat "$bat/power_now")
        echo "  Power:        $((p / 1000000)) W"
    fi
    if [ -f "$bat/temp" ]; then
        t=$(cat "$bat/temp")
        echo "  Temperature:  $((t / 10))°C"
    fi
    if [ -f "$bat/cycle_count" ]; then
        echo "  Cycles:       $(cat "$bat/cycle_count")"
    fi
    echo ""
done

# AC adapter
for adp in /sys/class/power_supply/AC* /sys/class/power_supply/ADP*; do
    [ -d "$adp" ] || continue
    name=$(basename "$adp")
    if [ -f "$adp/online" ]; then
        status=$(cat "$adp/online")
        if [ "$status" = "1" ]; then
            echo "[$name] Plugged in"
        else
            echo "[$name] Unplugged"
        fi
    fi
done

echo ""
echo "=== ACPI ==="
acpi -b 2>/dev/null || echo "(acpi not installed)"
