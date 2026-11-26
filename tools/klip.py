#!/usr/bin/env python3
"""Cuts a looping excerpt out of a recording on its beats (from tools/takt.py), for a band JuleHygge's walkers
step to.

    python3 tools/klip.py IN.wav IN.takt BEATS OUT.wav OUT.takt      (16-bit mono WAV)

The excerpt runs from the first beat to beat number BEATS (a whole number of phrases, so the loop joins where
the music itself turns), with a few milliseconds' fade at each end. OUT.takt holds the beats' times within the
excerpt, one a line; its last line is the excerpt's length, which is where the first beat comes round again.
"""
import array, sys, wave

src, takt, count, out, out_takt = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]
w = wave.open(src)
assert w.getsampwidth() == 2 and w.getnchannels() == 1, "16-bit mono WAV"
rate = w.getframerate()
data = array.array("h", w.readframes(w.getnframes()))
beats = [float(line) for line in open(takt)]
lead = 0.02                                  # the attack of the first note begins a little before its beat
start = max(0.0, beats[0] - lead)
a, b = int(start * rate), int((beats[count] - lead) * rate)
cut = data[a:b]
fade_in, fade_out = int(0.004 * rate), int(0.03 * rate)
for i in range(fade_in): cut[i] = int(cut[i] * i / fade_in)
for i in range(fade_out): cut[-1 - i] = int(cut[-1 - i] * i / fade_out)
o = wave.open(out, "wb")
o.setnchannels(1); o.setsampwidth(2); o.setframerate(rate)
o.writeframes(cut.tobytes())
o.close()
with open(out_takt, "w") as f:
    for t in beats[:count]:
        f.write(f"{t - start:.3f}\n")
    f.write(f"{len(cut) / rate:.3f}\n")
print(f"{out}: {len(cut) / rate:.2f} s, {count} beats")
