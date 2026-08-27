# NetBird image integration research

## Scope

This investigation evaluates whether NetBird should remain in the Digitalygo Universal Blue image and how its service lifecycle should be handled safely. It covers the repository installation logic, the current workstation package state, relevant Git history, NetBird 0.77.1 RPM behavior, upstream installation guidance, and available runtime setup patterns.

No implementation or remote infrastructure operation was performed.

## Executive summary

Keep NetBird, but fix its incomplete runtime setup. The image currently installs only `/usr/bin/netbird` because `tsflags=noscripts` suppresses the RPM `%post` script that creates and starts `netbird.service`. Removing `noscripts` is unsafe in the OCI image build because the `%post` tries to start a service without a booted systemd instance. The lowest-risk design is a dedicated, idempotent `ujust digitalygo-netbird-setup` command that provisions the service under the real host systemd, enables and starts it, verifies the daemon socket, and then launches interactive enrollment. Credentials and setup keys must remain outside the image and repository.

## What was reviewed

- `build_files/build.sh`
- `Containerfile`
- `system_files/usr/share/ublue-os/just/60-custom.just`
- `.github/workflows/build.yml`
- Existing repository tests
- Git commits `7b21541`, `f350acc`, and `279d514`
- Installed NetBird RPM 0.77.1 payload and scriptlets
- Current workstation systemd and NetBird daemon state
- [NetBird Linux installation guidance](https://docs.netbird.io/get-started/install/linux)
- [NetBird 0.77.1 service installer source](https://github.com/netbirdio/netbird/blob/v0.77.1/client/cmd/service_installer.go)
- [NetBird service systemd integration](https://github.com/netbirdio/service/blob/f62744f42502/service_systemd_linux.go)

The repository has no local `AGENTS.md`, `.github/CONTRIBUTING.md`, developer directives, or client expectations.

## Findings

### The current image installation is intentionally incomplete

`build_files/build.sh:74-84` creates the NetBird RPM repository and installs the package with:

```bash
dnf5 install -y --setopt=tsflags=noscripts netbird
```

The installed NetBird 0.77.1 RPM owns `/usr/bin/netbird` but does not contain a static `netbird.service` file. Its `%post` script performs the missing lifecycle actions:

```bash
/usr/bin/netbird service install
/usr/bin/netbird service start
```

Suppressing scriptlets therefore leaves a valid CLI with no daemon unit and no `/var/run/netbird.sock`. This exactly matches the observed workstation state.

### Normal RPM script execution is not suitable during the image build

The package installation runs inside the `Containerfile` build layer, where systemd is not booted as PID 1. NetBird's `%post` attempts to create, enable, reload, and start the service. Starting the daemon in that environment fails or produces build-environment state rather than target-host runtime state.

Repository history confirms the sequence:

- `7b21541` originally installed NetBird normally.
- `f350acc` added `tsflags=noscripts` because the RPM `%post` failed while starting the service in the container build.
- `279d514` removed `systemctl enable netbird` because no package-owned static unit existed.

Removing `tsflags=noscripts` would restore the known build failure and couple image creation to mutable upstream scriptlet behavior.

### NetBird supports Universal Blue, but activation is a runtime concern

The upstream guide, updated on 2026-08-21, documents Fedora Silverblue and Universal Blue installation followed by a reboot and:

```bash
systemctl enable --now netbird
```

The NetBird service installer writes `/etc/systemd/system/netbird.service`, enables it, and reloads systemd. Those actions are appropriate on a booted host, not during OCI image assembly.

### The repository already has a runtime onboarding mechanism

`system_files/usr/share/ublue-os/just/60-custom.just:1-40` provides `ujust digitalygo-setup` for host and user onboarding. A separate NetBird recipe fits this established runtime boundary while keeping privileged network setup isolated from application installation.

The existing CI only runs Node and Pi tests at `.github/workflows/build.yml:52-55`. It cannot currently detect a NetBird package that lacks a usable service lifecycle.

### Repository metadata verification differs from upstream guidance

`build_files/build.sh:82` sets `repo_gpgcheck=0`, while current upstream instructions use `repo_gpgcheck=1`. This should be validated against the repository endpoint and restored if builds succeed, rather than silently retaining weaker metadata verification.

### Enrollment material must not be image content

A NetBird setup key, peer identity, management credential, or generated client configuration must not be stored in Git, GitHub Actions command text, `system_files`, or an OCI layer. Normal workstation enrollment should use interactive `netbird up`. Any future unattended enrollment should use a short-lived, narrowly scoped key delivered at runtime through an approved secret channel.

## Options considered

| Option | Decision | Reason |
| --- | --- | --- |
| Dedicated runtime `ujust` setup | Recommended | Uses NetBird's supported installer under real systemd, provides visible errors, supports interactive enrollment, and avoids image secrets. |
| Remove NetBird | Reject unless the company stops using it | The problem is incomplete integration, not product incompatibility. Removal would also need cleanup of persistent units and client state on upgraded hosts. |
| Remove `tsflags=noscripts` | Reject | Reintroduces the known container-build service-start failure. |
| Automatic first-boot unit | Defer | Hides failures in boot logs, starts a privileged network daemon before enrollment, and complicates upgrades. |
| Repository-owned static NetBird unit | Reject | Forks upstream service arguments and conflicts with `netbird service install`, `reconfigure`, and `uninstall`. |
| Patch or repackage the RPM | Defer | Clean at the packaging layer but creates signing, maintenance, and vulnerability-response obligations. |
| Install through Homebrew | Reject for this image | Upstream documents additional SELinux handling, and it would duplicate a system package already available in the image. |

## Recommendation

1. Keep the official NetBird RPM installation with scriptlets disabled during image construction.
2. Add a dedicated `ujust digitalygo-netbird-setup` runtime command rather than silently adding NetBird to the general application setup.
3. Make service provisioning idempotent:
   - Verify `/usr/bin/netbird` and a booted systemd instance.
   - If `netbird.service` is absent, run `sudo netbird service install`.
   - Refuse to overwrite an unknown existing unit automatically.
   - Run `sudo systemctl enable --now netbird.service`.
   - Wait for `/var/run/netbird.sock` and verify that `netbird status` reaches the daemon.
4. Run interactive `netbird up` only after the service is healthy. Do not request or persist setup keys in the normal workstation recipe.
5. Document the NetBird setup command as a required onboarding step for company workstations.
6. Validate `repo_gpgcheck=1` and use it when the upstream repository supports it.
7. Add a booted VM smoke test because container-only checks cannot prove that systemd service creation and startup work.

## Verification requirements

Repository tests should verify:

- The package remains installed with scriptlets suppressed during image assembly.
- The dedicated runtime setup command exists and does not contain credentials.
- Fresh setup installs the service exactly once.
- Re-running setup is successful and does not overwrite an existing unit.
- A stopped known service is enabled and started.
- A conflicting unit blocks with a clear error.
- The daemon socket appears and `netbird status` reaches the daemon.

A booted disposable VM should verify:

1. `rpm -q netbird` succeeds.
2. `sudo netbird service install` creates the expected unit.
3. `sudo systemctl enable --now netbird` succeeds.
4. `systemctl is-enabled netbird` and `systemctl is-active netbird` succeed.
5. `netbird status` returns daemon state before enrollment.
6. Image upgrade preserves peer identity and uses the updated `/usr/bin/netbird` binary.

## Decision

NetBird should remain in the OS. The repository should make runtime service provisioning explicit, repeatable, testable, and credential-free instead of shipping a CLI that appears installed but cannot operate.
