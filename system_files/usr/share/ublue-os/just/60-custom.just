[group('Digitalygo')]
digitalygo-setup:
    #!/usr/bin/env bash
    set -euo pipefail

    brew install gh chezmoi lazygit mise
    brew install anomalyco/tap/opencode

    mise install node@22
    mise use -g node@22
    export PATH="${HOME}/.local/share/mise/shims:${PATH}"

    brew tap ublue-os/homebrew-tap
    brew trust ublue-os/tap
    brew install --cask jetbrains-toolbox-linux

    flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo || true
    flatpak remote-modify --user --subset= flathub || true
    flatpak install -y --user flathub \
        com.vscodium.codium \
        org.localsend.localsend_app \
        org.telegram.desktop \
        org.libreoffice.LibreOffice \
        md.obsidian.Obsidian \
        org.filezillaproject.Filezilla \
        org.godotengine.Godot3 \
        com.google.AndroidStudio \
        dev.zed.Zed \
        cc.arduino.IDE2 \
        com.bambulab.BambuStudio

    flatpak remote-add --if-not-exists --user cosmic https://apt.pop-os.org/cosmic/cosmic.flatpakrepo || true
    flatpak install -y --user cosmic io.github.hepp3n.kdeconnect

    npm config set prefix "${HOME}/.local"
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent
