#!/usr/bin/env python3
"""Finds every beat of a recording, so JuleHygge's carnival walkers can step to a real band (which never keeps
one tempo exactly: a fixed beat drifts half a step off within half a minute).

    python3 tools/takt.py FILE.wav [BPM]          (16-bit mono WAV; BPM is the rough tempo, from tools/tempo.py)

Prints the beat times in seconds, one a line, and to stderr how sure it is. The method is Ellis' dynamic
programming: the beats are the chain of moments that both land on rises in loudness and keep an even spacing.
The rises are measured in the bass alone (below about 150 Hz): in oompah music the tuba and the big drum play
on the beat and the chords after it, so the whole band's rises would as readily lock onto the after-beats.
No libraries needed.
"""
import array, math, sys, wave

path = sys.argv[1]
bpm = float(sys.argv[2]) if len(sys.argv) > 2 else 120.0
w = wave.open(path)
assert w.getsampwidth() == 2 and w.getnchannels() == 1, "16-bit mono WAV"
rate = w.getframerate()
data = array.array("h", w.readframes(w.getnframes()))

FPS = 200                                   # frames of the loudness curve a second
hop = rate // FPS

def rises(samples):
    env = []
    for i in range(0, len(samples) - hop, hop):
        e = 0.0
        for v in samples[i:i + hop:2]:
            e += v * v
        env.append(math.log1p(e))
    on = [max(0.0, b - a) for a, b in zip(env, env[1:])]
    # smooth a little (15 ms), so a rise spread over two frames counts as one
    return [(a + 2 * b + c) / 4 for a, b, c in zip([0] + on, on, on[1:] + [0])]

# the bass: two one-pole low-pass filters at 150 Hz
k = 1 - math.exp(-2 * math.pi * 150 / rate)
low = array.array("f", bytes(4 * len(data)))
a = b = 0.0
for i, v in enumerate(data):
    a += (v - a) * k
    b += (a - b) * k
    low[i] = b

bass, full = rises(low), rises(data)
n = len(bass)
mean = sum(bass) / n
sd = math.sqrt(sum((v - mean) ** 2 for v in bass) / n) or 1
x = [(v - mean) / sd for v in bass]

period = 60 / bpm * FPS
TIGHT = 400.0                               # how much an uneven step costs, against a rise in loudness
score = [0.0] * n
back = [-1] * n
lo, hi = int(period / 2), int(period * 2)
pen = [0.0] * (hi + 1)
for d in range(lo, hi + 1):
    pen[d] = -TIGHT * math.log(d / period) ** 2
for t in range(n):
    best, arg = 0.0, -1
    for d in range(lo, min(hi, t) + 1):
        s = score[t - d] + pen[d]
        if s > best: best, arg = s, t - d
    score[t] = x[t] + best
    back[t] = arg

t = max(range(n - hi, n), key=lambda i: score[i])
beats = []
while t >= 0:
    beats.append(t)
    t = back[t]
beats.reverse()
# drop the chain's run-in before the music starts (beats placed in silence)
loud = sorted(full)[int(n * 0.5)]
while len(beats) > 2 and max(full[max(0, beats[0] - 4):beats[0] + 5]) <= loud:
    beats.pop(0)

times = [(b + 1) / FPS for b in beats]        # (+1: a rise is between two frames)
for s in times:
    print(f"{s:.3f}")

gaps = [b - a for a, b in zip(times, times[1:])]
gaps_sorted = sorted(gaps)
med = gaps_sorted[len(gaps) // 2]
def at(curve, frames):
    return sum(max(curve[max(0, f - 3):f + 4]) for f in frames) / len(frames)
half = [(a + b) // 2 for a, b in zip(beats, beats[1:])]
print(f"{len(times)} beats, {times[0]:.2f}-{times[-1]:.2f} s; median step {med:.3f} s = {60 / med:.1f} a minute; "
      f"steps from {gaps_sorted[0]:.3f} to {gaps_sorted[-1]:.3f} s", file=sys.stderr)
print(f"bass rise on the beat {at(bass, beats):.2f}, between beats {at(bass, half):.2f}; "
      f"whole band on the beat {at(full, beats):.2f}, between {at(full, half):.2f}", file=sys.stderr)
for start in range(0, len(times) - 1, 32):
    part = gaps[start:start + 32]
    print(f"   beats {start}-{start + len(part)}: {60 * len(part) / sum(part):.1f} a minute", file=sys.stderr)
