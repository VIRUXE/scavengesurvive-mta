"""Synthesises the breathing loops of the masks (resources/[scavengesurvive]/items/sounds/breath_*.wav).

One breath in and out per file, cut to loop without a seam; the client (items/client/breath.lua) plays the worn
mask's loop, louder and faster with effort. The better a mask protects, the heavier it sounds:

    breath_cloth       a bandana: a faint, muffled breath through cloth
    breath_dust        a dust mask: a soft papery breath, the shell ticking as it flexes
    breath_respirator  a half respirator: a narrow, hissing breath in and a valve that clicks open for the breath out
    breath_gasmask     a gas mask: a deep hollow rasp in through the filter, a fluttering valve on the way out
    breath_wheeze      a spent filter, played over the mask's own loop: a thin whistle on the breath in

No sample libraries: filtered noise and a few tones from fixed seeds, so a run rewrites identical files.
Run from the repo root:  python -m tools.make_breath_sounds [--out DIR]
"""

from __future__ import annotations

import argparse
import wave
from pathlib import Path

import numpy as np

SR = 22050
DEFAULT_OUT = Path("resources/[scavengesurvive]/items/sounds")
PEAK = 0.8
# one cycle: breath in, a hold, breath out, a rest (seconds)
IN, HOLD, OUT, REST = 1.25, 0.2, 1.45, 0.4
CYCLE = IN + HOLD + OUT + REST


def axis(seconds: float) -> np.ndarray:
    return np.arange(int(round(seconds * SR))) / SR


def bandpass(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    spectrum = np.fft.rfft(x)
    freq = np.fft.rfftfreq(len(x), 1 / SR)
    # soft skirts, so a band does not ring
    gain = np.clip((freq - lo * 0.7) / (lo * 0.3 + 1), 0, 1) * np.clip((hi * 1.3 - freq) / (hi * 0.3 + 1), 0, 1)
    return np.fft.irfft(spectrum * gain, len(x))


def norm(x: np.ndarray) -> np.ndarray:
    return x / (np.abs(x).max() or 1)


def swell(seconds: float, attack: float, release: float) -> np.ndarray:
    """A breath's loudness: up over `attack` of its length, held, down over `release`."""
    t = axis(seconds) / seconds
    return np.clip(t / attack, 0, 1) ** 1.5 * np.clip((1 - t) / release, 0, 1) ** 1.5


def air(rng: np.random.Generator, seconds: float, lo: float, hi: float) -> np.ndarray:
    return norm(bandpass(rng.standard_normal(len(axis(seconds))), lo, hi))


def click(rng: np.random.Generator, lo: float, hi: float, decay: float) -> np.ndarray:
    t = axis(max(0.02, decay * 8))
    return norm(bandpass(rng.standard_normal(len(t)), lo, hi)) * np.exp(-t / decay) * np.clip(t / 0.0008, 0, 1)


def cycle() -> np.ndarray:
    return np.zeros(len(axis(CYCLE)))


def place(out: np.ndarray, at: float, part: np.ndarray, gain: float) -> None:
    start = int(round(at * SR))
    end = min(len(out), start + len(part))
    out[start:end] += part[: end - start] * gain


def cloth(rng: np.random.Generator) -> np.ndarray:
    out = cycle()
    place(out, 0, air(rng, IN, 180, 800) * swell(IN, 0.45, 0.4), 0.8)
    place(out, IN + HOLD, air(rng, OUT, 140, 600) * swell(OUT, 0.2, 0.7), 1.0)
    return out


def dust(rng: np.random.Generator) -> np.ndarray:
    out = cycle()
    place(out, 0, air(rng, IN, 350, 1700) * swell(IN, 0.4, 0.4), 0.9)
    place(out, IN + HOLD, air(rng, OUT, 250, 1200) * swell(OUT, 0.2, 0.7), 1.0)
    # the paper shell flexing in at the start of the breath in and out again at the breath out
    for at in (0.06, 0.13, IN + HOLD + 0.04):
        place(out, at, click(rng, 1500, 5000, 0.004), 0.25)
    return out


def respirator(rng: np.random.Generator) -> np.ndarray:
    out = cycle()
    inward = air(rng, IN, 500, 1300) + 0.5 * air(rng, IN, 2500, 5500)
    place(out, 0, norm(inward) * swell(IN, 0.35, 0.35), 0.9)
    place(out, IN + HOLD - 0.01, click(rng, 900, 3500, 0.006), 0.6)  # the exhale valve opens
    outward = air(rng, OUT, 300, 900) + 0.35 * air(rng, OUT, 1800, 4000)
    place(out, IN + HOLD, norm(outward) * swell(OUT, 0.12, 0.75), 1.0)
    place(out, IN + HOLD + OUT - 0.05, click(rng, 700, 2500, 0.008), 0.35)  # and falls shut
    return out


def gasmask(rng: np.random.Generator) -> np.ndarray:
    out = cycle()
    # in through the canister: a hollow body with the filter's hiss on top
    inward = air(rng, IN, 250, 480) + 0.8 * air(rng, IN, 800, 1100) + 0.6 * air(rng, IN, 2200, 5000)
    place(out, 0, norm(inward) * swell(IN, 0.5, 0.3), 1.0)
    place(out, IN + HOLD - 0.01, click(rng, 500, 2000, 0.01), 0.7)
    # out past the rubber valve, which flutters
    t = axis(OUT)
    flutter = 0.65 + 0.35 * np.sin(2 * np.pi * 27 * t + 2 * np.sin(2 * np.pi * 3 * t))
    outward = air(rng, OUT, 200, 420) + 0.7 * air(rng, OUT, 650, 950) + 0.25 * air(rng, OUT, 1500, 3000)
    place(out, IN + HOLD, norm(outward) * flutter * swell(OUT, 0.1, 0.8), 1.0)
    place(out, IN + HOLD + OUT - 0.04, click(rng, 400, 1500, 0.012), 0.4)
    return out


def wheeze(rng: np.random.Generator) -> np.ndarray:
    out = cycle()
    t = axis(IN)
    freq = 980 - 260 * t / IN + 25 * np.sin(2 * np.pi * 6 * t)
    tone = np.sin(2 * np.pi * np.cumsum(freq) / SR) + 0.3 * np.sin(4 * np.pi * np.cumsum(freq) / SR)
    whistle = norm(tone + 0.5 * air(rng, IN, 700, 1400))
    place(out, 0, whistle * swell(IN, 0.6, 0.25), 0.8)
    t = axis(OUT * 0.6)
    freq = 620 - 120 * t / (OUT * 0.6)
    rattle = norm(np.sin(2 * np.pi * np.cumsum(freq) / SR) * (np.sin(2 * np.pi * 38 * t) > 0) + air(rng, OUT * 0.6, 400, 900))
    place(out, IN + HOLD + 0.1, rattle * swell(OUT * 0.6, 0.2, 0.6), 0.35)
    return out


SOUNDS = {
    "breath_cloth": (cloth, 0.45, 101),
    "breath_dust": (dust, 0.55, 102),
    "breath_respirator": (respirator, 0.7, 103),
    "breath_gasmask": (gasmask, 0.8, 104),
    "breath_wheeze": (wheeze, 0.5, 105),
}


def write(path: Path, x: np.ndarray, peak: float) -> None:
    data = (norm(x) * peak * 32767).astype("<i2")
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data.tobytes())


def main() -> None:
    parser = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    out = parser.parse_args().out
    out.mkdir(parents=True, exist_ok=True)
    for name, (make, peak, seed) in SOUNDS.items():
        write(out / f"{name}.wav", make(np.random.default_rng(seed)), peak * PEAK)
        print(f"wrote {out / name}.wav")


if __name__ == "__main__":
    main()
