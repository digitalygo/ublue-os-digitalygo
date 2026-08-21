# mise (version manager): expose managed runtime shims (node, python, etc.) on PATH
# Shims are created under ~/.local/share/mise/shims by `mise install` / `mise use -g`.
if [ -d "$HOME/.local/share/mise/shims" ]; then
    export PATH="$HOME/.local/share/mise/shims:$PATH"
fi
