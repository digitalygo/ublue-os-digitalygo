[group('Digitalygo')]
digitalygo-setup:
    #!/usr/bin/env bash
    set -euo pipefail

    brew install gh chezmoi lazygit
    brew install anomalyco/tap/opencode

    mise install node@22
    mise use -g node@22
    export PATH="${HOME}/.local/share/mise/shims:${PATH}"

    brew tap ublue-os/homebrew-tap
    brew install --cask jetbrains-toolbox-linux

    flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo || true
    flatpak remote-modify --user --subset= flathub || true
    flatpak install -y --user flathub \
        com.vscodium.VSCodium \
        org.localsend.localsend \
        org.telegram.desktop \
        org.libreoffice.LibreOffice \
        md.obsidian.Obsidian \
        org.filezillaproject.Filezilla

    npm config set prefix "${HOME}/.local"
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent

    if command -v dms &>/dev/null; then
        dms setup || true
    fi
