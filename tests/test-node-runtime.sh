#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
setup_file="${repository_root}/system_files/usr/share/ublue-os/just/60-custom.just"
profile_file="${repository_root}/system_files/etc/profile.d/mise.sh"
wrapper_file="${repository_root}/system_files/usr/bin/pi"

[[ "$(grep -Fc 'mise install node@24' "$setup_file")" -eq 1 ]]
[[ "$(grep -Fc 'mise use -g node@24' "$setup_file")" -eq 1 ]]
[[ "$(grep -Fc 'node@22' "$setup_file")" -eq 0 ]]
[[ "$(grep -Fc 'brew postinstall ca-certificates' "$setup_file")" -eq 1 ]]
[[ "$(grep -Fc 'mise exec node@24 -- npm install --prefix "${HOME}/.local/libexec/pi"' "$setup_file")" -eq 1 ]]
[[ "$(grep -Fc 'npm config set prefix' "$setup_file")" -eq 0 ]]
[[ "$(grep -Fc 'export PATH="$HOME/.local/share/mise/shims:$PATH"' "$profile_file")" -eq 1 ]]
[[ -x "$wrapper_file" ]]
[[ "$(grep -Fc 'exec mise exec node@24 -- node' "$wrapper_file")" -eq 1 ]]
[[ "$(grep -Fc '.local/libexec/pi/node_modules/@earendil-works/pi-coding-agent/dist/cli.js' "$wrapper_file")" -eq 1 ]]
[[ "$(grep -Fc "grep -Fq '.local/opt/node22'" "$setup_file")" -eq 1 ]]
