#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper_file="${repository_root}/system_files/usr/bin/pi"
temporary_home="$(mktemp -d)"
trap 'rm -rf "$temporary_home"' EXIT

mkdir -p "$temporary_home/bin" "$temporary_home/.local/libexec/pi/node_modules/@earendil-works/pi-coding-agent/dist"
cat >"$temporary_home/bin/mise" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*"
EOF
chmod +x "$temporary_home/bin/mise"
touch "$temporary_home/.local/libexec/pi/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"

result="$(HOME="$temporary_home" PATH="$temporary_home/bin:/usr/bin:/bin" sh "$wrapper_file" --version)"
expected="exec node@24 -- node $temporary_home/.local/libexec/pi/node_modules/@earendil-works/pi-coding-agent/dist/cli.js --version"
[[ "$result" == "$expected" ]]
