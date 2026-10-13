#!/bin/bash
# Install the userspace half of the JHAT I2S DAC support on an Arduino Ventuno Q
# (Ubuntu 24.04, linux-qcom 6.8.0-1084, alsa-conf-qcom 1.18).
# Device-tree step is separate (see devicetree/README.md) and must be done first.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
TPLG_SRC=/usr/share/alsa/topology/qcs8300/monaco-gertrude-tplg.conf
TPLG_BIN=/lib/firmware/qcom/qcs8300/monaco-gertrude-tplg.bin
UCM=/usr/share/alsa/ucm2/Qualcomm/qcs8300/monaco-gertrude/HiFi.conf
BK=/var/backups/ventuno-jhat-dac; mkdir -p $BK
command -v alsatplg >/dev/null || apt-get install -y alsa-utils
command -v i2cset  >/dev/null || apt-get install -y i2c-tools

echo "== Bluetooth off (shares the TXS0104E level shifter with JHAT pins 37/38/40)"
rfkill block bluetooth || true
systemctl disable --now bluetooth 2>/dev/null || true

echo "== Topology"
[ -f $BK/monaco-gertrude-tplg.bin ] || cp $TPLG_BIN $BK/
patch -o /tmp/jhat-tplg.conf $TPLG_SRC "$HERE/topology/monaco-gertrude-tplg.conf.diff"
alsatplg -c /tmp/jhat-tplg.conf -o /tmp/jhat-tplg.bin 2>/dev/null
dpkg-divert --list $TPLG_BIN | grep -q local || dpkg-divert --local --no-rename --divert $TPLG_BIN.distrib --add $TPLG_BIN
install -m 644 /tmp/jhat-tplg.bin $TPLG_BIN

echo "== UCM"
[ -f $BK/HiFi.conf ] || cp $UCM $BK/
grep -q JHATDAC $UCM || patch $UCM "$HERE/ucm/HiFi.conf.diff"
dpkg-divert --list $UCM | grep -q local || dpkg-divert --local --no-rename --divert $UCM.distrib --add $UCM

echo "== PCM5242 init service"
install -m 755 "$HERE/dac/ventudac-init.sh" /usr/local/sbin/ventudac-init.sh
install -m 644 "$HERE/dac/ventudac.service" /etc/systemd/system/ventudac.service
systemctl daemon-reload; systemctl enable ventudac.service

echo "Done. Reboot, then pick 'RPi DAC Pro (JHAT)' as the output (wpctl status / wpctl set-default <id>)."
echo "Backups of the stock files are in $BK"
