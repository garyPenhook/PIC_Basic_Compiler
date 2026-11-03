#!/bin/sh
# basil-sim-only tests: programs that need a stimulus file. Run after `cargo build --release`.
# Usage: tests/sim/run.sh
set -e
cd "$(dirname "$0")/../.."
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cp tests/sim/serial_rx.bas "$w/"
./target/release/basil --keep-vars "$w/serial_rx.bas" >/dev/null
out=$(./target/release/basil-sim "$w/serial_rx.hex" --device 18F27Q10 --stim tests/sim/serial_rx.stim.toml \
    --dump SRX_B0,SRX_B1,SRX_B2,SRX_B3,SRX_FERR 2>/dev/null)
want="SRX_B0 = 72
SRX_B1 = 105
SRX_B2 = 33
SRX_B3 = 63
SRX_FERR = 4
tx1: Hi!"
for l in $(printf '%s\n' "$want" | tr ' ' '_'); do
    echo "$out" | tr ' ' '_' | grep -q "^$l" || { echo "FAIL serial_rx: missing '$l'"; echo "$out"; exit 1; }
done
echo "PASS serial_rx"
