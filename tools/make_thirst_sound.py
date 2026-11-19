"""Synthesises the sounds the thirst cue picks from (resources/[scavengesurvive]/character/files/thirst_*.wav).

A parched mouth, four ways (client/hunger.lua plays one at random, never the same twice running):

    thirst_swallow1  the lips part with a smack, the tongue unsticks from the palate, one gulp, a breath out the nose
    thirst_swallow2  a slower, deeper swallow that catches: two tongue clicks, a hard gulp, a short second one
    thirst_smack     no swallow: the lips and tongue smacking dry, three or four sticky clicks
    thirst_throat    a hoarse throat-clear, two short rasps

No sample libraries: oscillators and filtered noise from fixed seeds, so a run rewrites identical files.
Run from the repo root:  python -m tools.make_thirst_sound [--out DIR]
"""

from __future__ import annotations

import argparse
import wave
from pathlib import Path

import numpy as np

SR = 22050
DEFAULT_OUT = Path("resources/[scavengesurvive]/character/files")
PEAK = 0.8


def axis(seconds: float) -> np.ndarray:
    return np.arange(int(round(seconds * SR))) / SR


def bandpass(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    spectrum = np.fft.rfft(x)
    freq = np.fft.rfftfreq(len(x), 1 / SR)
    spectrum[(freq < lo) | (freq > hi)] = 0
    return np.fft.irfft(spectrum, len(x))


def norm(x: np.ndarray) -> np.ndarray:
    return x / (np.abs(x).max() or 1)


def place(out: np.ndarray, at: float, part: np.ndarray, gain: float) -> None:
    start = int(round(at * SR))
    end = min(len(out), start + len(part))
    out[start:end] += part[: end - start] * gain


def click(rng: np.random.Generator, lo: float, hi: float, decay: float) -> np.ndarray:
    """A short dry transient: band-limited noise with a sharp attack and an exponential tail."""
    t = axis(max(0.02, decay * 8))
    env = np.exp(-t / decay) * np.clip(t / 0.0008, 0, 1)
    return norm(bandpass(rng.standard_normal(len(t)), lo, hi)) * env


def gulp(rng: np.random.Generator, high: float, low: float, decay: float) -> np.ndarray:
    """The throat's swallow: a thump falling from `high` to `low` Hz with a muffled noise burst on top."""
    t = axis(decay * 3.5)
    freq = low + (high - low) * np.exp(-t / (decay * 0.8))
    phase = 2 * np.pi * np.cumsum(freq) / SR
    tone = (np.sin(phase) + 0.35 * np.sin(2 * phase)) * np.exp(-t / decay) * np.clip(t / 0.004, 0, 1)
    throat = norm(bandpass(rng.standard_normal(len(t)), 250, 1100))
    throat *= np.exp(-t / (decay * 0.7)) * np.clip(t / 0.002, 0, 1)
    return norm(tone / 1.35 + 0.45 * throat)


def breath(rng: np.random.Generator, seconds: float, lo: float, hi: float) -> np.ndarray:
    """A faint dry breath: band-limited noise under a smooth swell."""
    t = axis(seconds)
    return norm(bandpass(rng.standard_normal(len(t)), lo, hi)) * np.sin(np.pi * t / seconds) ** 2


def rasp(rng: np.random.Generator, seconds: float, pitch: float) -> np.ndarray:
    """A hoarse throat-clear burst: throat noise chopped by a creaky glottal pulse train, with a weak voiced tone."""
    t = axis(seconds)
    pulses = (np.sin(2 * np.pi * 32 * t + 3 * np.sin(2 * np.pi * 7 * t)) > 0.2).astype(float)
    noise = norm(bandpass(rng.standard_normal(len(t)), 300, 2400)) * (0.35 + 0.65 * pulses)
    f = pitch * (1 - 0.25 * t / seconds)
    voice = np.sin(2 * np.pi * np.cumsum(f) / SR) * pulses
    env = np.clip(t / 0.015, 0, 1) * np.exp(-t / (seconds * 0.45))
    return norm(noise + 0.4 * voice) * env


def finish(out: np.ndarray) -> np.ndarray:
    fade = int(0.01 * SR)
    out[-fade:] *= np.linspace(1, 0, fade)
    return norm(out) * PEAK


def swallow1() -> np.ndarray:
    rng = np.random.default_rng(20261119)
    out = np.zeros(int(0.95 * SR))
    place(out, 0.02, click(rng, 1800, 6000, 0.004), 0.55)  # lips part
    place(out, 0.05, click(rng, 2500, 7000, 0.003), 0.25)  # a second, smaller smack
    place(out, 0.17, click(rng, 1200, 4500, 0.005), 0.7)  # tongue off the palate
    place(out, 0.30, click(rng, 600, 2500, 0.004), 0.5)  # throat closes
    place(out, 0.31, gulp(rng, 210, 120, 0.045), 1.0)
    place(out, 0.56, breath(rng, 0.32, 500, 2600), 0.12)  # out through the nose
    return finish(out)


def swallow2() -> np.ndarray:
    rng = np.random.default_rng(20261120)
    out = np.zeros(int(1.1 * SR))
    place(out, 0.03, click(rng, 1400, 5000, 0.005), 0.6)  # tongue
    place(out, 0.14, click(rng, 1600, 5500, 0.004), 0.45)  # tongue again, sticking
    place(out, 0.33, click(rng, 500, 2200, 0.005), 0.55)
    place(out, 0.34, gulp(rng, 180, 95, 0.06), 1.0)  # a hard, deep gulp
    place(out, 0.58, gulp(rng, 160, 110, 0.03), 0.45)  # it catches: a short second one
    place(out, 0.72, breath(rng, 0.3, 400, 2000), 0.1)
    return finish(out)


def smack() -> np.ndarray:
    rng = np.random.default_rng(20261121)
    out = np.zeros(int(0.7 * SR))
    for at, lo, hi, decay, gain in (
        (0.02, 1800, 6500, 0.004, 0.7),  # lips
        (0.12, 1300, 5000, 0.005, 0.55),  # tongue off the palate
        (0.27, 2000, 7000, 0.003, 0.45),  # lips again
        (0.36, 1500, 5500, 0.004, 0.6),  # tongue
    ):
        place(out, at, click(rng, lo, hi, decay), gain)
    place(out, 0.4, breath(rng, 0.25, 600, 3000), 0.08)
    return finish(out)


def throat() -> np.ndarray:
    rng = np.random.default_rng(20261122)
    out = np.zeros(int(0.85 * SR))
    place(out, 0.02, rasp(rng, 0.22, 150), 0.8)  # "hhk"
    place(out, 0.3, rasp(rng, 0.3, 135), 1.0)  # "hhhm"
    place(out, 0.62, click(rng, 1200, 4500, 0.005), 0.3)  # the tongue after it
    return finish(out)


VARIANTS = {
    "thirst_swallow1": swallow1,
    "thirst_swallow2": swallow2,
    "thirst_smack": smack,
    "thirst_throat": throat,
}


def write_wav(path: Path, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(samples, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main() -> None:
    parser = argparse.ArgumentParser(description="Synthesises the thirst cue's sounds.")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    for name, render in VARIANTS.items():
        path = args.out / f"{name}.wav"
        write_wav(path, render())
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
