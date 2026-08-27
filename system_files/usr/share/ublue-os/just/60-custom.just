[group('Digitalygo')]
digitalygo-setup:
    #!/usr/bin/env bash
    set -euo pipefail

    brew install gh chezmoi lazygit mise
    brew install anomalyco/tap/opencode
    brew postinstall ca-certificates

    mise install node@24
    mise use -g node@24
    export PATH="${HOME}/.local/share/mise/shims:${PATH}"

    if [ -e "${HOME}/.local/bin/pi" ] && grep -Fq '.local/opt/node22' "${HOME}/.local/bin/pi"; then
        rm -f "${HOME}/.local/bin/pi" "${HOME}/.local/bin/pi-real"
    fi

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
    flatpak install -y --user cosmic io.github.hepp3n.kdeconnect//master

    mise exec node@24 -- npm install --prefix "${HOME}/.local/libexec/pi" --ignore-scripts @earendil-works/pi-coding-agent

    echo "Next step: run 'ujust digitalygo-netbird-setup' to provision and enroll NetBird."

[group('Digitalygo')]
digitalygo-netbird-setup:
    #!/usr/bin/env bash
    set -euo pipefail

    # Official two-pass NetBird onboarding (Universal Blue rpm-ostree flow):
    # packages are layered into a pending deployment and only exist after a
    # reboot, so this command never reboots on its own and never touches the
    # service or runs enrollment before that reboot.
    if [[ "${EUID}" -eq 0 ]]; then
        echo "Do not run 'ujust digitalygo-netbird-setup' as root; run it as your normal user." >&2
        exit 1
    fi

    # Publish the official repository definition shipped with the image.
    /usr/bin/sudo -- /usr/bin/install -D -o root -g root -m 0644 \
        /usr/share/digitalygo/netbird.repo \
        /etc/yum.repos.d/netbird.repo

    # Prints the pending-probe exit code: 0 = nothing pending, 77 = a
    # deployment is pending. Any other code is an unusable answer and aborts.
    probe_status_rc() {
        local rc=0
        /usr/bin/rpm-ostree status --pending-exit-77 >/dev/null || rc=$?
        case "$rc" in
            0 | 77) echo "$rc" ;;
            *)
                echo "ERROR: 'rpm-ostree status --pending-exit-77' exited ${rc}; not 0 or 77, aborting." >&2
                return 1
                ;;
        esac
    }
    pending="$(probe_status_rc)"

    if ! /usr/bin/rpm -q --quiet netbird; then
        # Pass 1: layer NetBird into the NEXT deployment; it is not usable in
        # the booted tree until a reboot.
        /usr/bin/sudo -- /usr/bin/rpm-ostree install --idempotent netbird
        post="$(probe_status_rc)"
        if [[ "$post" -ne 77 ]]; then
            echo "ERROR: no pending deployment after installing netbird (probe exit ${post}), aborting." >&2
            exit 1
        fi
        echo "NetBird has been installed to a pending deployment."
        echo "Reboot now, then run 'ujust digitalygo-netbird-setup' again to enable the service and enroll."
        exit 0
    fi

    load_state="$(/usr/bin/systemctl show netbird.service --property=LoadState --value)"
    case "$load_state" in
        loaded)
            # Decide from the probes' exit statuses (--quiet suppresses their
            # human-readable state text); a failing answer repairs once.
            if ! /usr/bin/systemctl is-enabled --quiet netbird.service ||
                ! /usr/bin/systemctl is-active --quiet netbird.service; then
                /usr/bin/sudo -- /usr/bin/systemctl enable --now netbird.service
            fi
            exec /usr/bin/netbird up
            ;;
        not-found)
            if [[ "$pending" -eq 77 ]]; then
                echo "ERROR: NetBird is not ready yet: a deployment is pending." >&2
                echo "Please reboot, then run 'ujust digitalygo-netbird-setup' again." >&2
            else
                echo "ERROR: this image ships a baked-in netbird package without a usable systemd service, which is unsupported." >&2
                echo "Update to the fixed image ('ujust update'), reboot, then run 'ujust digitalygo-netbird-setup' again." >&2
            fi
            exit 1
            ;;
        *)
            echo "ERROR: netbird.service LoadState is '${load_state:-<empty>}'; refusing to guess or repair it." >&2
            exit 1
            ;;
    esac
