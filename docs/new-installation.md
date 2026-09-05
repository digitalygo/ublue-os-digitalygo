# Digitalygo OS new installation

This guide starts at the first desktop login after installing and booting the Digitalygo OS image. Run the `ujust` commands as your normal desktop user. Do not prefix them with `sudo`; each recipe requests elevated privileges only where needed.

## Installation order

### 1. Update the image before installing NetBird

NetBird is not layered yet, so update the base image with bootc:

```bash
sudo bootc update
```

If bootc stages an update, reboot and log in again before continuing:

```bash
systemctl reboot
```

Completing the image update first avoids mixing it with the pending NetBird deployment created later.

### 2. Run the Digitalygo workstation setup

```bash
ujust digitalygo-setup
```

This recipe installs the workstation applications and development tools described in [Digitalygo setup](#digitalygo-setup). When it finishes, it points to the separate NetBird setup command.

### 3. Stage the NetBird installation

```bash
ujust digitalygo-netbird-setup
```

On the first run, the recipe:

- Publishes the NetBird repository definition shipped with the image, with package and repository metadata signature checks enabled.
- Runs `rpm-ostree install --idempotent netbird` through `sudo`.
- Confirms that rpm-ostree created a pending deployment.
- Stops without starting NetBird or rebooting automatically.

Reboot manually:

```bash
systemctl reboot
```

### 4. Activate and enroll NetBird

After rebooting, run the same recipe again as your normal desktop user:

```bash
ujust digitalygo-netbird-setup
```

The second run verifies that `netbird.service` is loaded, enables and starts it when necessary, then runs `netbird up` as your user. Complete the interactive enrollment in the browser.

The image and repository must never contain NetBird setup keys, peer credentials, or generated client configuration.

### 5. Verify the installation

```bash
rpm -q netbird
systemctl is-enabled netbird
systemctl is-active netbird
netbird status
```

The package should be installed, the service should be enabled and active, and `netbird status` should communicate with the daemon.

## Custom ujust recipes

The image defines its custom recipes in `system_files/usr/share/ublue-os/just/60-custom.just`.

### `digitalygo-setup`

Run this once during workstation onboarding:

```bash
ujust digitalygo-setup
```

It performs the following user-level setup:

- Installs `gh`, `chezmoi`, `lazygit`, and `mise` with Homebrew.
- Installs OpenCode from `anomalyco/tap` and completes the Homebrew CA certificate setup.
- Installs Node.js 24 with mise and selects it as the global Node.js version.
- Removes an obsolete Pi wrapper when it still points to the previous local Node.js 22 installation.
- Installs JetBrains Toolbox from the trusted Universal Blue Homebrew tap.
- Configures the user Flathub remote and installs VSCodium, LocalSend, Telegram Desktop, LibreOffice, Obsidian, FileZilla, Godot 3, Android Studio, Zed, Arduino IDE 2, and Bambu Studio.
- Configures the COSMIC Flatpak remote and installs its KDE Connect package from the `master` branch.
- Installs the Pi coding agent under `~/.local/libexec/pi` with Node.js 24.
- Prints `ujust digitalygo-netbird-setup` as the next onboarding step.

### `digitalygo-netbird-setup`

Run this recipe once before and once after its required reboot:

```bash
ujust digitalygo-netbird-setup
```

NetBird is intentionally installed only as a local rpm-ostree layered package. It is not baked into the OCI image. The official RPM scriptlets need to provision the upstream systemd service on a booted host, which does not work correctly during image construction.

The recipe is rerunnable and uses an idempotent package installation. It rejects execution as root, pins privileged command paths, never creates a custom service, never reboots automatically, and keeps interactive `netbird up` enrollment in the desktop user session.

## Updating the OS after installing NetBird

A NetBird layer makes the deployment incompatible with direct bootc mutation. The following bootc error is expected:

```text
Deployment contains local rpm-ostree modifications; cannot upgrade via bootc.
```

Do not remove NetBird just to make `sudo bootc update` or `sudo bootc upgrade` succeed. Update the image and reapply its package layer through rpm-ostree instead:

```bash
sudo rpm-ostree upgrade
```

Inspect the result:

```bash
rpm-ostree status
```

If rpm-ostree staged a deployment, reboot:

```bash
systemctl reboot
```

`sudo rpm-ostree uninstall netbird` removes the NetBird layer from the next deployment. `sudo rpm-ostree reset` is much broader: it removes all local rpm-ostree mutations, including other layered packages and overrides. Do not use `reset` merely to remove NetBird or bypass the bootc error.

## Troubleshooting

Show the booted, staged, and layered deployment state:

```bash
rpm-ostree status -v
```

A healthy NetBird installation appears under `LayeredPackages` as `netbird`.

If the package is present but the service is not ready and a deployment is pending, reboot and rerun:

```bash
ujust digitalygo-netbird-setup
```

If the package is present, the service is missing, and no deployment is pending, the machine may still use the legacy image that baked in an incomplete NetBird package. Update to the fixed image, reboot, and rerun the setup:

```bash
ujust update
systemctl reboot
ujust digitalygo-netbird-setup
```

Check each runtime component separately:

```bash
rpm -q netbird
systemctl status netbird
netbird status
```

The repository follows the [official NetBird procedure for Fedora Silverblue, Atomic, and Universal Blue](https://docs.netbird.io/get-started/install/linux#fedora-silverblue-atomic-universal-blue-rpm-ostree). See the [rpm-ostree administrator handbook](https://coreos.github.io/rpm-ostree/administrator-handbook/) for deployment, package layering, upgrades, and rollback behavior.
