---
status: completed
created_at: 2026-08-26
updated_at: 2026-09-05
files_edited:
  - build_files/build.sh
  - docs/new-installation.md
  - .github/workflows/build.yml
  - README.md
  - system_files/usr/share/digitalygo/netbird.repo
  - system_files/usr/share/ublue-os/just/60-custom.just
  - tests/test-netbird-ujust.sh
rationale: Replace the broken image-baked NetBird package and abandoned custom service helper with NetBird's official Universal Blue rpm-ostree installation flow, then document the required fresh-install and upgrade sequence.
supporting_docs:
  - https://docs.netbird.io/get-started/install/linux#fedora-silverblue-atomic-universal-blue-rpm-ostree
  - ../../../docs/new-installation.md
  - ../research/2026-08-26-netbird-image-integration.md
  - ../status/2026-08-26-official-netbird-ujust-preexisting-changes.md
---

# Official NetBird ujust onboarding

## Summary of changes

NetBird is no longer installed during OCI image construction. A single `ujust digitalygo-netbird-setup` command now follows NetBird's official Universal Blue procedure by staging the signed RPM through rpm-ostree, requiring a reboot, and completing service activation and interactive enrollment when rerun after reboot.

## Technical reasoning

The previous image build installed NetBird with RPM scriptlets disabled. That left `/usr/bin/netbird` available without the upstream-generated `netbird.service`. A custom root helper was investigated but rejected because it duplicated package lifecycle behavior and expanded the privileged attack surface.

The final design delegates package and service ownership to the signed upstream RPM:

- `build_files/build.sh` no longer creates the NetBird repository or installs the package.
- `system_files/usr/share/digitalygo/netbird.repo` contains the exact official repository definition with package and metadata signature checks enabled.
- `ujust digitalygo-netbird-setup` copies the reviewed repository file, stages `rpm-ostree install --idempotent netbird`, and requests a manual reboot.
- The same command, rerun after reboot, enables the upstream service when needed and executes interactive `netbird up` as the desktop user.
- Legacy states where the RPM exists without a service fail closed instead of creating or repairing a custom unit.

The user confirmed that `.gitignore` entry `substrate/traces/status/` is a pre-existing user change. It was preserved and excluded from the implementation review delta.

## Impact assessment

Fresh fixed images do not contain the NetBird RPM. Each workstation layers the package through the documented rpm-ostree mechanism and needs one reboot before enrollment.

The current legacy image must first update to an image containing this fix. Running the command on the legacy package-without-unit state returns migration guidance and performs no custom service repair.

The command never reboots automatically, never accepts setup keys, and keeps browser-based SSO in the original desktop session.

## Validation steps

The implementation was validated with:

```bash
bash tests/test-netbird-ujust.sh
bash tests/test-node-runtime.sh
bash tests/test-pi-wrapper.sh
bash -n build_files/build.sh tests/test-netbird-ujust.sh
just check
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build.yml', encoding='utf-8'))"
git diff --check
```

All checks passed. The deterministic NetBird suite covers package staging, pending deployments, reboot boundaries, legacy failure states, service activation, idempotent reruns, fixed command paths, hostile `PATH`, forbidden credential surfaces, and repository template integrity.

The frozen quality package `ef0b9d086a552bdb035fee367d2793bf20f67d9ea740327aa75ad8b18226b7eb` passed. The separate cumulative security package with the same content hash also passed.

A live rpm-ostree deployment, reboot, systemd activation, and browser SSO cycle remains to be validated after building and booting the fixed image.

## Update on 2026-09-05

### Summary of new work

Added `docs/new-installation.md` with the complete first-login order, a reference for both Digitalygo `ujust` recipes, the required two-pass NetBird installation, and the supported update path after NetBird is layered.

### Technical reasoning

NetBird must remain a local rpm-ostree layer so its RPM scriptlets can provision the upstream service on a booted host. The guide makes the resulting update constraint explicit: use bootc before layering NetBird, then use `rpm-ostree upgrade` for later image updates. It also distinguishes the scoped NetBird uninstall from the broader `rpm-ostree reset` operation.

### Impact assessment

The documentation gives new workstation installations one ordered procedure and prevents the bootc incompatibility message from being mistaken for a broken deployment. No image, recipe, package, or runtime behavior changed.

### Validation steps

The guide was checked against `60-custom.just`, the shipped NetBird repository definition, the NetBird regression test, the README, and the existing operation record. The NetBird test, Just syntax check, Markdown structural checks, and `git diff --check` passed.
