#!/bin/bash
set -ouex pipefail

# ── Parallel downloads ───────────────────────────────────────────────────────
echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf

# ── RPMFusion ────────────────────────────────────────────────────────────────
# Must be installed first since codec and driver packages come from these repos
dnf5 -y install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# ── Multimedia codecs ────────────────────────────────────────────────────────
# Replace free codec stubs with full ffmpeg from RPMFusion
dnf5 -y swap ffmpeg-free ffmpeg --allowerasing || true

# ── Replace foot with alacritty ──────────────────────────────────────────────
dnf5 -y swap foot alacritty --allowerasing || dnf5 -y remove foot && dnf5 -y install alacritty

# ── All packages in a single transaction ─────────────────────────────────────
# Consolidating into one dnf5 call avoids repeated repo metadata loads
dnf5 -y install --skip-unavailable \
    ffmpeg-libs \
    libva-intel-driver \
    intel-media-driver \
    mesa-va-drivers-freeworld \
    mesa-vdpau-drivers-freeworld \
    distrobox \
    just \
    fzf \
    htop \
    tmux \
    neovim \
    zsh \
    fish \
    restic \
    chezmoi \
    git \
    git-credential-libsecret \
    gh \
    curl \
    wget \
    nodejs \
    npm \
    python3-pip \
    wofi \
    mako \
    clipman \
    lxpolkit \
    bootc \
    podman-compose \
    fastfetch \
    glow \
    gum \
    wl-clipboard \
    wireguard-tools \
    openssh-askpass \
    borgbackup \
    rclone \
    lm_sensors \
    powertop \
    ddcutil \
    evtest \
    pulseaudio-utils \
    input-remapper \
    iotop \
    ydotool \
    p7zip \
    p7zip-plugins \
    xdg-terminal-exec \
    libxcrypt-compat \
    google-noto-fonts-common \
    google-noto-sans-fonts \
    google-noto-emoji-fonts \
    adobe-source-code-pro-fonts \
    jetbrains-mono-fonts-all

# ── Claude Code ───────────────────────────────────────────────────────────────
HOME=/tmp npm install -g --prefix /usr --cache /tmp/npm-cache @anthropic-ai/claude-code

# ── Default editor ────────────────────────────────────────────────────────────
alternatives --install /usr/bin/editor editor /usr/bin/nvim 60

# ── System services ──────────────────────────────────────────────────────────
systemctl enable podman.socket
