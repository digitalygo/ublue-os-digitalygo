# Digitalygo workstation bootstrap: installs every user app (no GitHub steps).
#
# Run once after first login; it is idempotent, so re-running is safe.
# GitHub auth and chezmoi dotfiles are done separately (see digitalygo-os-install skill).
[group('Digitalygo')]
digitalygo-setup:
    #!/usr/bin/env bash
    set -euo pipefail

    # 1. CLI tools via Homebrew
    brew install gh chezmoi lazygit
    brew install anomalyco/tap/opencode

    # node via mise (brew's node postinstall fails on this image)
    mise install node@22
    mise use -g node@22
    export PATH="${HOME}/.local/share/mise/shims:${PATH}"

    # 2. JetBrains Toolbox (per-user manager for the IDEs)
    brew tap ublue-os/homebrew-tap
    brew install --cask jetbrains-toolbox-linux

    # 3. GUI apps via Flatpak (full, unfiltered Flathub)
    flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo || true
    flatpak remote-modify --user --subset= flathub || true
    flatpak install -y --user flathub \
        com.vscodium.VSCodium \
        org.localsend.localsend \
        org.telegram.desktop \
        org.libreoffice.LibreOffice \
        md.obsidian.Obsidian \
        org.filezillaproject.Filezilla

    # 4. Pi coding agent (per-user npm global install)
    npm config set prefix "${HOME}/.local"
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent

    # 5. DMS niri integration (generates ~/.config/niri/dms/*.kdl)
    if command -v dms &>/dev/null; then
        dms setup || true
    fi