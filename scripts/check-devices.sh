#!/bin/sh
# Verify every device description in devices/:
#   1. regenerate it from the Microchip pack it names and diff against the committed file
#      (catches hand edits and a pack that changed under us);
#   2. run the data sheet cross-check (devgen check) against devices/<name>.expect.toml.
# Exit status is non-zero if anything differs or disagrees.
set -eu
cd "$(dirname "$0")/.."
PACKS=${MCHP_PACKS:-$HOME/.mchp_packs}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cargo build -q -p devgen
status=0
for dev in devices/*.toml; do
  case "$dev" in *.expect.toml) continue ;; esac
  name=$(basename "$dev" .toml)
  pack=$(sed -n 's/^pack = "\(.*\)"$/\1/p' "$dev" | head -1)
  ver=$(sed -n 's/^pack_version = "\(.*\)"$/\1/p' "$dev" | head -1)
  src=$(sed -n 's/^source = "\(.*\)"$/\1/p' "$dev" | head -1)
  pic="$PACKS/Microchip/$pack/$ver/$src"
  if [ ! -f "$pic" ]; then echo "$name: pack file not found: $pic" >&2; status=1; continue; fi
  ./target/debug/devgen gen "$pic" "$tmp/$name.toml" 2>/dev/null
  if cmp -s "$dev" "$tmp/$name.toml"; then echo "$name: up to date with $pack $ver"; else echo "$name: DIFFERS from regenerated output" >&2; status=1; fi
  exp="devices/$name.expect.toml"
  if [ -f "$exp" ]; then ./target/debug/devgen check "$dev" "$exp" || status=1; else echo "$name: no $exp (data sheet cross-check missing)" >&2; status=1; fi
done
exit $status
