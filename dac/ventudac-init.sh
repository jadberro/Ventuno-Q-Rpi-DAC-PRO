#!/bin/bash
# PCM5242 init for 3-wire (no MCLK) I2S slave, IQaudio DAC Pro. arg1 = volume reg (0x30=0dB, 0x48=-12dB)
V=${1:-0x48}
c() { i2cset -f -y 0 0x4c $1 $2; }
c 0x00 0x00
c 0x01 0x11; sleep 0.05; c 0x01 0x00      # reset
c 0x02 0x10                                # standby
c 0x25 0x7d                                # ignore clock-detect errors (no SCK)
c 0x0d 0x10                                # PLL ref = BCK
c 0x04 0x01                                # PLL enable
c 0x28 0x00                                # I2S, 16-bit
c 0x41 0x00                                # auto-mute off
c 0x08 0x3f                                # GPIO1-6 outputs
for g in 0x50 0x51 0x52 0x53 0x54 0x55; do c $g 0x02; done
c 0x56 0x3f                                # drive them high
c 0x3d $V; c 0x3e $V
c 0x00 0x01; c 0x01 0x00; c 0x02 0x00; c 0x00 0x00   # page1: line out 2Vrms (0 dB gain)
c 0x03 0x00                                # unmute
c 0x02 0x00                                # run
