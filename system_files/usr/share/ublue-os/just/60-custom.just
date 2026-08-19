# Digitalygo workstation bootstrap.
#
# Installs every user app and sets up the machine in one shot.
# Run once after first login; it is idempotent, so re-running is safe.
[group('Digitalygo')]
digitalygo-setup:
    #!/usr/bin/env bash
    set -euo pipefail

    # 1. CLI tools via Homebrew
    brew install gh chezmoi lazygit node
    brew install anomalyco/tap/opencode

    # 2. GitHub auth (interactive, one-time per machine)
    if ! gh auth status &>/dev/null; then
        gh auth login --hostname github.com --git-protocol https
    fi
    gh auth setup-git

    # 3. JetBrains Toolbox (per-user manager for the IDEs)
    brew tap ublue-os/homebrew-tap
    brew install --cask jetbrains-toolbox-linux

    # 4. GUI apps via Flatpak (full, unfiltered Flathub)
    flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo || true
    flatpak remote-modify --user --subset= flathub || true
    flatpak install -y --user flathub \
        com.vscodium.VSCodium \
        org.localsend.localsend \
        org.telegram.desktop \
        org.libreoffice.LibreOffice \
        md.obsidian.Obsidian \
        org.filezillaproject.Filezilla

    # 5. Pi coding agent (per-user npm global install)
    npm config set prefix "${HOME}/.local"
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent

    # 6. DMS niri integration (generates ~/.config/niri/dms/*.kdl)
    if command -v dms &>/dev/null; then
        dms setup || true
    fi

    # 7. chezmoi dotfiles from the private digitalygo repo
    if [[ ! -d "${HOME}/.local/share/chezmoi" ]]; then
        chezmoi init digitalygo/dotfiles
    fi
    chezmoi apply