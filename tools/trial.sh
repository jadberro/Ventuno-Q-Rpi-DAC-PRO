#!/bin/bash
# Requires the optional debug modules from kernel/ (sysfs knobs under /sys/module/snd_q6apm/parameters).
# usage: sudo trial.sh <type|-1> <idx|-1> <sd|-1> <clkid hex|0> [route numid=91] [ws -1]
T=$1; I=$2; SD=$3; C=$4; NID=${5:-91}; WS=${6:--1}
D="${VENTUDAC_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
P=/sys/module/snd_q6apm/parameters; Q=/sys/module/q6apm_lpass_dais/parameters
echo $T > $P/i2s_ovr_type; echo $I > $P/i2s_ovr_idx; echo $SD > $P/i2s_ovr_sd; echo $WS > $P/i2s_ovr_ws
echo $((C)) > $Q/lpi_clk_id
for n in 90 91 92 93 94; do amixer -c0 -q cset numid=$n 0; done
amixer -c0 -q cset numid=$NID 1
i2cset -f -y 0 0x4c 0 0; i2cset -f -y 0 0x4c 0x0d 0x10; i2cset -f -y 0 0x4c 0x02 0x00
B=$(for r in $(seq 0x58 0x5f) 0x76; do i2cget -f -y 0 0x4c $r; done | tr '\n' ' ')
dmesg -C
timeout 10 aplay -q -D hw:0,2 -d 3 $D/tone.wav > $D/aplay.log 2>&1 &
AP=$!
sleep 1.2
A=$(for r in $(seq 0x58 0x5f) 0x76; do i2cget -f -y 0 0x4c $r; done | tr '\n' ' ')
wait $AP; RC=$?
M=$(dmesg | grep -E "ventudac|rror|fail" | sed 's/^\[[^]]*\] //' | tr '\n' '|' | cut -c1-400)
CH=same; [ "$B" != "$A" ] && CH=CHANGED
echo "T=$T I=$I SD=$SD C=$C nid=$NID ws=$WS | aplay=$RC $(head -c 120 $D/aplay.log | tr '\n' ' ') | dac $CH [$B] -> [$A] | $M"
