#!/usr/bin/env python3
"""Measures the tempo of a recording, to match it to the beat JuleHygge's carnival walkers step to.

    python3 tools/tempo.py FILE.wav [FILE.wav ...]      (16-bit mono WAV; make one with afconvert -d LEI16@22050 -c 1)

For each file: the tempo of the whole, and of every 20 seconds of it (a band does not keep one tempo all the way).
The onsets are the rises in loudness, 100 times a second; the tempo is the beat spacing at which they repeat most
strongly, between 80 and 170 beats a minute. No libraries needed.
"""
import array, math, sys, wave

def onsets(path):
    w = wave.open(path)
    assert w.getsampwidth() == 2 and w.getnchannels() == 1, "16-bit mono WAV"
    rate = w.getframerate()
    data = array.array("h", w.readframes(w.getnframes()))
    hop = rate // 100
    env = []
    for i in range(0, len(data) - hop, hop):
        e = 0
        for v in data[i:i + hop:4]:
            e += v * v
        env.append(math.log1p(e))
    return [max(0.0, b - a) for a, b in zip(env, env[1:])]

def tempo(on):
    """(beats a minute, how much stronger the best spacing is than the average one)"""
    n = len(on)
    mean = sum(on) / n
    x = [v - mean for v in on]
    best, scores = None, []
    for bpm10 in range(800, 1701, 5):
        lag = 6000 / (bpm10 / 10)          # in hundredths of a second
        s = 0.0
        for k in (1, 2, 4):                 # the beat, two beats and a bar
            d = lag * k
            lo = int(d); frac = d - lo
            if lo + 1 >= n: continue
            for i in range(0, n - lo - 1, 2):
                s += x[i] * (x[i + lo] * (1 - frac) + x[i + lo + 1] * frac)
        scores.append(s)
        if best is None or s > best[1]: best = (bpm10 / 10, s)
    avg = sum(abs(s) for s in scores) / len(scores)
    return best[0], best[1] / avg if avg else 0

for path in sys.argv[1:]:
    on = onsets(path)
    bpm, strength = tempo(on)
    print(f"{path}: {len(on) / 100:.0f} s, {bpm:.1f} beats a minute (strength {strength:.1f})")
    parts = []
    for start in range(0, len(on) - 2000, 2000):
        b, s = tempo(on[start:start + 2000])
        parts.append(f"{start // 100}s {b:.0f}")
    print("   every 20 s: " + ", ".join(parts))
