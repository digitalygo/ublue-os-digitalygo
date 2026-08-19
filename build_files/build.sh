#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

# ---------------------------------------------------------------------------
# 1. Remove GNOME: this image uses niri + DMS, no double desktop
# ---------------------------------------------------------------------------
GNOME_PACKAGES=(
    bluefin-logos
    gnome-shell
    gdm
    gnome-session
    gnome-initial-setup
    gnome-software
    gnome-software-rpm-ostree
    gnome-tweaks
    gnome-shell-extensions-app
    ptyxis
    gnome-terminal
    gnome-terminal-nautilus
)
readarray -t GNOME_INSTALLED < <(rpm -qa --queryformat='%{NAME}\n' "${GNOME_PACKAGES[@]}" 2>/dev/null || true)
if [[ ${#GNOME_INSTALLED[@]} -gt 0 ]]; then
    dnf5 remove -y "${GNOME_INSTALLED[@]}"
fi

# ---------------------------------------------------------------------------
# 2. niri + wayland session essentials
# ---------------------------------------------------------------------------
dnf5 install -y \
    niri \
    xdg-desktop-portal-wlr \
    lxpolkit \
    kitty \
    nautilus

# Bibata cursor theme (morros look)
curl -Lo /etc/yum.repos.d/peterwu-rendezvous.repo \
    "https://copr.fedorainfracloud.org/coprs/peterwu/rendezvous/repo/fedora-$(rpm -E %fedora)/peterwu-rendezvous-fedora-$(rpm -E %fedora).repo"
dnf5 install -y bibata-cursor-themes

# ---------------------------------------------------------------------------
# 3. Dank Linux shell (DMS) + greetd login manager
# ---------------------------------------------------------------------------
curl --output-dir /etc/yum.repos.d/ --remote-name \
    "https://copr.fedorainfracloud.org/coprs/avengemedia/dms/repo/fedora-$(rpm -E %fedora)/avengemedia-dms-fedora-$(rpm -E %fedora).repo"
dnf5 install -y quickshell dms greetd dms-greeter --allowerasing

# greeter user for greetd (if not already present)
id greeter &>/dev/null || useradd --system --home-dir /var/lib/greetd --create-home --shell /usr/sbin/nologin greeter

# greetd config + replace the display manager with greetd
mkdir -p /etc/greetd
cat > /etc/greetd/config.toml << 'EOF'
[terminal]
vt = 1

[default_session]
user = "greeter"
command = "dms-greeter --command niri"
EOF
rm -f /etc/systemd/system/display-manager.service
ln -s /usr/lib/systemd/system/greetd.service /etc/systemd/system/display-manager.service
systemctl enable --force greetd.service

# DMS autostart for new users
mkdir -p /etc/skel/.config/systemd/user/graphical-session.target.wants
ln -s /usr/lib/systemd/user/dms.service /etc/skel/.config/systemd/user/graphical-session.target.wants/

# niri config for new users
mkdir -p /etc/skel/.config/niri
cp -rf /ctx/dot_config/niri/config.kdl /etc/skel/.config/niri/

# ---------------------------------------------------------------------------
# 4. CLI tools via Homebrew (already shipped by Bluefin DX)
# ---------------------------------------------------------------------------
brew install gh chezmoi node@22
brew link --force --overwrite node@22

# ---------------------------------------------------------------------------
# 5. GUI apps via Flatpak
# ---------------------------------------------------------------------------
flatpak install -y flathub com.vscodium.VSCodium

# ---------------------------------------------------------------------------
# 6. Google Chrome (for Chrome DevTools)
# ---------------------------------------------------------------------------
cat > /etc/yum.repos.d/google-chrome.repo << 'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/$basearch
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
dnf5 install -y google-chrome-stable

# ---------------------------------------------------------------------------
# 7. VPN
# ---------------------------------------------------------------------------
dnf5 install -y openvpn NetworkManager-openvpn

# ---------------------------------------------------------------------------
# 8. Development toolchains
# ---------------------------------------------------------------------------
dnf5 install -y \
    golang golang-x-tools-gopls delve \
    php-cli php-fpm php-mysqlnd php-pdo php-pgsql php-gd php-xml \
    php-mbstring php-intl php-zip php-curl php-opcache php-pecl-xdebug composer

# ---------------------------------------------------------------------------
# 9. Sunshine streaming server (Moonlight client connects to this)
# ---------------------------------------------------------------------------
curl -Lo /etc/yum.repos.d/lizardbyte-sunshine.repo \
    "https://copr.fedorainfracloud.org/coprs/lizardbyte/stable/repo/fedora-$(rpm -E %fedora)/lizardbyte-stable-fedora-$(rpm -E %fedora).repo"
dnf5 install -y Sunshine

# ---------------------------------------------------------------------------
# 10. JetBrains Toolbox manager (the IDEs themselves are installed per-user)
# ---------------------------------------------------------------------------
brew tap ublue-os/homebrew-tap
brew install --cask jetbrains-toolbox-linux

# ---------------------------------------------------------------------------
# Enable podman socket
# ---------------------------------------------------------------------------
systemctl enable podman.socket
