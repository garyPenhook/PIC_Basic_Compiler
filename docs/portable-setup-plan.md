# Plan: portable toolchain discovery

## Problem
A new user who clones the repo must be able to compile without hand-editing. Today:
- `find_pic_as` (src/driver.rs) only scans `/opt/microchip/xc8/*` (Linux), picking the newest by lexical sort.
- `find_dfp` (src/driver.rs) is hardcoded to `$HOME/.mchp_packs/Microchip/<pack>/<pack_version>/xc8`, with no override and no fallback to another installed version.
- `HOME` is the only home lookup (also in src/embedded.rs), so Windows fails.
- Error messages do not say what was searched or how to fix it.

## Goals
Working compile on Linux, macOS and Windows with no edits. When something is missing, the error says exactly what to do.

## Changes (src/driver.rs and src/main.rs unless noted)

### 1. Cross-platform home directory
- Helper that falls back from `HOME` to `USERPROFILE`.
- Use it in `find_dfp` and in src/embedded.rs.

### 2. pic-as discovery order (first hit wins)
1. `--pic-as PATH`
2. `BASIL_PICAS`
3. `pic-as` on `PATH`
4. Per-platform install roots, newest version:
   - Linux: `/opt/microchip/xc8/*`
   - macOS: `/Applications/microchip/xc8/*`
   - Windows: `C:\Program Files\Microchip\xc8\*`, with `pic-as.exe`
5. Compare version folders numerically (v2.46 vs v2.5), not lexically.

### 3. Device pack discovery
1. `--dfp DIR`, then `BASIL_DFP` (points at the pack's `xc8` folder).
2. Exact pack and version from the device file, under each pack root.
3. Else the newest installed version of the same pack, with a one-line warning naming the version used.
4. Pack roots: `~/.mchp_packs/Microchip`, and the MPLAB X install's packs folder. Confirm both on a real install before hardcoding.

### 4. Error messages
- pic-as not found: list every place searched and the fix (install XC8, set `BASIL_PICAS`, pass `--pic-as`).
- Pack not found: print the expected path, the roots searched, and the fix.
- Same treatment for `xc8-cc`.

### 5. `basil --doctor`
- Prints resolved pic-as path and version, xc8-cc path, pack roots and packs found, and the devices/lib source in use.
- Exits non-zero if anything required is missing.

### 6. Docs
- README and QUICKSTART "Setup" section: install requirement, lookup order, env vars and flags, `--doctor`.
- Update `--help` in src/main.rs (currently lists only the Linux path).
- Optional: `basil.toml` for per-project path pinning (skip unless wanted).

### 7. Tests
- Unit tests for the version-sort helper and lookup order, using temp dirs and injected env values.
- Missing pack gives fallback plus warning; total miss gives the expected message.
- `cargo test --release` (`cargo build` first if lib changes).

### 8. Process
- Bump the basil version in small patch steps, one per change.
- Run `/code-review` on the diff; check fallback ordering and Windows path quoting of `-mdfp=`.

## Suggested order
1. Home helper and numeric version sort (low risk).
2. pic-as discovery.
3. Pack discovery and `--dfp`.
4. Error messages.
5. `--doctor`.
6. Docs and tests alongside each step.

## Open questions
- Windows and macOS now, or Linux only with better errors?
- Is falling back to a different pack version acceptable? It could change config-word bits versus the pinned version.
- Want the `basil.toml` option?
