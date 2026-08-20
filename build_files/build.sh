#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

# ---------------------------------------------------------------------------
# 1. Remove GNOME: this image uses COSMIC, no double desktop
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
# 2. COSMIC desktop (System76) + greetd login manager
# ---------------------------------------------------------------------------
curl -Lo /etc/yum.repos.d/ryanabx-cosmic.repo \
    "https://copr.fedorainfracloud.org/coprs/ryanabx/cosmic-epoch/repo/fedora-$(rpm -E %fedora)/ryanabx-cosmic-epoch-fedora-$(rpm -E %fedora).repo"
dnf5 install -y cosmic-desktop cosmic-greeter greetd gnome-keyring

# greetd + cosmic-greeter as the login manager
id cosmic-greeter &>/dev/null || useradd --system --home-dir /var/lib/cosmic-greeter --create-home --shell /usr/sbin/nologin cosmic-greeter
mkdir -p /etc/greetd
cat > /etc/greetd/config.toml << 'EOF'
[terminal]
vt = 1

[default_session]
command = "cosmic-comp cosmic-greeter"
user = "cosmic-greeter"
EOF
rm -f /etc/systemd/system/display-manager.service
ln -s /usr/lib/systemd/system/greetd.service /etc/systemd/system/display-manager.service
systemctl enable --force greetd.service

# ---------------------------------------------------------------------------
# Note: user apps are installed at runtime via ujust, not baked:
#   - CLI tools (gh, node, chezmoi, lazygit, opencode)  -> `ujust digitalygo-setup`
#   - GUI apps via flatpak (codium, telegram, ...)       -> `ujust digitalygo-setup`
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 3. Google Chrome (for Chrome DevTools)
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
# 4. VPN + mesh networking
# ---------------------------------------------------------------------------
dnf5 install -y openvpn NetworkManager-openvpn

# NetBird (WireGuard mesh VPN, CLI agent)
cat > /etc/yum.repos.d/netbird.repo << 'EOF'
[netbird]
name=netbird
baseurl=https://pkgs.netbird.io/yum/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.netbird.io/yum/repodata/repomd.xml.key
repo_gpgcheck=0
EOF
dnf5 install -y --setopt=tsflags=noscripts netbird

# ---------------------------------------------------------------------------
# 5. Development toolchains
# ---------------------------------------------------------------------------
dnf5 install -y \
    golang golang-x-tools-gopls delve \
    php-cli php-fpm php-mysqlnd php-pdo php-pgsql php-gd php-xml \
    php-mbstring php-intl php-zip php-curl php-opcache php-pecl-xdebug composer

# ---------------------------------------------------------------------------
# 6. Sunshine streaming server (Moonlight client connects to this)
# ---------------------------------------------------------------------------
curl -Lo /etc/yum.repos.d/lizardbyte-sunshine.repo \
    "https://copr.fedorainfracloud.org/coprs/lizardbyte/stable/repo/fedora-$(rpm -E %fedora)/lizardbyte-stable-fedora-$(rpm -E %fedora).repo"
dnf5 install -y Sunshine

# ---------------------------------------------------------------------------
# Enable podman socket
# ---------------------------------------------------------------------------
systemctl enable podman.socket
