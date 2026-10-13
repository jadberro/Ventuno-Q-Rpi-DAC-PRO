#!/bin/bash
D="${VENTUDAC_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
mkdir -p "$D/logs"
L="$D/logs/sweep3.log"; : > "$L"
echo 7 > /sys/module/snd_q6apm/parameters/i2s_match_type
echo 0 > /sys/module/snd_q6apm/parameters/i2s_match_idx
# pass 1: every accepted interface, no vote, both SD lines
for TI in "6 0" "6 1" "6 2" "6 3" "6 4" "5 0" "0 1" "0 2" "0 3" "0 4" "2 0" "3 0" "4 0" "4 1"; do
  set -- $TI
  for SD in 2 1 3; do bash $D/trial.sh $1 $2 $SD 0 91 >> $L 2>&1; done
done
# pass 2: type 6 idx 0-4 and type 0/5 with clock votes
CL="0x10f 0x110 0x111 0x112 0x113 0x114 0x115 0x100 0x102 0x104 0x106 0x108 0x10b 0x10d 0x300 0x301 0x302 0x303 0x304"
for TI in "6 1" "6 0" "6 2" "6 3" "6 4" "5 0" "0 1" "0 2"; do
  set -- $TI
  for C in $CL; do bash $D/trial.sh $1 $2 2 $C 91 >> $L 2>&1; done
done
echo SWEEPDONE >> $L
