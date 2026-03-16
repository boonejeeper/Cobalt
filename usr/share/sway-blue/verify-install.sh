#!/bin/bash
# Verify expected packages are installed and show versions
# Run on the deployed system: bash /usr/share/sway-blue/verify-install.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

MISSING=0

check() {
    local cmd="$1"
    local flag="${2:---version}"
    if command -v "$cmd" &>/dev/null; then
        ver=$("$cmd" $flag 2>&1 | head -1)
        printf "${GREEN}%-20s${NC} %s\n" "$cmd" "$ver"
    else
        printf "${RED}%-20s${NC} NOT FOUND\n" "$cmd"
        MISSING=$((MISSING + 1))
    fi
}

echo "=== Sway Desktop ==="
check sway
check swaybg
check swayidle
check swaylock
check waybar
check wofi
check foot --version
check grim
check slurp
check wl-copy --version
check mako
check kanshi
check clipman --version
check wev --version
check lxpolkit --version

echo ""
echo "=== System Tools ==="
check flatpak
check podman
check distrobox
check just
check fzf
check htop
check tmux -V
check nvim --version
check zsh --version
check git --version
check curl --version
check wget --version

echo ""
echo "=== Daily Drivers ==="
check restic version
check chezmoi --version

echo ""
echo "=== Multimedia ==="
check ffmpeg -version
check brightnessctl --version
check playerctl --version

echo ""
echo "=== Fonts ==="
if fc-list | grep -qi "noto sans" &>/dev/null; then
    printf "${GREEN}%-20s${NC} %s\n" "Noto Sans" "$(fc-list 'Noto Sans' | head -1)"
else
    printf "${RED}%-20s${NC} NOT FOUND\n" "Noto Sans"
    MISSING=$((MISSING + 1))
fi
if fc-list | grep -qi "source code pro" &>/dev/null; then
    printf "${GREEN}%-20s${NC} %s\n" "Source Code Pro" "$(fc-list 'Source Code Pro' | head -1)"
else
    printf "${RED}%-20s${NC} NOT FOUND\n" "Source Code Pro"
    MISSING=$((MISSING + 1))
fi

echo ""
echo "=== Services ==="
if systemctl is-enabled podman.socket &>/dev/null; then
    printf "${GREEN}%-20s${NC} enabled\n" "podman.socket"
else
    printf "${RED}%-20s${NC} NOT ENABLED\n" "podman.socket"
    MISSING=$((MISSING + 1))
fi

echo ""
if [[ $MISSING -eq 0 ]]; then
    printf "${GREEN}All checks passed.${NC}\n"
else
    printf "${YELLOW}${MISSING} item(s) missing or not found.${NC}\n"
    exit 1
fi
