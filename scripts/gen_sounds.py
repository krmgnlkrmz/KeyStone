#!/usr/bin/env python3
"""Synthesises the game's sound effects and the ambient bed into App/Resources/Sounds (16-bit mono WAV).

Everything is generated (no third-party audio): wood creak, stone scrape, metal ring, low collapse
rumble, soft ticks and a single chime, after the design system's sound column. Deterministic (seeded).
"""
import os, wave
import numpy as np

OUT = os.path.join(os.path.dirname(__file__), "..", "App/Resources/Sounds")
SR = 44100
rng = np.random.default_rng(20261008)


def t(dur, sr=SR):
    return np.arange(int(dur * sr)) / sr


def env(n, attack=0.005, decay_pow=2.0, sr=SR):
    a = max(1, int(attack * sr))
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a)
    e[a:] = (1 - np.linspace(0, 1, n - a)) ** decay_pow
    return e


def lowpass(x, cutoff, sr=SR):
    # one-pole low-pass, applied twice
    a = np.exp(-2 * np.pi * cutoff / sr)
    y = np.zeros_like(x)
    for _ in range(2):
        acc = 0.0
        for i in range(len(x)):
            acc = (1 - a) * x[i] + a * acc
            y[i] = acc
        x = y.copy()
    return y


def bandpass(x, lo, hi, sr=SR):
    return lowpass(x, hi, sr) - lowpass(x, lo, sr)


def noise(dur):
    return rng.uniform(-1, 1, int(dur * SR))


def norm(x, peak=0.8):
    m = np.max(np.abs(x)) or 1
    return x / m * peak


def save(name, x, sr=SR):
    os.makedirs(OUT, exist_ok=True)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())


def tick():
    d = 0.08
    x = bandpass(noise(d), 900, 2000) * env(int(d * SR), 0.001, 3) * 0.8
    x += np.sin(2 * np.pi * 320 * t(d)) * env(int(d * SR), 0.001, 4) * 0.25
    return norm(x, 0.5)


def select():
    d = 0.04
    return norm(np.sin(2 * np.pi * 900 * t(d)) * env(int(d * SR), 0.001, 3), 0.25)


def place():
    d = 0.16
    x = np.sin(2 * np.pi * 240 * t(d)) * env(int(d * SR), 0.002, 3) * 0.6
    x += bandpass(noise(d), 1800, 3200) * env(int(d * SR), 0.001, 5) * 0.4
    return norm(x, 0.5)


def nope():
    d = 0.09
    return norm(np.sin(2 * np.pi * 180 * t(d)) * env(int(d * SR), 0.002, 2), 0.3)


def creak():
    d = 0.32
    tt = t(d)
    f = 140 + 60 * np.sin(2 * np.pi * 3 * tt) + 40 * tt
    ph = np.cumsum(2 * np.pi * f / SR)
    saw = 2 * ((ph / (2 * np.pi)) % 1) - 1
    x = lowpass(saw, 900) * env(len(tt), 0.03, 1.5)
    x += bandpass(noise(d), 300, 1200) * env(len(tt), 0.01, 2) * 0.3
    return norm(x, 0.45)


def scrape():
    d = 0.3
    x = bandpass(noise(d), 500, 2600) * env(int(d * SR), 0.02, 1.5)
    x *= 0.6 + 0.4 * np.sin(2 * np.pi * 23 * t(d))
    return norm(x, 0.45)


def ring():
    d = 0.6
    tt = t(d)
    x = sum(np.sin(2 * np.pi * f * tt) * a for f, a in [(880, 1), (1320, 0.5), (2210, 0.25), (3170, 0.12)])
    x *= np.exp(-tt * 7)
    return norm(x, 0.35)


def collapse():
    d = 1.0
    tt = t(d)
    x = lowpass(noise(d), 260) * env(len(tt), 0.005, 1.4) * 1.0
    x += np.sin(2 * np.pi * (58 - 10 * tt) * tt) * np.exp(-tt * 3.5) * 0.5
    for start in (0.08, 0.21, 0.37):
        s = int(start * SR)
        k = bandpass(noise(0.12), 200, 900) * env(int(0.12 * SR), 0.001, 3) * 0.5
        x[s:s + len(k)] += k[: len(x) - s]
    return norm(x, 0.85)


def drop():
    d = 0.45
    x = lowpass(noise(d), 500) * env(int(d * SR), 0.003, 2)
    x += np.sin(2 * np.pi * 90 * t(d)) * np.exp(-t(d) * 9) * 0.4
    return norm(x, 0.7)


def chime():
    d = 0.6
    tt = t(d)
    x = np.sin(2 * np.pi * 660 * tt) * np.exp(-tt * 6) * 0.7
    late = np.zeros_like(tt)
    s = int(0.06 * SR)
    late[s:] = np.sin(2 * np.pi * 990 * tt[: len(tt) - s]) * np.exp(-tt[: len(tt) - s] * 5) * 0.5
    return norm(x + late, 0.3)


def undo():
    d = 0.2
    tt = t(d)
    f = 520 - 260 * tt / d
    ph = np.cumsum(2 * np.pi * f / SR)
    return norm(np.sin(ph) * env(len(tt), 0.005, 2), 0.25)


def ambient():
    sr = 22050
    d = 24.0
    tt = np.arange(int(d * sr)) / sr
    # Melody-free bed: two slow detuned drones and filtered air, looping cleanly (whole cycles).
    x = np.zeros_like(tt)
    for f, a in [(55.0, 0.5), (82.5, 0.3), (110.0, 0.2), (164.8, 0.08)]:
        x += a * np.sin(2 * np.pi * f * tt) * (0.7 + 0.3 * np.sin(2 * np.pi * tt / d * 2))
    air = rng.uniform(-1, 1, len(tt))
    air = lowpass(air[: len(tt)], 400, sr)
    x += air * 0.6 * (0.6 + 0.4 * np.sin(2 * np.pi * tt / d))
    fade = int(0.5 * sr)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    save("ambient", norm(x, 0.35), sr)


if __name__ == "__main__":
    for name, fn in [("tick", tick), ("select", select), ("place", place), ("nope", nope), ("creak", creak),
                     ("scrape", scrape), ("ring", ring), ("collapse", collapse), ("drop", drop), ("chime", chime),
                     ("undo", undo)]:
        save(name, fn())
    ambient()
    print("sounds written to", os.path.normpath(OUT))
