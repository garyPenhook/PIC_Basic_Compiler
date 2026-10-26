#!/usr/bin/env bash
# One-shot setup of the basil Zed environment. Safe to re-run.
#   - generates the tree-sitter parser (needs `tree-sitter` on PATH)
#   - publishes ./grammar as a local git repo and pins extension.toml to it
#   - links basil-lsp into ~/.local/bin, installs tasks, snippets and F-key bindings
# Then in Zed: command palette -> "zed: install dev extension" -> pick this zed-extension folder.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
zed_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/zed"
mirror="${XDG_DATA_HOME:-$HOME/.local/share}/basil-zed/tree-sitter-picbasic"

command -v tree-sitter >/dev/null || { echo "tree-sitter CLI not found (cargo install tree-sitter-cli)" >&2; exit 1; }
(cd "$here/grammar" && tree-sitter generate)

mkdir -p "$mirror" "$HOME/.local/bin" "$zed_cfg/snippets"
rsync -a --delete --exclude .git "$here/grammar/" "$mirror/"
(cd "$mirror" && { [ -d .git ] || git init -q; } && git add -A &&
  { git diff --cached --quiet || git -c user.name=basil -c user.email=basil@localhost commit -qm "picbasic grammar"; })
rev="$(git -C "$mirror" rev-parse HEAD)"
sed -i -E "s|^repository = \"file://.*\"|repository = \"file://$mirror\"|; s|^rev = \".*\"|rev = \"$rev\"|" "$here/extension.toml"

ln -sf "$here/lsp/basil-lsp.js" "$HOME/.local/bin/basil-lsp"
chmod +x "$here/lsp/basil-lsp.js"
cp "$here/config/snippets.json" "$zed_cfg/snippets/pic basic.json"

node - "$here/config/tasks.json" "$zed_cfg/tasks.json" <<'JS'
const fs = require('fs');
const [src, dst] = process.argv.slice(2);
const ours = JSON.parse(fs.readFileSync(src, 'utf8'));
const have = fs.existsSync(dst) ? JSON.parse(fs.readFileSync(dst, 'utf8')) : [];
const labels = new Set(ours.map((t) => t.label));
fs.writeFileSync(dst, JSON.stringify(have.filter((t) => !labels.has(t.label)).concat(ours), null, 2) + '\n');
JS
echo "done. rev $rev"
