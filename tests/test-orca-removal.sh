#!/usr/bin/env bash
# Regression tests for the build-time Orca removal in build_files/build.sh.
# The actual section is extracted from the build script and executed against
# recording rpm/dnf5 stubs, so the test needs no root and never runs the
# host-mutating build script.

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_sh="$repository_root/build_files/build.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

case_name="static"
events="$work/events.log"
out_file="$work/out.log"
rc=0

fail() {
    echo "FAIL [$case_name]: $1" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Extract the real section between its numbered heading and the podman block
# ---------------------------------------------------------------------------
grep -Fxq 'set -ouex pipefail' "$build_sh" ||
    fail "build.sh lost its strict-mode preamble"

orca_sections="$(grep -Ec '^# [0-9]+\. Remove Orca' "$build_sh" || true)"
[[ "$orca_sections" -eq 1 ]] ||
    fail "expected exactly one numbered Orca removal section, found $orca_sections"
podman_markers="$(grep -Ec '^# Enable podman socket' "$build_sh" || true)"
[[ "$podman_markers" -eq 1 ]] ||
    fail "expected exactly one podman socket marker, found $podman_markers"

orca_start="$(grep -nE '^# [0-9]+\. Remove Orca' "$build_sh" | cut -d: -f1)"
podman_line="$(grep -nE '^# Enable podman socket' "$build_sh" | cut -d: -f1)"
(( orca_start < podman_line )) ||
    fail "Orca section must precede the podman socket enable"
sed -n "${orca_start},$((podman_line - 1))p" "$build_sh" >"$work/orca-section.sh"

section="$work/orca-section.sh"
[[ -s "$section" ]] || fail "extracted Orca section is empty"
grep -Fq 'if rpm -q orca' "$section" ||
    fail "presence guard is missing"
grep -Fq 'dnf5 remove -y --no-autoremove orca' "$section" ||
    fail "exact removal command is missing"
removals="$(grep -Fc 'dnf5 remove' "$section" || true)"
[[ "$removals" -eq 1 ]] ||
    fail "section must perform exactly one dnf5 removal, found $removals"
installs="$(grep -Fc 'dnf5 install' "$section" || true)"
[[ "$installs" -eq 0 ]] ||
    fail "section must not install packages, found $installs installs"
bash -n "$section" || fail "extracted Orca section does not parse"
if sed 's/#.*//' "$section" | grep -Eq '/(usr/)?s?bin/'; then
    fail "section invokes an absolute host path instead of the stubbed PATH"
fi

# ---------------------------------------------------------------------------
# Ordering: every installer, especially COSMIC and Sunshine, must run first
# ---------------------------------------------------------------------------
removal_lines="$(grep -Fc 'dnf5 remove -y --no-autoremove orca' "$build_sh" || true)"
[[ "$removal_lines" -eq 1 ]] ||
    fail "expected exactly one Orca removal in build.sh, found $removal_lines"
removal_line="$(grep -nF 'dnf5 remove -y --no-autoremove orca' "$build_sh" | cut -d: -f1)"
for marker in '@cosmic-desktop-environment' 'Sunshine'; do
    marker_line="$(grep -nF -m1 -- "$marker" "$build_sh" | cut -d: -f1)"
    [[ -n "$marker_line" ]] || fail "missing installer marker: $marker"
    (( marker_line < removal_line )) ||
        fail "Orca removal must follow the $marker install"
done
while IFS=: read -r line _; do
    (( line < removal_line )) ||
        fail "dnf5 install at line $line runs after the Orca removal"
done < <(grep -nE '^[[:space:]]*dnf5 install' "$build_sh")
(( removal_line < podman_line )) ||
    fail "Orca removal must precede the podman socket enable"

# ---------------------------------------------------------------------------
# Recording stubs: the extracted block sees only rpm and dnf5 from PATH
# ---------------------------------------------------------------------------
stub="$work/stub"
mkdir -p "$stub"

cat >"$stub/rpm" <<'EOF'
#!/bin/bash
printf "%s\n" "CALL:rpm: $*" >> "${EVENTS:?}"
exit "${RPM_PRESENT_RC:?}"
EOF
chmod +x "$stub/rpm"

cat >"$stub/dnf5" <<'EOF'
#!/bin/bash
printf "%s\n" "CALL:dnf5: $*" >> "${EVENTS:?}"
exit "${DNF5_RC:?}"
EOF
chmod +x "$stub/dnf5"

{
    printf '%s\n' 'set -ouex pipefail'
    cat "$section"
    printf '%s\n' 'printf "BLOCK-COMPLETED\n"'
} >"$work/orca-runner.sh"
bash -n "$work/orca-runner.sh" || fail "runner copy does not parse"

bash_bin="$(command -v bash)"
run_section() {
    (
        export PATH="$stub"
        export EVENTS="$events" RPM_PRESENT_RC DNF5_RC
        "$bash_bin" --noprofile --norc "$work/orca-runner.sh"
    ) >"$out_file" 2>&1
}

run_and_expect_ok() {
    set +e
    run_section
    rc=$?
    set -e
    (( rc == 0 )) || fail "expected success, got exit $rc: $(cat "$out_file")"
    grep -Fxq 'BLOCK-COMPLETED' "$out_file" ||
        fail "success marker missing: $(cat "$out_file")"
}

assert_events() { # <expected multiline event log>
    local expected="$1" actual
    actual="$(cat "$events")"
    [[ "$actual" == "$expected" ]] || {
        printf 'expected events:\n%s\nactual events:\n%s\n' "$expected" "$actual" >&2
        fail "unexpected recorded commands"
    }
}

RPM_PRESENT_RC=0
DNF5_RC=0

# ---------------------------------------------------------------------------
# Present: exactly one probe, then the exact --no-autoremove removal
# ---------------------------------------------------------------------------
case_name="installed Orca is removed once without autoremove"
RPM_PRESENT_RC=0 DNF5_RC=0
: >"$events"
run_and_expect_ok
assert_events $'CALL:rpm: -q orca\nCALL:dnf5: remove -y --no-autoremove orca'

# ---------------------------------------------------------------------------
# Absent: the guard suppresses removal and the build continues
# ---------------------------------------------------------------------------
case_name="absent Orca is a no-op"
RPM_PRESENT_RC=1 DNF5_RC=0
: >"$events"
run_and_expect_ok
assert_events 'CALL:rpm: -q orca'

# ---------------------------------------------------------------------------
# Removal failure: strict mode stops the build before any success marker
# ---------------------------------------------------------------------------
case_name="failed removal aborts the build"
RPM_PRESENT_RC=0 DNF5_RC=1
: >"$events"
set +e
run_section
rc=$?
set -e
(( rc != 0 )) || fail "failed dnf5 removal did not fail the build"
if grep -Fq 'BLOCK-COMPLETED' "$out_file"; then
    fail "success marker ran after the removal failure"
fi
assert_events $'CALL:rpm: -q orca\nCALL:dnf5: remove -y --no-autoremove orca'

echo "Orca build-time removal: OK"
