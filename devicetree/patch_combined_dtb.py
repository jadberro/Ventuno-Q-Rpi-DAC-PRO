#!/usr/bin/env python3
"""Patch the Ventuno Q's combined-dtb.dtb (dtb_a partition) to route LPI I2S1 to the JHAT header.

combined-dtb.dtb is a plain concatenation of FDT blobs. The bootloader picks the one matching the
board (qcom,msm-id / qcom,board-id). This tool:
  1. splits the file into its FDTs,
  2. picks the one whose model/msm-id/board-id match the running board (/proc/device-tree),
  3. decompiles it (dtc -s), applies jhat-i2s1.dts.diff with `patch`, recompiles,
  4. splices it back in place and writes the result to --out (never touches the partition itself).

Usage:
  python3 patch_combined_dtb.py --in /mnt/dtb_a/combined-dtb.dtb --out combined-dtb.new.dtb [--index N] [--check REF.dtb]
Then copy --out onto the FAT partition yourself (see README).
"""
import argparse, os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DIFF = os.path.join(HERE, "jhat-i2s1.dts.diff")
MAGIC = b"\xd0\x0d\xfe\xed"


def split(blob):
    out, o = [], 0
    while o + 8 <= len(blob):
        if blob[o:o + 4] != MAGIC:
            raise SystemExit(f"unexpected data at offset {o}")
        size = struct.unpack(">I", blob[o + 4:o + 8])[0]
        out.append(blob[o:o + size]); o += size
    return out


def dtc(args, data=None):
    r = subprocess.run(["dtc", "-q"] + args, input=data, capture_output=True)
    if r.returncode:
        raise SystemExit(r.stderr.decode())
    return r.stdout


def prop(dts, name):
    for line in dts.splitlines()[:80]:
        s = line.strip()
        if s.startswith(name + " ="):
            return s.split("=", 1)[1].strip().rstrip(";")
    return None


def live(name):
    p = f"/proc/device-tree/{name}"
    if not os.path.exists(p):
        return None
    b = open(p, "rb").read()
    if name == "model":
        return '"' + b.rstrip(b"\0").decode() + '"'
    return "<" + " ".join(f"0x{struct.unpack('>I', b[i:i+4])[0]:02x}" for i in range(0, len(b), 4)) + ">"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--index", type=int, help="force sub-DTB index")
    ap.add_argument("--check", help="compare result against a known-good combined dtb")
    a = ap.parse_args()

    blobs = split(open(a.inp, "rb").read())
    print(f"{len(blobs)} FDTs in {a.inp}")
    want = {k: live(k) for k in ("model", "qcom,msm-id", "qcom,board-id")}
    idx = a.index
    if idx is None:
        hits = []
        for i, b in enumerate(blobs):
            d = dtc(["-I", "dtb", "-O", "dts"], b).decode(errors="replace")
            got = {k: prop(d, k) for k in want}
            if all(want[k] is None or got[k] is None or got[k].replace(" ", "") == want[k].replace(" ", "") for k in want) \
                    and got["model"] == want["model"]:
                hits.append(i)
        if len(hits) != 1:
            raise SystemExit(f"could not pick a unique FDT for this board (candidates {hits}); use --index")
        idx = hits[0]
    print(f"patching FDT #{idx}")

    with tempfile.TemporaryDirectory() as t:
        src = os.path.join(t, "orig.dts")
        open(src, "wb").write(dtc(["-I", "dtb", "-O", "dts", "-s"], blobs[idx]))
        txt = open(src).read()
        for ph in ("0x400", "0x401", "0x402"):
            if f"phandle = <{ph}>;" in txt:
                raise SystemExit(f"phandle {ph} already used in this DTB: the diff was made for a different build")
        if "lpi_i2s1-active-state" in txt:
            raise SystemExit("this DTB already contains the JHAT I2S1 changes")
        r = subprocess.run(["patch", "--no-backup-if-mismatch", src, DIFF], capture_output=True, text=True)
        print(r.stdout.strip())
        if r.returncode:
            raise SystemExit("patch failed:\n" + r.stderr)
        new = dtc(["-I", "dts", "-O", "dtb"], open(src, "rb").read())

    blobs[idx] = new
    out = b"".join(blobs)
    open(a.out, "wb").write(out)
    print(f"wrote {a.out} ({len(out)} bytes)")

    if a.check:
        ref = split(open(a.check, "rb").read())[idx]
        same = dtc(["-I", "dtb", "-O", "dts", "-s"], ref) == dtc(["-I", "dtb", "-O", "dts", "-s"], new)
        print("check vs reference:", "IDENTICAL (decompiled)" if same else "DIFFERENT")
        sys.exit(0 if same else 1)


if __name__ == "__main__":
    main()
