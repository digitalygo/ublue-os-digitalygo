---
status: completed
created_at: 2026-10-28
files_edited:
  - build_files/build.sh
  - tests/test-orca-removal.sh
  - .github/workflows/build.yml
rationale:
  - Make the requested Orca removal part of the image rather than a workstation-local override.
  - Avoid unintended screen-reader interception of typing without changing user preferences.
  - Preserve unused dependencies and test the removal before the image build.
supporting_docs:
  - ../../../build_files/build.sh
  - ../../../tests/test-orca-removal.sh
  - ../../../.github/workflows/build.yml
---

# Remove Orca from the workstation image

## Summary of changes

The image build now removes the Orca RPM after all package installations, including
COSMIC. A regression test runs in the existing CI runtime-policy step.

## Technical reasoning

The operator reported that removing Orca locally resolved intermittent keyboard
input interception, then requested the same policy in the image source. This is an
image composition decision, not proof that Orca causes every similar input problem.

The removal belongs after package installation because desktop groups can include
Orca. A package-presence check makes an already absent package a no-op.
`dnf5 remove -y --no-autoremove orca` targets Orca without automatically cleaning up
unused dependencies. A failed removal aborts the build through its existing strict
shell mode. Merely disabling a user-session setting would leave the package
available for accidental activation and would not meet the requested removal.

## Impact assessment

New images intentionally omit the Orca screen reader. Users who require Orca must
provide it separately. The change does not edit accessibility settings, keyboard
shortcuts, user data, or workstation-local rpm-ostree overrides. It does not target
COSMIC, the on-screen keyboard, or shared accessibility packages for removal.

The workflow adds one test invocation without changing triggers, permissions,
publication, or signing. The change takes effect on machines only after they
update to and boot an image containing it. No host deployment or reboot is part
of this repository task.

## Validation steps

The clean baseline was `73c7a667b8c80c7fa0083f718d5281992a8e5ec3` on `main`.
Implementation was isolated on `fix/remove-orca-from-image`. Repository-local
`AGENTS.md`, `.github/CONTRIBUTING.md`, developer directives, and client
expectations were absent.

The orchestrator independently ran:

- All four shell tests: Node runtime, Pi wrapper, NetBird onboarding, and Orca removal.
- `bash -n build_files/build.sh tests/test-orca-removal.sh`.
- `shellcheck build_files/build.sh tests/test-orca-removal.sh`.
- `just check` and `just lint`.
- YAML parsing for `.github/workflows/build.yml`.
- Baseline-versus-current actionlint comparison by diagnostic kind and message.
- `git diff --check`.

The new test executes the actual removal block with recording stubs and a
restricted command path. It covers installed and absent packages, exact removal
arguments, a failed removal stopping execution, and placement after every package
installation. All delta-focused checks passed. The independent quality judgment
returned `PASS`, accepting the branch and path coverage without claiming an
instrumented coverage percentage.

Repository-wide lint is not clean: `just lint` retains existing SC2016 and SC2015
informational diagnostics in unchanged tests, while actionlint reports the same
21 findings before and after this change. No new diagnostic was introduced.

A full OCI build and booted desktop test were not run locally. The existing PR
workflow builds the image and runs `bootc container lint`; the real dependency
transaction, resulting package set, and desktop behavior remain integration
verification concerns. No separate security review was required for this delta:
it adds no API, authentication, schema, secrets, or sensitive-data handling.
