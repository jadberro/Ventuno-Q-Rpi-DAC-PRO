#!/usr/bin/env python3
"""Drive LPI gpio6 (BCK) / gpio7 (LRCK) / gpio9 (DATA) as GPIOs via /dev/mem and see if the PCM5242 notices.
Restores the original cfg registers afterwards."""
import mmap, os, struct, subprocess, time, threading
BASE, SIZE = 0x3440000, 0x20000
BCK, LRCK, DAT = 6, 7, 9
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=BASE)
rd = lambda off: struct.unpack_from("<I", m, off)[0]
def wr(off, v): struct.pack_into("<I", m, off, v)
def dac():
    out = []
    for r in list(range(0x58, 0x60)) + [0x76]:
        out.append(subprocess.run(["i2cget", "-f", "-y", "0", "0x4c", hex(r)], capture_output=True, text=True).stdout.strip())
    return " ".join(out)
saved = {p: rd(0x1000 * p) for p in (BCK, LRCK, DAT)}
print("saved cfg", {p: hex(v) for p, v in saved.items()})
print("dac idle    :", dac())
try:
    for p in (BCK, LRCK, DAT):
        c = saved[p]
        c = (c & ~(0xF << 2)) | (1 << 9)       # func 0 (gpio), output enable
        wr(0x1000 * p, c)
    stop = False; samples = []
    def sampler():
        time.sleep(0.8)
        samples.append(dac())
    t = threading.Thread(target=sampler); t.start()
    vb, vl, vd = 0x1000 * BCK + 4, 0x1000 * LRCK + 4, 0x1000 * DAT + 4
    t0 = time.time(); n = 0; lr = 0
    while time.time() - t0 < 2.0:
        for i in range(32):
            wr(vb, 2); wr(vd, 2 if (i & 4) else 0)
            wr(vb, 0)
        lr ^= 2; wr(vl, lr); n += 1
    t.join()
    print(f"bitbang frames={n} ({n/2.0:.0f} Hz LRCK)")
    print("dac during  :", samples[0] if samples else "?")
finally:
    for p, v in saved.items():
        wr(0x1000 * p, v)
    print("restored cfg", {p: hex(rd(0x1000 * p)) for p in saved})
time.sleep(0.5)
print("dac after   :", dac())
