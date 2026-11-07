"""Synthesises the ignition sounds the driver's dashboard plays (resources/[scavengesurvive]/hud/sounds/*.wav).

One file per way the key can turn, cut to the same beats as the dashboard's performance for it
(hud/shared/logic/dashboard.lua, `sample`), so the needle, the lamps and the sound agree:

    acc_on        the key turned to ACC: a relay clunk and a tick
    crank_start   it starts: starter whirr with compression chugs, speeding up as the engine catches
    crank_flat    flat battery: weak solenoid chatter, one burst every 220 ms
    crank_dead    dead starter motor: a solid solenoid clunk on the same 220 ms beat, nothing turns
    crank_grind   wrecked engine: a starter that binds, uneven, in 170 ms phases (a third of them labouring)
    crank_steady  empty tank: an even crank that never catches
    engine_stall  the engine dies: a shudder that slows and falls in pitch, ends in a clunk

No sample libraries: everything is oscillators and filtered noise from a fixed seed, so a run rewrites identical files.
Run from the repo root:  python -m tools.make_ignition_sounds [--out DIR]
"""

from __future__ import annotations

import argparse
import wave
from pathlib import Path

import numpy as np

SR = 22050
DEFAULT_OUT = Path("resources/[scavengesurvive]/hud/sounds")
PEAK = 0.8


def axis(seconds: float) -> np.ndarray:
    return np.arange(int(round(seconds * SR))) / SR


def bandpass(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    spectrum = np.fft.rfft(x)
    freq = np.fft.rfftfreq(len(x), 1 / SR)
    spectrum[(freq < lo) | (freq > hi)] = 0
    return np.fft.irfft(spectrum, len(x))


def noise(rng: np.random.Generator, n: int, lo: float = 0, hi: float = SR / 2) -> np.ndarray:
    x = rng.standard_normal(n)
    return x if (lo <= 0 and hi >= SR / 2) else bandpass(x, lo, hi)


def hit(buf: np.ndarray, at: float, rng: np.random.Generator, tones, grit: float = 0.0, grit_tau: float = 0.004,
        gain: float = 1.0) -> None:
    """Add one struck sound at `at` seconds: tones = [(hz, tau seconds, amplitude)], plus a burst of noise."""
    start = int(at * SR)
    n = min(int(0.3 * SR), len(buf) - start)
    if n <= 0:
        return
    t = np.arange(n) / SR
    seg = np.zeros(n)
    for hz, tau, amp in tones:
        seg += amp * np.sin(2 * np.pi * hz * t) * np.exp(-t / tau)
    if grit:
        seg += grit * noise(rng, n, 400, 6000) * np.exp(-t / grit_tau)
    seg[: int(0.0005 * SR)] *= np.linspace(0, 1, int(0.0005 * SR))  # no click from a hard edge
    buf[start : start + n] += gain * seg


def profile(t: np.ndarray, points) -> np.ndarray:
    """A value that moves linearly between (seconds, value) points, held at the ends."""
    xs, ys = zip(*points)
    return np.interp(t, xs, ys)


def whirr(rng: np.random.Generator, t: np.ndarray, motor_hz: np.ndarray, chug_hz: np.ndarray, depth: float,
          rumble: float = 0.5) -> np.ndarray:
    """A starter motor turning an engine over: a harmonic whine at motor_hz, chopped by a compression chug at chug_hz."""
    phase = 2 * np.pi * np.cumsum(motor_hz) / SR
    tone = sum(np.sin(k * phase) / k**1.2 for k in range(1, 7))
    tone += 0.08 * np.sin(9 * phase)  # gear whine
    chug_phase = np.cumsum(chug_hz) / SR
    chug = (0.5 + 0.5 * np.cos(2 * np.pi * chug_phase)) ** 2
    env = (1 - depth) + depth * chug
    low = noise(rng, len(t), 40, 420) * 3.0  # the engine's own rumble, in time with the chug
    return env * (tone + rumble * low * (0.4 + chug))


def fade(x: np.ndarray, head: float = 0.004, tail: float = 0.02) -> np.ndarray:
    a, b = int(head * SR), int(tail * SR)
    x = x.copy()
    x[:a] *= np.linspace(0, 1, a)
    x[-b:] *= np.linspace(1, 0, b)
    return x


def acc_on(rng):
    buf = np.zeros(len(axis(0.16)))
    hit(buf, 0.0, rng, [(210, 0.018, 1.0), (1500, 0.006, 0.5), (90, 0.03, 0.6)], grit=0.35, grit_tau=0.005)
    hit(buf, 0.075, rng, [(1900, 0.004, 0.45)], grit=0.2, grit_tau=0.003)  # the dash's bulb relay ticks after
    return buf


def crank_start(rng):
    t = axis(1.0)
    motor = profile(t, [(0, 130), (0.1, 150), (0.6, 190), (0.9, 420), (1.0, 420)])
    chug = profile(t, [(0, 6.5), (0.6, 7.5), (0.9, 15), (1.0, 15)])
    depth = profile(t, [(0, 0.65), (0.6, 0.55), (0.9, 0.3), (1.0, 0.3)])
    level = profile(t, [(0, 0.0), (0.06, 0.8), (0.6, 0.9), (0.9, 1.0), (1.0, 0.0)])
    out = whirr(rng, t, motor, chug, depth) * level * 0.35
    hit(out, 0.0, rng, [(160, 0.03, 1.0), (700, 0.012, 0.4)], grit=0.3)  # the solenoid throws the pinion in
    hit(out, 0.86, rng, [(70, 0.05, 1.2), (130, 0.03, 0.6)], grit=0.5, grit_tau=0.03)  # the first cylinders fire
    return out


def beat_buf(seconds: float) -> np.ndarray:
    return np.zeros(len(axis(seconds)))


def crank_flat(rng):
    out = beat_buf(1.3)
    for i, at in enumerate(np.arange(0, 1.3, 0.22)):
        weak = 1.0 - 0.08 * i  # the battery sags a little more on each try
        for j in range(3):  # the solenoid chatters: it cannot hold the plunger in
            hit(out, at + j * 0.016, rng, [(1700 - 90 * j, 0.004, 0.7 * weak), (380, 0.01, 0.35 * weak)],
                grit=0.25 * weak, grit_tau=0.003)
    return out


def crank_dead(rng):
    out = beat_buf(1.3)
    for at in np.arange(0, 1.3, 0.22):
        hit(out, at, rng, [(180, 0.035, 1.0), (620, 0.02, 0.5), (60, 0.05, 0.5)], grit=0.4, grit_tau=0.006)
        hit(out, at + 0.009, rng, [(2300, 0.008, 0.3)], grit=0.15, grit_tau=0.004)  # the pinion tinks on the ring gear
    return out


def crank_grind(rng):
    t = axis(2.2)
    bind = (np.floor(t / 0.170) % 3 == 0).astype(float)
    # a binding starter lugs down and growls; between binds it spins up and scrapes
    motor = np.where(bind > 0, 75, 190) + 12 * np.sin(2 * np.pi * 9 * t)
    chug = np.where(bind > 0, 3.0, 8.0)
    body = whirr(rng, t, motor, chug, 0.5, rumble=0.3)
    scrape = noise(rng, len(t), 900, 4200)
    scrape *= (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(np.where(bind > 0, 40, 95)) / SR)) ** 1.5
    scrape *= np.where(bind > 0, 1.1, 0.7)
    ring = sum(np.sin(2 * np.pi * hz * t) * (rng.random(len(t)) > 0.998) for hz in (1450, 2310, 3170))
    ring = np.convolve(ring, np.exp(-np.arange(int(0.03 * SR)) / (0.006 * SR)), mode="same")
    out = (0.3 * body + 0.5 * scrape + 0.4 * ring) * profile(t, [(0, 0.0), (0.05, 1), (2.1, 1), (2.2, 0)])
    hit(out, 0.0, rng, [(160, 0.03, 0.9)], grit=0.3)
    return out


def crank_steady(rng):
    t = axis(2.2)
    wobble = np.sin(t / 0.070)  # the dashboard's needle wobble, so the two agree
    motor = 150 + 8 * wobble
    chug = 4.6 + 0.2 * wobble
    out = whirr(rng, t, motor, chug, 0.6) * profile(t, [(0, 0.0), (0.05, 0.9), (2.1, 0.85), (2.2, 0)]) * 0.35
    hit(out, 0.0, rng, [(160, 0.03, 1.0), (700, 0.012, 0.4)], grit=0.3)
    return out


def engine_stall(rng):
    t = axis(1.5)
    motor = profile(t, [(0, 150), (0.4, 110), (1.2, 55), (1.5, 40)])
    chug = profile(t, [(0, 13), (0.3, 9), (0.9, 4), (1.3, 2.2), (1.5, 1.5)])
    depth = profile(t, [(0, 0.5), (1.3, 0.9)])
    level = profile(t, [(0, 1.0), (0.3, 0.9), (1.2, 0.35), (1.4, 0.0)])
    out = whirr(rng, t, motor, chug, depth, rumble=0.8) * level * 0.35
    hit(out, 0.0, rng, [(90, 0.04, 0.9)], grit=0.5, grit_tau=0.02)  # the misfire that starts the shudder
    hit(out, 1.32, rng, [(120, 0.04, 0.8), (400, 0.015, 0.3)], grit=0.3)  # the last cylinder settles
    return out


SOUNDS = {
    "acc_on": acc_on,
    "crank_start": crank_start,
    "crank_flat": crank_flat,
    "crank_dead": crank_dead,
    "crank_grind": crank_grind,
    "crank_steady": crank_steady,
    "engine_stall": engine_stall,
}


def write_wav(path: Path, samples: np.ndarray) -> None:
    samples = fade(samples)
    peak = float(np.max(np.abs(samples))) or 1.0
    pcm = np.int16(np.clip(samples / peak * PEAK, -1, 1) * 32767)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    out = ap.parse_args().out
    out.mkdir(parents=True, exist_ok=True)
    for i, (name, make) in enumerate(SOUNDS.items()):
        samples = make(np.random.default_rng(1000 + i))
        write_wav(out / f"{name}.wav", samples)
        print(f"{name}.wav  {len(samples) / SR:.2f} s")


if __name__ == "__main__":
    main()
