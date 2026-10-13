# I2S Audio HATs on Arduino Ventuno Q (RPi DAC Pro / TI PCM5242)

Working playback from a **Raspberry Pi DAC Pro / IQaudio DAC Pro (TI PCM5242)** HAT plugged into the **Arduino Ventuno Q** (ABX00181, Qualcomm QCS8275 "Monaco") 40-pin JHAT header. Shows up as a standard PipeWire audio output and verified with high-fidelity playback.

As shipped, the board's audio stack has no backend that drives the JHAT I2S pins, so no I2S HAT works out of the box. This repository documents the missing piece: **which Qualcomm AudioReach I2S interface drives those pins**, along with the device tree diff, ALSA topology, UCM configuration, and automatic startup service to reproduce the working setup.

> **Tested Environment:**
> - **Board:** Arduino Ventuno Q (ABX00181, DT model: `Qualcomm Technologies, Inc. Monaco Monza addons`, sound card: `monaco-gertrude`)
> - **OS:** Ubuntu 24.04.5 LTS (ARM64)
> - **Kernel:** `linux-qcom 6.8.0-1084.89` (`6.8.0-1084-qcom`)
> - **ALSA:** `alsa-conf-qcom 1.18`
> - **Audio HAT:** Raspberry Pi DAC Pro / IQaudio DAC Pro (TI PCM5242 stereo DAC)

---

## TL;DR: The Key Discovery

The 40-pin JHAT I2S pins are routed to Qualcomm LPASS Low Power Island (LPI) **"I2S1"**:

| JHAT Pin | RPi Pin Name | SoC Pad | LPI Pin / Function | Purpose |
|:---:|:---|:---|:---|:---|
| **12** | GPIO18 PCM_CLK | `MD_GPIO_116` | gpio6 `i2s1_clk` | Bit Clock (BCK) |
| **35** | GPIO19 PCM_FS | `MD_GPIO_117` | gpio7 `i2s1_ws` | Word Select / Frame Sync (LRCK) |
| **38** | GPIO20 PCM_DIN | `MD_GPIO_118` | gpio8 `i2s1_data` (SD0) | Capture Data (DIN) |
| **40** | GPIO21 PCM_DOUT | `MD_GPIO_119` | gpio9 `i2s1_data` (SD1) | Playback Data to DAC (DOUT) |

The ADSP's AudioReach I2S endpoint token values that drive those physical pads are:

```
AR_TKN_U32_MODULE_HW_IF_TYPE  3     (lpaif_type = 3)
AR_TKN_U32_MODULE_HW_IF_IDX   0     (intf_idx = 0)
AR_TKN_U32_MODULE_SD_LINE_IDX 2     (sd_line_idx = 2 -> SD1 = pin 40)
```

For comparison on the same board, the stock topology uses:
- **(7, 0, SD0)** for HDMI Audio (ADV7535 bridge on LPI I2S4)
- **(1, 0)** for the onboard MAX98090 speaker/mic codec (LPI quad MI2S)

Earlier attempts using `(0, 1)` or `(7, x)` were accepted by the DSP firmware but drove different physical lines, leaving the header silent. Interface `(3, 0, SD1)` is the exact match for the JHAT header.

---

## Repository Contents

| Path | Description |
|:---|:---|
| [`devicetree/`](devicetree/) | Diff (`jhat-i2s1.dts.diff`) and automated patching script (`patch_combined_dtb.py`) for `/dev/mmcblk0p18` (`dtb_a` partition). Configures LPI I2S1 pinmux, a dummy codec (`spdif-dit-dacpro`), and DAI link `LPI_MI2S_RX_1` (id 160). |
| [`topology/monaco-gertrude-tplg.conf.diff`](topology/monaco-gertrude-tplg.conf.diff) | Adds AudioReach graph backends (sub-graph, container, logger, `i2s_rx` module, mixer, and routes) for `LPI_MI2S_RX_1` targeting `(3, 0, 2)`. Compiled into binary topology using `alsatplg`. |
| [`ucm/HiFi.conf.diff`](ucm/HiFi.conf.diff) | Adds UCM device `JHATDAC` on `hw:CARD,2` (`MultiMedia3`). Configures mutual exclusivity with HDMI and sets default routing. |
| [`dac/ventudac-init.sh`](dac/ventudac-init.sh) | Direct I2C initialization script configuring the TI PCM5242 registers for 3-wire I2S (deriving its PLL from BCK without MCLK). |
| [`dac/ventudac.service`](dac/ventudac.service) | Systemd unit running `ventudac-init.sh` automatically at boot after sound initialization. |
| [`install.sh`](install.sh) | One-step installer for userspace: applies topology + UCM changes (protected by `dpkg-divert`) and enables the DAC service. |
| [`kernel/0001-ventudac-audioreach-debug-knobs.patch`](kernel/0001-ventudac-audioreach-debug-knobs.patch) | **Optional** debug patch for `snd-q6apm` / `q6apm-lpass-dais` adding runtime sysfs knobs to sweep I2S interfaces. **Not needed for normal operation.** |
| [`tools/`](tools/) | Discovery tools used to uncover the mapping: `bitbang.py`, `trial.sh`, `sweep3.sh`, `datacheck.sh`. |

---

## Step-by-Step Installation Guide

### Prerequisites
Make sure required build tools are installed on the Ventuno Q:
```bash
sudo apt-get update
sudo apt-get install -y device-tree-compiler alsa-utils i2c-tools patch python3
```

---

### Step 1: Disable Bluetooth
> [!IMPORTANT]
> JHAT pins 37, 38, and 40 share a level shifter (TXS0104E, U21) with the Bluetooth UART. To prevent electrical contention on the I2S lines, Bluetooth must be disabled:

```bash
sudo rfkill block bluetooth
sudo systemctl disable --now bluetooth
```
*(This is also automated during `sudo ./install.sh`).*

---

### Step 2: Patch Device Tree

The Ventuno Q boots with `combined-dtb.dtb` on the FAT16 `dtb_a` partition (`/dev/mmcblk0p18`). The bootloader selects FDT #16 matching the `Monaco Monza addons` board ID.

1. Mount the DTB partition and make a backup:
   ```bash
   sudo mkdir -p /mnt/dtb_a
   sudo mount /dev/mmcblk0p18 /mnt/dtb_a
   cp /mnt/dtb_a/combined-dtb.dtb ~/combined-dtb.dtb.orig
   ```

2. Run the patcher script:
   ```bash
   python3 devicetree/patch_combined_dtb.py --in ~/combined-dtb.dtb.orig --out ~/combined-dtb.new.dtb
   ```

3. Copy the patched DTB back and reboot:
   ```bash
   sudo cp ~/combined-dtb.new.dtb /mnt/dtb_a/combined-dtb.dtb
   sync
   sudo umount /mnt/dtb_a
   sudo reboot
   ```

4. Verify after reboot:
   ```bash
   sudo cat /sys/kernel/debug/pinctrl/3440000.pinctrl/pinmux-pins | grep -E "gpio[679]"
   ```
   You should see `gpio6`, `gpio7`, and `gpio9` owned by `sound` with functions `i2s1_clk`, `i2s1_ws`, and `i2s1_data`.

*(To restore original DTB: mount `/dev/mmcblk0p18`, copy `~/combined-dtb.dtb.orig` back to `/mnt/dtb_a/combined-dtb.dtb`, and reboot).*

---

### Step 3: Install Userspace Stack (Topology, UCM, DAC Service)

Run the automated installer script:
```bash
sudo ./install.sh
```

What `install.sh` does:
1. Turns off Bluetooth to free the shared level shifter.
2. Compiles `topology/monaco-gertrude-tplg.conf.diff` using `alsatplg` and installs it to `/lib/firmware/qcom/qcs8300/monaco-gertrude-tplg.bin`.
3. Patches ALSA UCM `/usr/share/alsa/ucm2/Qualcomm/qcs8300/monaco-gertrude/HiFi.conf`.
4. Registers `dpkg-divert` on both files so system package updates (`alsa-conf-qcom`) won't overwrite them.
5. Installs and enables `ventudac.service` to initialize the PCM5242 at boot.

After running `install.sh`, reboot the board:
```bash
sudo reboot
```

---

### Step 4: Verification & Audio Playback

#### 1. Check DAC Detection
Check that the PCM5242 is responding on I2C bus 0 at address `0x4c`:
```bash
i2cdetect -y -r 0
# Address 4c should show "4c" or "UU"
```

Verify the DAC status register:
```bash
i2cget -f -y 0 0x4c 0x76
# Expected output: 0x85 (Run state)
```

#### 2. Test Audio with ALSA (Bypass Sound Server)
Unmute and route `MultiMedia3` directly to `LPI_MI2S_RX_1`:
```bash
amixer -c0 cset name='LPI_MI2S_RX_1 Audio Mixer MultiMedia3' 1
speaker-test -D hw:0,2 -c 2 -r 48000 -t sine -f 1000
# or play a 48kHz 16-bit WAV file:
# aplay -D hw:0,2 your-audio-48k-s16.wav
```

#### 3. Select in PipeWire
List available audio devices:
```bash
wpctl status
```
Find **"Built-in Audio RPi DAC Pro (JHAT) + HDMI playback"** and set it as default:
```bash
wpctl set-default <ID>
```
Verify the active port is `JHATDAC`. Audio from browsers, media players, or Spotify will now stream through the DAC HAT.

---

## How It Works (Signal Path)

```
PipeWire Sink (UCM Device "JHATDAC", hw:0,2)
  │
  ▼
ASoC Front-End (FE) MultiMedia3
  │
  ▼
DPCM Mixer Control: "LPI_MI2S_RX_1 Audio Mixer MultiMedia3"
  │
  ▼
Back-End (BE) LPI_MI2S_RX_1 (DAI ID 160, q6apm-lpass-dais)
  │ Machine driver sc8280xp_snd_hw_params(): set_fmt(cpu, BP_FP)
  │ -> SoC acts as Bit-Clock and Frame-Sync Master
  ▼
AudioReach DSP Graph (loaded from monaco-gertrude-tplg.bin):
  [stream2.logger1] -> [device160.logger1] -> [device160.i2s_rx1 module]
  PARAM_ID_I2S_INTF_CFG:
    - lpaif_type   = 3
    - intf_idx     = 0
    - sd_line_idx  = 2
    - ws_src       = 1 (INTERNAL)
  │
  ▼
Qualcomm LPASS LPI I2S1 Controller
  │ LPI pinctrl gpio6/7/9 (functions i2s1_clk, i2s1_ws, i2s1_data)
  │ eGPIO pads 116 / 117 / 119
  ▼
TXS0108E / TXS0104E Voltage Level Shifters (3.3V)
  │
  ▼
40-Pin JHAT Header:
  - Pin 12: BCK  (1.536 MHz)
  - Pin 35: LRCK (48 kHz)
  - Pin 40: DATA (PCM SD1)
  │
  ▼
TI PCM5242 Stereo DAC (Raspberry Pi DAC Pro)
  - 3-wire I2S slave mode
  - Internal PLL locked to BCK
  - Analog output to RCA / 3.5mm headphone jack
```

---

## TI PCM5242 Register Configuration (3-Wire I2S)

Because the Raspberry Pi DAC Pro has no crystal oscillator and the JHAT header does not carry MCLK, the PCM5242 must generate its internal clock by locking its PLL to the bit clock (BCK).

The configuration applied by [`dac/ventudac-init.sh`](dac/ventudac-init.sh):

| Register | Value | Description / Purpose |
|:---:|:---:|:---|
| `0x01` | `0x11` &rarr; `0x00` | Full chip reset |
| `0x02` | `0x10` | Enter standby |
| `0x25` | `0x7D` | Ignore FS/BCK/SCK halt and clock-detection errors (since SCK is absent) |
| `0x0D` | `0x10` | Set PLL reference clock source = BCK |
| `0x04` | `0x01` | Enable PLL |
| `0x28` | `0x00` | Audio format: Standard I2S, 16-bit |
| `0x41` | `0x00` | Disable auto-mute (leaving auto-mute on resulted in silence) |
| `0x08`, `0x50`..`0x55` | `0x3F`, `0x02` | Configure PCM5242 GPIO 1-6 as outputs |
| `0x56` | `0x3F` | Drive GPIO 1-6 high (required to enable DAC Pro's analog output stage) |
| `0x3D`, `0x3E` | `0x30` / `0x48` | Digital volume control (`0x30` = 0 dB, `0x48` = -12 dB) |
| Page 1 `0x02` | `0x00` | Set Line-Out 2Vrms (0 dB gain) |
| `0x03` | `0x00` | Unmute digital volume |
| `0x02` | `0x00` | Transition to run mode |

**Healthy operating state registers:**
- Reg `0x76` = `0x85` (Operating state = Run, DAC active)
- Reg `0x5B` = `0x30` (48 kHz sample rate detected)
- Reg `0x5C`/`0x5D` = `0x00`/`0x20` (BCK ratio = 32·fs)
- Reg `0x04` bit 4 = `0` (PLL locked)

---

## Technical Background: How the Mapping Was Found

Initial bring-up with trial device tree changes and a binary-patched `snd-q6apm.ko` showed a healthy audio graph in ALSA: routes switched, `aplay` paced at exactly 48 kHz, and DSP commands were accepted with status 0. However, the DAC pins remained completely idle.

We systematically isolated the issue in 6 steps:

1. **Kernel Driver Audit:**
   Inspected Ubuntu `linux-qcom 6.8.0-1084.89` source. `sc8280xp_snd_hw_params()` already includes handling for `LPI_MI2S_RX_0 ... LPI_MI2S_TX_4`, and `audioreach_i2s_set_media_format()` correctly sets `ws_src = INTERNAL` when formatted as `BP_FP`. The kernel driver code was already fully capable.
2. **Pad Ownership Verification:**
   Verified via `/sys/kernel/debug/gpio` that pads 116–119 were configured as `egpio` (LPASS-owned). `/sys/kernel/debug/pinctrl/3440000.pinctrl/` confirmed `gpio6`, `gpio7`, and `gpio9` were muxed to `i2s1_*` and claimed by `sound`. Pinmux was correct.
3. **Electrical Path Verification (Direct Bit-Banging):**
   To rule out board hardware defects or level-shifter tri-stating, [`tools/bitbang.py`](tools/bitbang.py) directly accessed LPI TLMM registers (`0x3440000`) via `/dev/mem`, switched gpio6/7/9 into output mode, and manually toggled BCK/LRCK/DATA. The PCM5242 clock-detect registers immediately registered clock transitions. This proved the traces, level shifters, header, and DAC were fully functional.
4. **Live Interface Parameter Sweep:**
   Using the debug patch ([`kernel/0001-ventudac-audioreach-debug-knobs.patch`](kernel/0001-ventudac-audioreach-debug-knobs.patch)), we exposed sysfs knobs to live-override `lpaif_type`, `intf_idx`, and `sd_line_idx` without recompiling topologies or rebooting. Using [`tools/sweep3.sh`](tools/sweep3.sh) and the PCM5242 status registers as a live detector:
   - DSP accepted interfaces: `(0, 1)`, `(0, 2)`, `(1, 0)`, `(2, 0)`, **`(3, 0)`**, `(5, 0)`, `(6, 0..4)`, `(7, 0)`.
   - **Only interface `(3, 0)`** caused the PCM5242 to lock to clocks (`reg 0x76 = 0x85`).
   - Using auto-mute bit flags as a data detector ([`tools/datacheck.sh`](tools/datacheck.sh)), SD line 2 transmitted audio data while SD line 1 was quiet, matching pin 40 = DATA1.
5. **Acoustic Optimization:**
   Eliminated initial crackle by refining auto-mute flags and PLL lock settings, achieving clear 1 kHz test tones and full stereo music playback via PipeWire.
6. **Production Packaging:**
   Consolidated the findings into a clean topology diff, UCM profile, boot service, and non-destructive DTB patching tool.

---

## Known Notes & Caveats

- **HDMI Audio & DAC:** On this sound card, HDMI audio and the JHAT DAC both utilize `MultiMedia3`. The UCM profile configures them as mutually exclusive devices. Select one active output port at a time.
- **DTB Updates:** If a future system package update rewrites `/dev/mmcblk0p18` (`dtb_a`), re-run Step 2 to re-apply the DTB patch.
- **Other I2S HATs:** Other audio HATs that require MCLK (e.g. codecs without an internal PLL) or HATs configured as I2S master will require their own clocking setup. Capture on pin 38 (SD0) maps to `i2s_tx` on interface `(3, 0)` with SD line 1.

---

## License & Credits

- Developed by **Jad Berro**, October 2026.
- **Scripts and documentation:** MIT License (see [LICENSE](LICENSE)).
- **Kernel patch (`kernel/*.patch`):** GPL-2.0 (derived from the Linux kernel).
- **Topology & UCM diffs:** Target Qualcomm's `alsa-conf-qcom` package; original Qualcomm licenses apply.
