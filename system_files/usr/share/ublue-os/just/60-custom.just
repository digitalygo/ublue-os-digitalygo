# Digitalygo workstation bootstrap: GitHub auth, dev agents, and chezmoi dotfiles
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

    # 3. JetBrains Toolbox manager (per-user; run once, then install IDEs from it)
    brew tap ublue-os/homebrew-tap
    brew install --cask jetbrains-toolbox-linux

    # 4. DMS niri integration (generates ~/.config/niri/dms/*.kdl)
    if command -v dms &>/dev/null; then
        dms setup || true
    fi

    # 5. chezmoi dotfiles from the private digitalygo repo
    if [[ ! -d "${HOME}/.local/share/chezmoi" ]]; then
        chezmoi init digitalygo/dotfiles
    fi
    chezmoi apply
