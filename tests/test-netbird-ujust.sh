#!/usr/bin/env bash
# Tests for the official Universal Blue rpm-ostree NetBird onboarding flow:
# `ujust digitalygo-netbird-setup` in 60-custom.just plus its image surfaces.
# Deterministic and unprivileged: the extracted recipe is rewritten onto
# recording stubs, so nothing needs root, systemd, rpm-ostree, or network.

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
just_file="$repository_root/system_files/usr/share/ublue-os/just/60-custom.just"
build_sh="$repository_root/build_files/build.sh"
repo_file="$repository_root/system_files/usr/share/digitalygo/netbird.repo"

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

# Scenario knobs (exported; individual cases overwrite them explicitly).
set_knob_defaults() {
    RPM_Q_RC=1          # /usr/bin/rpm -q: 1 = package absent
    PRE_STATUS_RC=0     # first pending probe: 0 = nothing pending
    POST_STATUS_RC=77   # post-install probe: 77 = pending deployment
    SHOW_RC=0           # systemctl LoadState query exit code
    LOAD_STATE=loaded   # reported unit load state
    ENABLE_STATE=enabled
    ACTIVE_STATE=active
    SIMULATED_UID=1000        # replaces ${EUID} in the executing recipe copy
    HOSTILE_PATH=""
}
set_knob_defaults
export RPM_Q_RC PRE_STATUS_RC POST_STATUS_RC SHOW_RC LOAD_STATE \
    ENABLE_STATE ACTIVE_STATE SIMULATED_UID HOSTILE_PATH

run_recipe() {
    (
        export HOME="$work"
        export EVENTS="$events"
        export PATH="${HOSTILE_PATH:+$HOSTILE_PATH:}$work/stub:/usr/bin:/bin"
        bash --noprofile --norc "$work/recipe-dyn.sh"
    ) >"$out_file" 2>&1
}

call_count() { # <regex-for-name+args>
    grep -Ec "^CALL:$1:" "$events" || true
}

first_line_of() { # <fixed string> -> line number
    local n
    n="$(grep -Fn -- "$1" "$events" | head -n1 | cut -d: -f1)"
    [[ -n "$n" ]] || fail "missing expected event: $1"
    printf '%s' "$n"
}

# Failure paths may still run read-only queries, but never repair anything.
assert_no_mutations() {
    assert_absent 'sudo: -- .*systemctl enable'
    assert_absent 'netbird'
}

assert_absent() { # <regex-for-name+args>
    [[ "$(call_count "$1")" -eq 0 ]] ||
        fail "unexpected privileged/unprivileged action matched '$1'"
}

copy_install_args="-D -o root -g root -m 0644 /usr/share/digitalygo/netbird.repo /etc/yum.repos.d/netbird.repo"

# Flow preamble shared by every healthy run: template first, probe second.
flow_starts_correctly() {
    cp_line="$(first_line_of "CALL:install: ${copy_install_args}")"
    st_line="$(first_line_of "CALL:rpm-ostree: status --pending-exit-77")"
    (( cp_line < st_line )) ||
        fail "pending probe ran before the repo template was published"
}

# Executable-token scan: comment- and string-stripped source must resolve no
# consequential command from PATH.
strip_exec_tokens() {
    sed -e 's/#.*//' -e 's/"[^"]*"/""/g' -e "s/'[^']*'/''/g" -- "$1"
}
bare_command_hits() {
    # Only command positions count; bare argument occurrences such as
    # 'rpm -q --quiet netbird' or 'enable --now netbird.service' are fine.
    strip_exec_tokens "$1" |
        grep -Pn '(?:^|[;&(|]|\b(?:then|do|else|exec)\b|!)\s*(?!/usr/bin/)(sudo|rpm-ostree|rpm|systemctl|netbird|install)(?![-.\w])' || true
}
surface_hits() {
    strip_exec_tokens "$1" |
        grep -Eni -- '--setup-key|SETUP_KEY|--management-url|NB_[A-Z_]*KEY|apply-live|allow-inactive' || true
}
unit_creation_hits() {
    # No privileged-helper residue: never install a unit or craft one.
    strip_exec_tokens "$1" |
        grep -Eni -- 'service install|(cat >|tee -a|ln -s).*netbird' || true
}
reboot_hits() {
    strip_exec_tokens "$1" |
        grep -En '(^|[;&|( ])(reboot|shutdown|poweroff|systemd-run)(\b|$)' || true
}

# ---------------------------------------------------------------------------
# Shipped repo template is byte-exact official content, world-readable
# ---------------------------------------------------------------------------
printf '%s\n' '[netbird]' 'name=netbird' 'baseurl=https://pkgs.netbird.io/yum/' \
    'enabled=1' 'gpgcheck=1' 'gpgkey=https://pkgs.netbird.io/yum/repodata/repomd.xml.key' \
    'repo_gpgcheck=1' >"$work/expected.repo"
cmp -s "$repo_file" "$work/expected.repo" ||
    { diff -u "$work/expected.repo" "$repo_file" >&2 || true; fail "netbird.repo is not the exact official template"; }
[[ "$(stat -c '%a' "$repo_file")" == 644 ]] ||
    fail "netbird.repo must be mode 0644 (is $(stat -c '%a' "$repo_file"))"

# ---------------------------------------------------------------------------
# build.sh no longer bakes NetBird anywhere
# ---------------------------------------------------------------------------
hits="$(grep -Eni 'netbird|tsflags=noscripts|pkgs\.netbird\.io' "$build_sh" || true)"
[[ -z "$hits" ]] || { printf '%s\n' "$hits" >&2; fail "build.sh still references NetBird or noscriptlets"; }

# ---------------------------------------------------------------------------
# Recipe structure, pointers, fixed paths, forbidden surfaces
# ---------------------------------------------------------------------------
[[ "$(grep -Fc 'digitalygo-netbird-setup:' "$just_file")" -eq 1 ]] ||
    fail "expected exactly one digitalygo-netbird-setup recipe"
sed -n '/^digitalygo-setup:/,/^digitalygo-netbird-setup:/p' "$just_file" |
    grep -Fq "ujust digitalygo-netbird-setup" ||
    fail "digitalygo-setup lost its next-step pointer"

sed -n '/^digitalygo-netbird-setup:/,$p' "$just_file" |
    sed -e '1d' -e 's/^    //' >"$work/recipe-body.sh"
bash -n "$work/recipe-body.sh" || fail "extracted recipe body does not parse"
stripped="$(cat "$work/recipe-body.sh")"

for pin in '/usr/bin/sudo' '/usr/bin/install' '/usr/bin/rpm-ostree' '/usr/bin/systemctl' '/usr/bin/netbird'; do
    grep -Fq "$pin" <<<"$stripped" || fail "missing pinned binary $pin"
done
grep -Fq '/usr/bin/rpm -q --quiet netbird' <<<"$stripped" ||
    fail "presence probe must be the pinned 'rpm -q --quiet netbird'"
for flag in '--idempotent' '--pending-exit-77' '--property=LoadState'; do
    grep -Fq -- "$flag" <<<"$stripped" || fail "required flag missing: $flag"
done
grep -Fq '/usr/bin/systemctl is-enabled --quiet netbird.service' <<<"$stripped" ||
    fail "enabled probe must be the pinned 'systemctl is-enabled --quiet netbird.service'"
grep -Fq '/usr/bin/systemctl is-active --quiet netbird.service' <<<"$stripped" ||
    fail "active probe must be the pinned 'systemctl is-active --quiet netbird.service'"
parsed_state_hits="$(grep -En 'enable_state|active_state|\$\(/usr/bin/systemctl is-' <<<"$stripped" || true)"
[[ -z "$parsed_state_hits" ]] || { printf '%s\n' "$parsed_state_hits" >&2; fail "loaded unit must decide from probe exit statuses, not parsed text"; }
grep -Fq '/usr/bin/install -D -o root -g root -m 0644' <<<"$stripped" ||
    fail "template publication lacks the pinned install invocation"
grep -Fq 'exec /usr/bin/netbird up' <<<"$stripped" ||
    fail "enrollment must remain the user-stage 'exec /usr/bin/netbird up'"
grep -Fq '[[ "${EUID}" -eq 0 ]]' <<<"$stripped" ||
    fail "root rejection via EUID is missing"

printf '#!/bin/bash\nsudo systemctl enable x\nnetbird up\n' >"$work/bare.sample"
bare_command_hits "$work/bare.sample" >/dev/null ||
    fail "bare-command scanner missed its positive control"
hits="$(bare_command_hits "$work/recipe-body.sh")"
[[ -z "$hits" ]] || { printf '%s\n' "$hits" >&2; fail "recipe resolves a consequential command from PATH"; }

printf '#!/bin/bash\nnetbird up --setup-key leaked\n' >"$work/credential.sample"
surface_hits "$work/credential.sample" >/dev/null ||
    fail "surface scanner missed its positive control"
printf '#!/bin/bash\ncat > /etc/x/netbird.service <<EOF\nEOF\nnetbird service install\n' >"$work/unit.sample"
unit_creation_hits "$work/unit.sample" >/dev/null ||
    fail "unit-creation scanner missed its positive control"
for surface in "$just_file" "$build_sh" "$repo_file" "$work/recipe-body.sh"; do
    [[ -z "$(surface_hits "$surface")" ]] ||
        { surface_hits "$surface" >&2 || true; fail "forbidden credential/repair surface in $surface"; }
    [[ -z "$(reboot_hits "$surface")" ]] ||
        { reboot_hits "$surface" >&2 || true; fail "automatic reboot/shutdown found in $surface"; }
done
for surface in "$just_file" "$work/recipe-body.sh"; do
    [[ -z "$(unit_creation_hits "$surface")" ]] ||
        { unit_creation_hits "$surface" >&2 || true; fail "custom unit installation found in $surface"; }
done

# ---------------------------------------------------------------------------
# Rewritten execution copy: pinned paths mapped onto recording stubs
# ---------------------------------------------------------------------------
stub="$work/stub"
mkdir -p "$stub"

write_stub() { # <name> <script>
    printf '#!/usr/bin/env bash\n%s\n' "$2" >"$stub/$1"
    chmod +x "$stub/$1"
}

write_stub sudo '
    printf "%s\n" "CALL:sudo: $*" >> "${EVENTS:?}"
    [[ "${1:-}" == -- ]] && shift
    exec "$@"
'
write_stub install '
    printf "%s\n" "CALL:install: $*" >> "${EVENTS:?}"
'
write_stub rpm '
    printf "%s\n" "CALL:rpm: $*" >> "${EVENTS:?}"
    exit "${RPM_Q_RC:?}"
'
write_stub rpm-ostree '
    printf "%s\n" "CALL:rpm-ostree: $*" >> "${EVENTS:?}"
    case "$*" in
        *--pending-exit-77*)
            n="$(grep -c "^CALL:rpm-ostree: .*--pending-exit-77$" "${EVENTS:?}" || true)"
            if [[ "$n" == 0 || "$n" == 1 ]]; then
                exit "${PRE_STATUS_RC:?}"
            else
                exit "${POST_STATUS_RC:?}"
            fi
            ;;
    esac
    exit 0
'
write_stub systemctl '
    printf "%s\n" "CALL:systemctl: $*" >> "${EVENTS:?}"
    case "$*" in
        *show*--property=LoadState*)
            [[ "${SHOW_RC:-0}" != 0 ]] && exit "${SHOW_RC}"
            printf "%s\n" "${LOAD_STATE-default}"
            ;;
        *is-enabled*|*is-active*)
            # Real systemctl prints state text unless called with --quiet. This
            # harness supports quiet probes only: refuse loudly otherwise.
            # Exit status is the contract under test: 0 iff enabled or active,
            # driven by ENABLE_STATE / ACTIVE_STATE, never by printed text.
            case "$*" in
                *--quiet*) ;;
                *)
                    echo "ERROR: state probe without --quiet: $*" >&2
                    exit 64
                    ;;
            esac
            if [[ "$*" == *is-enabled* ]]; then
                [[ "${ENABLE_STATE:?}" == enabled ]]
            else
                [[ "${ACTIVE_STATE:?}" == active ]]
            fi
            ;;
    esac
'
write_stub netbird '
    printf "%s\n" "CALL:netbird: $*" >> "${EVENTS:?}"
'

sed -E \
    -e 's/\$\{EUID\}/${SIMULATED_UID}/g' \
    -e "s#/usr/bin/rpm-ostree#$stub/rpm-ostree#g" \
    -e "s#/usr/bin/systemctl#$stub/systemctl#g" \
    -e "s#/usr/bin/install#$stub/install#g" \
    -e "s#/usr/bin/sudo#$stub/sudo#g" \
    -e "s#/usr/bin/netbird#$stub/netbird#g" \
    -e "s#/usr/bin/rpm([^/-])#$stub/rpm\\1#g" \
    "$work/recipe-body.sh" >"$work/recipe-dyn.sh"
bash -n "$work/recipe-dyn.sh" || fail "transformed recipe does not parse"
# Executable text of the rewritten copy must hold zero production pins.
if sed 's/#.*//' "$work/recipe-dyn.sh" | grep -Fq '/usr/bin/'; then
    sed 's/#.*//' "$work/recipe-dyn.sh" | grep -nF '/usr/bin/' >&2 || true
    fail "transformed recipe still reaches production pinned paths"
fi
flat_recipe() {
    sed 's/\\$//' "$1" | tr '\n' ' ' | tr -s ' '
}
flat_recipe "$work/recipe-dyn.sh" >"$work/recipe-flat.txt"
grep -Fq '${SIMULATED_UID}' "$work/recipe-dyn.sh" ||
    fail "EUID simulation hook missing"
grep -Fq '${EUID}' "$work/recipe-dyn.sh" &&
    fail "raw EUID survived transformation"
    grep -Fq -- "${stub}/sudo -- ${stub}/install ${copy_install_args}" "$work/recipe-flat.txt" &&
    grep -Fq -- "${stub}/rpm-ostree install --idempotent netbird" "$work/recipe-flat.txt" ||
    fail "transformed recipe lost a required rewrite"

start_case() { # <name>: fresh event log plus fresh knobs, no cross-case state
    case_name="$1"
    : >"$events"
    set_knob_defaults
}

run_and_expect_ok() {
    set +e
    run_recipe
    rc=$?
    set -e
    (( rc == 0 )) || fail "exit $rc, output: $(cat "$out_file")"
}

run_and_expect_fail() {
    set +e
    run_recipe
    rc=$?
    set -e
    (( rc != 0 )) || fail "unexpected success despite failure expectation"
}

# ---------------------------------------------------------------------------
# Root rejection happens before anything executes
# ---------------------------------------------------------------------------
start_case "rejects root before any side effect"
SIMULATED_UID=0 run_and_expect_fail
grep -q "as root" "$out_file" || fail "root refusal diagnostic missing"
(( $(call_count ".") == 0 )) || fail "actions ran despite root refusal"

# ---------------------------------------------------------------------------
# Pass 1: package absent -> idempotent layering, forced pending answer,
# reboot instructions; service and CLI stay untouched
# ---------------------------------------------------------------------------
start_case "absent package: stages install, demands pending, no service/up"
RPM_Q_RC=1 PRE_STATUS_RC=0 POST_STATUS_RC=77
run_and_expect_ok
grep -q "Reboot" "$out_file" || fail "no reboot instruction"
grep -q "again" "$out_file" || fail "no rerun instruction"
flow_starts_correctly
first_line_of "CALL:sudo: -- ${stub}/rpm-ostree install --idempotent netbird" >/dev/null ||
    fail "missing pinned 'rpm-ostree install --idempotent netbird' layering call"
(( "$(grep -c '^CALL:rpm-ostree: status --pending-exit-77$' "$events")" == 2 )) ||
    fail "pending must be probed before and again after install"
assert_absent 'systemctl'
assert_absent 'netbird'

start_case "absent package with pending state stays inert"
RPM_Q_RC=1 PRE_STATUS_RC=77 POST_STATUS_RC=77
run_and_expect_ok
grep -q "Reboot" "$out_file" || fail "still needs the reboot instruction"
flow_starts_correctly
assert_absent 'systemctl'
assert_absent 'netbird'

start_case "absent package: post-install probe must report pending (77)"
RPM_Q_RC=1 PRE_STATUS_RC=0 POST_STATUS_RC=0
run_and_expect_fail
grep -q "pending deployment" "$out_file" ||
    fail "wrong diagnostic: $(tail -n3 "$out_file")"
assert_absent 'systemctl'
assert_absent 'netbird'

start_case "unusable probe answer aborts immediately"
RPM_Q_RC=1 PRE_STATUS_RC=3
run_and_expect_fail
grep -q "exited 3" "$out_file" || fail "diagnostic hides the bad code"
flow_starts_correctly
(( "$(call_count 'rpm')" == 0 )) ||
    fail "presence probed although the status probe already failed"
(( "$(call_count 'rpm-ostree')" == 1 )) ||
    fail "extra rpm-ostree work after a failed status probe"
assert_absent 'systemctl'
assert_absent 'netbird'

# ---------------------------------------------------------------------------
# Present but unitless: fail closed both ways, repair nothing
# ---------------------------------------------------------------------------
start_case "installed without service, nothing pending: legacy-image guidance"
RPM_Q_RC=0 LOAD_STATE=not-found PRE_STATUS_RC=0
run_and_expect_fail
grep -qi "fixed image" "$out_file" || fail "no update-the-fixed-image guidance"
flow_starts_correctly
assert_no_mutations

start_case "installed without service but deployment pending: reboot guidance"
RPM_Q_RC=0 LOAD_STATE=not-found PRE_STATUS_RC=77
run_and_expect_fail
grep -qi "reboot" "$out_file" || fail "no reboot-and-rerun guidance"
grep -qi "fixed image" "$out_file" &&
    fail "wrong advice: image update suggested although a deploy is pending"
assert_no_mutations

# ---------------------------------------------------------------------------
# Loaded unit: guarantee enabled+started, enroll as the user
# ---------------------------------------------------------------------------
start_case "loaded but disabled and inactive: enables once, then user up"
RPM_Q_RC=0 LOAD_STATE=loaded ENABLE_STATE=disabled ACTIVE_STATE=inactive
run_and_expect_ok
flow_starts_correctly
enable_line="$(first_line_of "CALL:sudo: -- ${stub}/systemctl enable --now netbird.service")"
up_line="$(first_line_of "CALL:netbird: up")"
last_line="$(wc -l <"$events")"
(( enable_line < up_line && up_line == last_line )) ||
    fail "enrollment must be the final user-stage step after enable --now"

start_case "loaded, enabled and active: no mutations, straight to enrollment"
RPM_Q_RC=0 LOAD_STATE=loaded ENABLE_STATE=enabled ACTIVE_STATE=active
run_and_expect_ok
flow_starts_correctly
grep -q "enable --now" "$events" &&
    fail "needlessly mutated an enabled+active unit"
grep -q "^CALL:netbird: up$" "$events" || fail "user-stage 'netbird up' missing"
(( "$(call_count 'netbird')" == 1 )) || fail "unexpected extra netbird calls"

# ---------------------------------------------------------------------------
# Unexpected unit states and query failures fail closed
# ---------------------------------------------------------------------------
for weird_state in masked bad-state ''; do
    start_case "unexpected LoadState (${weird_state:-empty}) fails closed"
    RPM_Q_RC=0 LOAD_STATE="$weird_state"
    run_and_expect_fail
    if [[ "$weird_state" == "" ]]; then
        grep -q "<empty>" "$out_file" || fail "empty-state diagnostic missing"
    fi
    assert_no_mutations
done

start_case "LoadState query failure aborts without acting"
RPM_Q_RC=0 LOAD_STATE="loaded" SHOW_RC=7
run_and_expect_fail
assert_no_mutations

# ---------------------------------------------------------------------------
# Fixed paths defeat hostile PATH shadowing (with working detection control)
# ---------------------------------------------------------------------------
fakebin="$work/hostile-bin"
mkdir -p "$fakebin"
printf '#!/usr/bin/env bash\nprintf "EVIL-SUDO %%s\\n" "$*"\n' >"$fakebin/sudo"
chmod +x "$fakebin/sudo"
EVIL_OUT="$(PATH="$fakebin:$stub:/usr/bin:/bin" bash --noprofile --norc \
    <(printf '#!/bin/bash\nsudo probe-marker\n'))"
grep -q "EVIL-SUDO probe-marker" <<<"$EVIL_OUT" ||
    fail "hijack detector broken: bare sudo no longer capturable"
start_case "hostile PATH cannot intercept pinned commands"
HOSTILE_PATH="$fakebin"
RPM_Q_RC=0 LOAD_STATE=loaded
run_and_expect_ok
grep -q "EVIL-SUDO" "$events" && fail "a pinned call was intercepted"
grep -q "^CALL:netbird: up$" "$events" || fail "user enrollment lost under hostile PATH"
flow_starts_correctly

echo "NetBird ujust flow: OK"
