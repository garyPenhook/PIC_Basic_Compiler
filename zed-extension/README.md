# PIC BASIC (basil) for Zed

Language support for the basil compiler, matching the VS Code extension.

| Piece | What it gives |
|---|---|
| `grammar/` | token-level tree-sitter grammar (case-insensitive keywords via `src/scanner.c`) |
| `languages/picbasic/` | highlighting (keyword lists from `vscode-extension/src/keywords.js`), outline, comments, brackets |
| `lsp/basil-lsp.js` | language server: `basil --check` diagnostics, hover, completion, outline (Node, no dependencies) |
| `src/lib.rs` | launches `basil-lsp` |
| `config/` | tasks (`basil: build`, `check`, `debug`, `report`, `clean`), snippets, per-project settings |

## Install

```
cargo install tree-sitter-cli        # once
zed-extension/scripts/zed-install.sh
```

Then in Zed: command palette -> `zed: install dev extension` -> choose `zed-extension/`.

Keys on `.bas` files: F7 build, Ctrl+F7 debug build, F6 check, Shift+F7 resource report.
`.zed/settings.json` (here and in `my_src/`) pins `.bas` to PIC BASIC because the Swordfish
extension claims the same suffix.

Before publishing, replace the grammar `repository` in `extension.toml` with a public URL
(for this repo: the repo URL plus `path = "zed-extension/grammar"`).
