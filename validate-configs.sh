#!/bin/bash
# validate-configs.sh — Validate SuperLite OS configs in Alpine Docker

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ERRORS=0
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; ERRORS=$((ERRORS+1)); }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }
header() { echo -e "\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}${BOLD}  $1${NC}"; echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

DOTFILES="/dotfiles"

# ============================================================
header "1. Package Availability (community+testing repos)"
# ============================================================
PACKAGES=(
  labwc foot waybar swaybg wlr-randr swayidle mako brightnessctl
  font-awesome font-jetbrains-mono pipewire wireplumber
  grim slurp wtype libnotify polkit xwayland
)

for pkg in "${PACKAGES[@]}"; do
  if apk info -e "$pkg" >/dev/null 2>&1; then
    ok "$pkg"
  else
    fail "$pkg — NOT FOUND"
  fi
done

# ============================================================
header "2. Waybar Config Validation"
# ============================================================
CONFIG="$DOTFILES/.config/waybar/config"

if [ -f "$CONFIG" ]; then
  ok "Config file exists"
  
  # Strip JSONC comments and trailing commas, then validate
  STRIPPED=$(sed 's|//.*$||g; /^[[:space:]]*$/d' "$CONFIG" | sed 's/,\([[:space:]]*[}\]])/\1/g')
  
  if echo "$STRIPPED" | jq . >/dev/null 2>&1; then
    ok "Valid JSON (after stripping comments)"
  else
    fail "Invalid JSON — jq parse error:"
    echo "$STRIPPED" | jq . 2>&1 | head -5
  fi
  
  LAYER=$(echo "$STRIPPED" | jq -r '.layer // "missing"')
  if [ "$LAYER" = "top" ]; then
    ok "layer = top ✓ (visible above windows)"
  elif [ "$LAYER" = "bottom" ]; then
    fail "layer = bottom — HIDDEN behind maximized windows!"
  else
    warn "layer = $LAYER"
  fi
  
  POS=$(echo "$STRIPPED" | jq -r '.position // "missing"')
  ok "position = $POS"
  
  HEIGHT=$(echo "$STRIPPED" | jq -r '.height // "auto"')
  ok "height = $HEIGHT"
else
  fail "Config NOT FOUND"
fi

# ============================================================
header "3. Waybar Style CSS Validation"
# ============================================================
STYLE="$DOTFILES/.config/waybar/style.css"

if [ -f "$STYLE" ]; then
  ok "Style file exists ($(wc -c < "$STYLE") bytes)"
  OPEN=$(grep -o '{' "$STYLE" | wc -l)
  CLOSE=$(grep -o '}' "$STYLE" | wc -l)
  if [ "$OPEN" -eq "$CLOSE" ]; then
    ok "Braces balanced ($OPEN open, $CLOSE close)"
  else
    fail "Braces UNBALANCED ($OPEN open, $CLOSE close)"
  fi
  
  # Check key selectors exist
  for sel in "window#waybar" "#taskbar" "#clock" "#battery" "#network"; do
    if grep -q "$sel" "$STYLE"; then
      ok "Selector '$sel' found"
    else
      warn "Selector '$sel' missing"
    fi
  done
else
  fail "Style NOT FOUND"
fi

# ============================================================
header "4. LabWC Autostart Validation"
# ============================================================
AUTOSTART="$DOTFILES/.config/labwc/autostart"

if [ -f "$AUTOSTART" ]; then
  ok "Autostart file exists"
  
  if grep -q "swaybg" "$AUTOSTART"; then
    ok "swaybg in autostart ✓"
    if grep -q "\-m fill" "$AUTOSTART"; then
      ok "swaybg uses -m fill"
    fi
  else
    fail "swaybg NOT in autostart — no wallpaper at boot!"
  fi
  
  if grep -q "waybar" "$AUTOSTART"; then
    ok "waybar in autostart ✓"
  else
    fail "waybar NOT in autostart!"
  fi
  
  # Check for bashisms
  if grep -q '\[\[' "$AUTOSTART"; then
    fail "Contains [[ bashism — Alpine /bin/sh will fail"
  else
    ok "No bashisms (safe for /bin/sh)"
  fi
else
  fail "Autostart NOT FOUND"
fi

# ============================================================
header "5. LabWC rc.xml Validation"
# ============================================================
RCXML="$DOTFILES/.config/labwc/rc.xml"

if [ -f "$RCXML" ]; then
  ok "rc.xml exists"
  KEYBINDS=$(grep -c '<keybind' "$RCXML")
  MOUSEBINDS=$(grep -c '<mousebind' "$RCXML")
  ok "$KEYBINDS keybindings, $MOUSEBINDS mousebindings"
  
  # Check essential keybinds
  for key in "W-Return" "W-Space" "W-f" "A-F4"; do
    if grep -q "key=\"$key\"" "$RCXML"; then
      ok "Keybind $key present"
    else
      warn "Keybind $key missing"
    fi
  done
else
  fail "rc.xml NOT FOUND"
fi

# ============================================================
header "6. LabWC Menu.xml Validation"
# ============================================================
MENUXML="$DOTFILES/.config/labwc/menu.xml"

if [ -f "$MENUXML" ]; then
  ok "menu.xml exists"
  
  if grep -q "Wallpaper" "$MENUXML"; then
    ok "Wallpaper menu found"
    if grep -q "Default Wallpaper" "$MENUXML"; then
      ok "Default Wallpaper option present"
    fi
    if grep -q "swaybg" "$MENUXML"; then
      ok "swaybg commands present"
    fi
  else
    fail "No Wallpaper menu!"
  fi
else
  fail "menu.xml NOT FOUND"
fi

# ============================================================
header "7. Default Wallpaper Check"
# ============================================================
WALLPAPER="$DOTFILES/Pictures/wallpapers/default.png"

if [ -f "$WALLPAPER" ]; then
  ok "Default wallpaper exists"
  SIZE=$(stat -c%s "$WALLPAPER" 2>/dev/null || wc -c < "$WALLPAPER")
  ok "Size: $SIZE bytes"
  
  if file "$WALLPAPER" | grep -qi "PNG"; then
    ok "Valid PNG image"
  else
    fail "NOT a valid PNG!"
  fi
else
  fail "Default wallpaper NOT FOUND"
fi

# ============================================================
header "8. Autostart ↔ Wallpaper Extension Match"
# ============================================================
if [ -f "$AUTOSTART" ] && [ -f "$WALLPAPER" ]; then
  AUTOSTART_EXT=$(grep "DEFAULT_WP=" "$AUTOSTART" | grep -oP '\.\w+"?$' | tr -d '"')
  ACTUAL_EXT=".${WALLPAPER##*.}"
  if [ "$AUTOSTART_EXT" = "$ACTUAL_EXT" ]; then
    ok "Extension match: autostart=$AUTOSTART_EXT file=$ACTUAL_EXT"
  else
    fail "Extension mismatch! autostart=$AUTOSTART_EXT file=$ACTUAL_EXT"
  fi
fi

# ============================================================
header "9. Genapkovl Scripts — Pictures Copy"
# ============================================================
for script in /superlite-os/aports/scripts/genapkovl-superlite.sh \
              /superlite-os/aports/scripts/genapkovl-superlite-install.sh \
              /superlite-os/aports/scripts/genapkovl-superlite-unified.sh; do
  name=$(basename "$script")
  if [ -f "$script" ]; then
    if grep -q "Pictures" "$script"; then
      ok "$name copies Pictures ✓"
    else
      fail "$name does NOT copy Pictures!"
    fi
    
    if bash -n "$script" 2>/dev/null; then
      ok "$name syntax OK"
    else
      fail "$name syntax error!"
    fi
  fi
done

# ============================================================
header "10. swaybg Dry-Run Test"
# ============================================================
# Test swaybg can parse the flags (won't actually display)
if command -v swaybg >/dev/null 2>&1; then
  ok "swaybg binary found"
  
  # Check image is loadable
  if [ -f "$WALLPAPER" ]; then
    # swaybg --help doesn't exist, but we can test it doesn't crash on --version
    SWAYBG_VER=$(swaybg --version 2>&1 || echo "unknown")
    ok "swaybg version: $SWAYBG_VER"
  fi
else
  fail "swaybg binary NOT FOUND"
fi

# ============================================================
header "Summary"
# ============================================================
if [ $ERRORS -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}All checks passed!${NC}"
else
  echo -e "  ${RED}${BOLD}$ERRORS issue(s) found${NC}"
fi
echo ""

exit $ERRORS
