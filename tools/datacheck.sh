#!/bin/bash
# Requires the optional debug modules from kernel/ (sysfs knobs under /sys/module/snd_q6apm/parameters).
# usage: datacheck.sh <sd> <wav>
SD=$1; W=$2; D="${VENTUDAC_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
P=/sys/module/snd_q6apm/parameters
echo 7 > $P/i2s_match_type; echo 0 > $P/i2s_match_idx
echo 3 > $P/i2s_ovr_type; echo 0 > $P/i2s_ovr_idx; echo $SD > $P/i2s_ovr_sd
for n in 90 91 92 93 94; do amixer -c0 -q cset numid=$n 0; done; amixer -c0 -q cset numid=91 1
i2cset -f -y 0 0x4c 0 0; i2cset -f -y 0 0x4c 0x41 0x07; i2cset -f -y 0 0x4c 0x3b 0x11; i2cset -f -y 0 0x4c 0x02 0x00; i2cset -f -y 0 0x4c 0x03 0x00
timeout 10 aplay -q -D hw:0,2 -d 3 $W &
sleep 1.5
echo -n "sd=$SD $(basename $W): 76=$(i2cget -f -y 0 0x4c 0x76) 6c(automute flags)=$(i2cget -f -y 0 0x4c 0x6c) 5e=$(i2cget -f -y 0 0x4c 0x5e) 03=$(i2cget -f -y 0 0x4c 0x03) 3d=$(i2cget -f -y 0 0x4c 0x3d)"; echo
wait
