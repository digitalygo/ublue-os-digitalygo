# Digitalygo workstation recipes

# Install CLI dev tools via Homebrew. Run once after first login, then keep
# everything updated with `brew upgrade`.
[group('Digitalygo')]
digitalygo-brew:
    #!/usr/bin/env bash
    set -euo pipefail
    brew install gh chezmoi lazygit node
    brew install anomalyco/tap/opencode

# Install GUI apps via Flatpak (full, unfiltered Flathub).
# Run once after first login.
[group('Digitalygo')]
digitalygo-flatpak:
    #!/usr/bin/env bash
    set -euo pipefail

    flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo || true
    flatpak remote-modify --user --subset= flathub || true

    flatpak install -y --user flathub \
        com.vscodium.VSCodium \
        org.localsend.localsend \
        org.telegram.desktop \
        org.libreoffice.LibreOffice \
        md.obsidian.Obsidian \
        org.filezillaproject.Filezilla

# Bootstrap: GitHub auth, Pi, DMS integration, and chezmoi dotfiles.
# Run `ujust digitalygo-brew` first (installs gh and node via brew).
[group('Digitalygo')]
digitalygo-setup:
    #!/usr/bin/env bash
    set -euo pipefail

    # 1. GitHub CLI auth (interactive, one-time per machine)
    if ! gh auth status &>/dev/null; then
        gh auth login --hostname github.com --git-protocol https
    fi
    gh auth setup-git

    # 2. Pi coding agent (per-user npm global install)
    npm config set prefix "${HOME}/.local"
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent

    # 3. DMS niri integration (generates ~/.config/niri/dms/*.kdl)
    if command -v dms &>/dev/null; then
        dms setup || true
    fi

    # 4. chezmoi dotfiles from the private digitalygo repo
    if [[ ! -d "${HOME}/.local/share/chezmoi" ]]; then
        chezmoi init digitalygo/dotfiles
    fi
    chezmoi apply