#!/bin/bash
# build every program with basil and XC8 (-Os, -O2, -O1), print flash bytes
B=/home/gary/apps/Basic_Compiler/target/release/basil
DFP=$(ls -d ~/.mchp_packs/Microchip/PIC18F-Q_DFP/*/xc8 | tail -1)
cd "$(dirname "$0")"
printf "%-8s %8s %8s %8s %8s %8s\n" prog basil xc8-Os xc8-O2 xc8-O1 xc8-O0
for p in a_algo b_dsp c_text d_ctrl; do
  bw=$($B $p.bas -o $p.hex --report 2>&1 | sed -n 's/.*Program: \([0-9]*\) words.*/\1/p'); bb=$((bw*2))
  row="$bb"
  for o in -Os -O2 -O1 -O0; do
    r=$(xc8-cc -mcpu=18F27Q10 -mdfp=$DFP $o -std=c99 -mno-default-config-bits -mwarn=-3 -o $p$o.elf $p.c 2>&1 | sed -n 's/.*Program space *used *[0-9A-Fa-f]*h *( *\([0-9]*\)).*/\1/p')
    row="$row ${r:-ERR}"
  done
  printf "%-8s %8s %8s %8s %8s %8s\n" $p $row
done
# sink equality (basil result against the value XC8 -Os produced): python3 ../../scripts/exec-test.py --basil ../../target/release/basil *.bas
