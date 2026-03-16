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
    restic \
    chezmoi \
    git \
    curl \
    wget \
    nodejs \
    npm \
    wofi \
    mako \
    clipman \
    lxpolkit \
    google-noto-fonts-common \
    google-noto-sans-fonts \
    google-noto-emoji-fonts \
    adobe-source-code-pro-fonts

# ── Claude Code ───────────────────────────────────────────────────────────────
npm install -g @anthropic-ai/claude-code

# ── Default editor ────────────────────────────────────────────────────────────
alternatives --install /usr/bin/editor editor /usr/bin/nvim 60

# ── System services ──────────────────────────────────────────────────────────
systemctl enable podman.socket
