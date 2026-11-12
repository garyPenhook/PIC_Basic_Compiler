#!/bin/bash
# build every program in this folder with basil and XC8 (-Os, -O2, -O1), print flash bytes and RAM bytes
B=/home/gary/apps/Basic_Compiler/target/release/basil
DFP=$(ls -d ~/.mchp_packs/Microchip/PIC18F-Q_DFP/*/xc8 | tail -1)
cd "$(dirname "$0")"
W=$(mktemp -d)
printf "%-12s | %7s %5s | %7s %5s | %7s %5s | %7s %5s\n" prog "basil-B" RAM "Os-B" RAM "O2-B" RAM "O1-B" RAM
for p in m*.bas; do
  p=${p%.bas}
  out=$($B $p.bas -o $W/$p.hex --report 2>&1)
  bw=$(echo "$out" | sed -n 's/.*Program: \([0-9]*\) words.*/\1/p'); [ -z "$bw" ] && bw=$(echo "$out" | sed -n 's/.*(\([0-9]*\) words.*/\1/p')
  br=$(echo "$out" | sed -n 's/.*total \([0-9]*\) bytes.*/\1/p')
  row="$((bw*2)) $br"
  for o in -Os -O2 -O1; do
    r=$(xc8-cc -mcpu=18F27Q10 -mdfp=$DFP $o -std=c99 -mno-default-config-bits -mwarn=-3 -o $W/$p$o.elf $p.c 2>&1)
    pb=$(echo "$r" | sed -n 's/.*Program space *used *[0-9A-Fa-f]*h *( *\([0-9]*\)).*/\1/p')
    db=$(echo "$r" | sed -n 's/.*Data space *used *[0-9A-Fa-f]*h *( *\([0-9]*\)).*/\1/p')
    row="$row ${pb:-ERR} ${db:-ERR}"
  done
  printf "%-12s | %7s %5s | %7s %5s | %7s %5s | %7s %5s\n" $p $row
done
rm -rf $W
