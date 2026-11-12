#!/bin/bash
# Quick gate for code-generation work: build, then run the simulator programs that have caught optimiser faults,
# and print the bench/large sizes for both cores. It does not replace `BASIL_MDB=1 cargo test --release`.
#
#   scripts/gate.sh          PIC18 set in basil-sim (about a minute)
#   scripts/gate.sh 16       also the PIC16F17146 set in MDB (a few minutes more)
#   scripts/gate.sh sizes    sizes only
#
# PIC18 set: tests/exec, bench/large, and the library models (tests/exec_rtcc, exec_glcd_*, exec_epaper, exec_pins):
# the models are whole library modules and caught a tail merged across two routines that tests/exec did not.
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1
B=$root/target/release/basil
cargo build --release > "${TMPDIR:-/tmp}/gate-build.$$" 2>&1 || { grep -E '^(warning|error)' -A6 "${TMPDIR:-/tmp}/gate-build.$$"; rm -f "${TMPDIR:-/tmp}/gate-build.$$"; echo "build failed"; exit 1; }
rm -f "${TMPDIR:-/tmp}/gate-build.$$"
[ -x "$B" ] || { echo "no $B"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

run() { # label, then exec-test.py arguments
  local label=$1; shift
  if python3 scripts/exec-test.py --basil "$B" "$@" > "$T/out" 2>&1; then
    echo "ok    $label ($(grep -c '^ok' "$T/out") programs)"
  else
    echo "FAIL  $label"; grep -v '^ok' "$T/out" | tail -25; fail=1
  fi
}

sizes() {
  local dev unit total w row
  for dev in 18F27Q10 16F18346; do
    total=0; row=""
    for p in a_algo b_dsp c_text d_ctrl; do
      if [ $dev = 16F18346 ]; then
        sed -e "s/^\(\s*Device\s*=\s*\)\S*/\1$dev/I" -e 's/^Clock = 64/Clock = 32/' -e 's/HFINTOSC_64MHZ/HFINT32/' bench/large/$p.bas > "$T/$p.bas"
      else
        cp bench/large/$p.bas "$T/$p.bas"
      fi
      w=$("$B" -S --report "$T/$p.bas" -o "$T/$p.S" 2>&1 | sed -n 's/.*Program: \([0-9]*\) words.*/\1/p')
      [ -n "$w" ] || { echo "FAIL  bench/large/$p for $dev does not build"; fail=1; w=0; }
      case $dev in 18F*) w=$((w * 2)); unit=bytes;; *) unit=words;; esac
      total=$((total + w)); row="$row $p $w "
    done
    echo "$dev $unit: $row total $total"
  done
}

if [ "$1" != sizes ]; then
  for flags in "" "-O0"; do
    run "PIC18 tests/exec + bench/large ${flags:-optimised}" --flags="$flags" tests/exec/*.bas bench/large/*.bas
    run "PIC18 library models ${flags:-optimised}" --flags="$flags" tests/exec_rtcc/lib_rtcc_model.bas tests/exec_rtcc/lib_rtccspi_model.bas \
      tests/exec_glcd_ks/lib_*.bas tests/exec_glcd_t69/lib_*.bas tests/exec_glcd_st79/lib_*.bas tests/exec_epaper/lib_*.bas tests/exec_pins/lib_*.bas
    run "PIC18F16Q41 I2C model ${flags:-optimised}" --flags="$flags" --device 18F16Q41 tests/exec_rtcc/lib_rtcc_model_hw.bas
  done
fi
if [ "$1" = 16 ]; then
  # The list of tests/exec programs that also run on the enhanced mid-range core lives in tests/backend.rs.
  list=$(sed -n '/^const P16_PORTABLE/,/^];/p' tests/backend.rs | grep -o '"[a-z0-9_]*"' | tr -d '"' | sed 's|.*|tests/exec/&.bas|')
  cp "$B" "$T/basil16"; B=$T/basil16     # a private copy, so a build can go on meanwhile
  for flags in "" "-O0"; do
    run "PIC16F17146 portable + exec_p16 + bench/large ${flags:-optimised}" --flags="$flags" --device 16F17146 $list tests/exec_p16/*.bas bench/large/*.bas
  done
  B=$root/target/release/basil
fi
sizes
exit $fail
