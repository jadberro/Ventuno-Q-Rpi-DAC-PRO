# Device-tree change

The Ventuno Q boots with `combined-dtb.dtb` from the `dtb_a` partition (`/dev/mmcblk0p18`, FAT16).
That file is 20 FDT blobs concatenated back to back. The bootloader picks the one matching the board's
`qcom,msm-id` / `qcom,board-id`. On our board (model `Monaco Monza addons`) it is FDT #16.

`jhat-i2s1.dts.diff` is a diff against the decompiled (`dtc -s`) stock FDT. It:

1. **Adds `lpi_i2s1-active-state`** to the LPASS LPI pin controller (`3440000.pinctrl`):
   gpio6 → `i2s1_clk` (JHAT pin 12), gpio7 → `i2s1_ws` (pin 35), gpio9 → `i2s1_data` (pin 40, DAC input).
   These LPI pads are TLMM eGPIOs 116/117/119; they are already owned by LPASS (`egpio`) on stock.
2. **Appends that state to `/sound` `pinctrl-0`**, so the pads are muxed when the card probes.
3. **Adds a dummy codec** `spdif-dit-dacpro` (`linux,spdif-dit`) and a `dacpro-playback-dai-link`:
   cpu = `q6apmbedai LPI_MI2S_RX_1` (id 160), platform = `q6apm`, `format = "i2s"`.
   The machine driver (`sc8280xp.c`) then sets the CPU DAI to `BP_FP` (SoC is bit-clock and frame master),
   which makes `audioreach_i2s_set_media_format()` send `ws_src = INTERNAL` to the DSP.
4. Leftovers from the bring-up, harmless and not required:
   - `sweep0/2/3` DAI links for LPI_MI2S_RX_0/2/3 (ids 158/162/164).
   - A `ti,pcm5122@4c` node on the JHAT I2C bus. It makes `snd-soc-pcm512x` probe the chip, but it is not in any DAI link. The DAC is configured from userspace by `dac/ventudac-init.sh`.

The diff hard-codes phandles `0x400-0x402` and references existing phandles (`0x295` q6apm, `0x297` q6apmbedai,
`0x2f3` regulator). It only applies to the exact DTB build shipped on our board. The script refuses to apply it if those
phandles are already in use.

## Apply

```bash
sudo mkdir -p /mnt/dtb_a && sudo mount /dev/mmcblk0p18 /mnt/dtb_a
cp /mnt/dtb_a/combined-dtb.dtb ~/combined-dtb.dtb.orig          # keep this!
python3 patch_combined_dtb.py --in ~/combined-dtb.dtb.orig --out ~/combined-dtb.new.dtb
sudo cp ~/combined-dtb.new.dtb /mnt/dtb_a/combined-dtb.dtb && sync && sudo umount /mnt/dtb_a
sudo reboot
```

After the reboot, `/sys/kernel/debug/pinctrl/3440000.pinctrl/pinmux-pins` should show gpio6/7/9 owned by `sound`
with functions `i2s1_clk` / `i2s1_ws` / `i2s1_data`.

Restore: copy `combined-dtb.dtb.orig` back to the partition and reboot.
