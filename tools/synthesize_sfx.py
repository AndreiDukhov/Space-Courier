"""Bake the original prototype sound effects offline with Python's standard library.

Run from the repository root: python tools/synthesize_sfx.py
Godot only imports the resulting WAV files; this script is never run by the game.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
import random
import struct
import wave

RATE = 44100
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "audio" / "sfx"
TAU = math.tau


def noise(count: int, seed: int, cutoff: float = 1800.0, loop: bool = False) -> list[float]:
    rng = random.Random(seed)
    source = [rng.uniform(-1.0, 1.0) for _ in range(count)]
    alpha = 1.0 - math.exp(-TAU * cutoff / RATE)
    state = 0.0
    result = []
    for _ in range(2 if loop else 1):
        result = []
        for value in source:
            state += alpha * (value - state)
            result.append(state)
    return result


def envelope(t: float, duration: float, decay: float = 6.0, attack: float = 0.003) -> float:
    return min(1.0, t / attack) * math.exp(-decay * t / duration) * min(1.0, max(0.0, duration - t) / 0.025)


def chirp(t: float, start: float, end: float, duration: float) -> float:
    slope = math.log(end / start) / duration
    phase = TAU * start * math.expm1(slope * t) / slope if abs(slope) > 1e-9 else TAU * start * t
    return math.sin(phase)


def weapon(kind: str, variant: int) -> list[float]:
    if kind == "autocannon":
        return cannon(variant)
    duration = {"laser": 0.34, "autocannon": 0.37, "plasma": 0.60}[kind]
    count = round(duration * RATE)
    hiss = noise(count, 1000 + variant, 3100.0 if kind != "plasma" else 950.0)
    result = []
    for index in range(count):
        t = index / RATE
        if kind == "laser":
            body = chirp(t, 1850 + variant * 110, 260 + variant * 35, duration)
            value = 0.65 * body + 0.16 * chirp(t, 3100, 650, duration) + hiss[index] * math.exp(-t * 40) * 0.35
            value *= envelope(t, duration, 5.5)
        else:
            body = chirp(t, 600 + variant * 75, 120, duration)
            modulation = math.sin(TAU * t * 36) * 0.17
            value = (body * (0.7 + modulation) + hiss[index] * 0.8 + chirp(t, 1100, 280, duration) * 0.18) * envelope(t, duration, 4.5, 0.012)
        result.append(value)
    return result


def cannon(variant: int) -> list[float]:
    duration = 1.05 + variant * 0.035
    count = round(duration * RATE)
    pressure = noise(count, 1100 + variant, 180)
    crack = noise(count, 1200 + variant, 6500)
    body = noise(count, 1300 + variant, 720)
    result = []
    for index in range(count):
        t = index / RATE
        attack = min(1.0, t / 0.0015)
        blast = crack[index] * math.exp(-t * 65) * 1.8
        boom = pressure[index] * math.exp(-t * 6.5) * 3.2
        punch = math.sin(TAU * (44 * t + 48 * 0.018 * (1 - math.exp(-t / 0.018)))) * math.exp(-t * 21)
        recoil = math.sin(TAU * t * (147 + variant * 13)) * math.exp(-t * 29) * 0.12
        tail = body[index] * math.exp(-t * 7.5) * 0.55
        result.append((blast + boom + punch * 0.65 + recoil + tail) * attack * min(1.0, (duration - t) / 0.06))
    return result


def impact(variant: int) -> list[float]:
    duration = 0.32
    source = noise(round(duration * RATE), 2000 + variant, 4200)
    result = []
    for index, value in enumerate(source):
        t = index / RATE
        clang = sum(math.sin(TAU * t * frequency) * math.exp(-t * decay) for frequency, decay in [(610 + variant * 90, 28), (1283 + variant * 115, 38), (2140, 65)])
        result.append((0.22 * clang + value * math.exp(-t * 55)) * envelope(t, duration, 3.0))
    return result


def explosion(variant: int) -> list[float]:
    duration = 1.12 + variant * 0.12
    count = round(duration * RATE)
    bass = noise(count, 3000 + variant, 130)
    crackle = noise(count, 3100 + variant, 2700)
    result = []
    for index in range(count):
        t = index / RATE
        sub = chirp(t, 105 + variant * 9, 29, duration)
        tail = bass[index] * 2.7 * math.exp(-t * 3.7)
        debris = crackle[index] * (0.4 + 0.6 * math.sin(TAU * t * 17) ** 8) * math.exp(-t * 6)
        result.append((sub * math.exp(-t * 8) * 0.7 + tail + debris) * envelope(t, duration, 1.8, 0.006))
    return result


def shield(variant: int, recharge: bool = False) -> list[float]:
    duration = 1.05 if recharge else 0.43
    source = noise(round(duration * RATE), 4000 + variant, 3200)
    result = []
    for index, value in enumerate(source):
        t = index / RATE
        if recharge:
            rise = chirp(t, 230, 1150, duration)
            value = (rise * 0.5 + math.sin(TAU * t * 690) * 0.12 + value * 0.25) * math.sin(math.pi * t / duration) ** 1.2
        else:
            tone = chirp(t, 1450 + variant * 180, 690, duration)
            value = (tone * 0.6 + math.sin(TAU * t * 2180) * 0.2 + value * 0.35) * envelope(t, duration, 5.5)
        result.append(value)
    return result


def engine(kind: str) -> list[float]:
    duration = 2.0
    count = round(duration * RATE)
    seed = {"idle": 5100, "cruise": 5200, "boost": 5300}[kind]
    source = noise(count, seed, 70, True)
    fundamental = {"idle": 40.0, "cruise": 52.0, "boost": 64.0}[kind]
    result = []
    for index, value in enumerate(source):
        t = index / RATE
        hum = math.sin(TAU * t * fundamental) * 0.52 + math.sin(TAU * t * fundamental * 2) * 0.20 + math.sin(TAU * t * fundamental * 3) * 0.045
        purr = 0.82 + 0.18 * math.sin(TAU * t * (24 if kind == "boost" else 22))
        breath = 0.96 + 0.04 * math.sin(TAU * t * 1.5)
        result.append((hum + value * 0.055) * purr * breath)
    return result


def transit(kind: str) -> list[float]:
    duration = {"depart": 1.3, "arrive": 0.95, "takeoff": 0.9, "landing": 0.85}[kind]
    source = noise(round(duration * RATE), 6000 + len(kind), 1800)
    rising = kind in ("depart", "takeoff")
    result = []
    for index, value in enumerate(source):
        t = index / RATE
        progress = t / duration
        tone = chirp(t, 80 if rising else 820, 1300 if rising else 70, duration)
        shape = math.sin(math.pi * progress) ** 1.5
        value = (tone * 0.38 + value * (0.5 + progress)) * shape
        if kind == "arrive":
            value += math.sin(TAU * t * 62) * math.exp(-t * 9) * min(1, t / 0.008) * 0.5
        result.append(value)
    return result


def ui(kind: str, variant: int = 0) -> list[float]:
    duration = 0.085 if kind == "click" else 0.22
    source = noise(round(duration * RATE), 7000 + variant, 2100)
    result = []
    for index, value in enumerate(source):
        t = index / RATE
        if kind == "click":
            value = (math.sin(TAU * t * (650 + variant * 65)) * 0.45 + value * 0.4) * envelope(t, duration, 7.0, 0.0015)
        else:
            split = duration * 0.45
            local = t if t < split else t - split
            frequency = 540 if t < split else 810 if kind == "confirm" else 360
            value = math.sin(TAU * local * frequency) * envelope(local, duration - split, 4.0, 0.003)
        result.append(value)
    return result


def door(variant: int) -> list[float]:
    duration = 0.72
    source = noise(round(duration * RATE), 8000 + variant, 1300)
    result = []
    for index, value in enumerate(source):
        t = index / RATE
        motor = chirp(t, 180 + variant * 30, 340, duration)
        shape = math.sin(math.pi * t / duration) ** 2
        result.append((motor * 0.18 + value * 1.1) * shape)
    return result


def knock(variant: int) -> list[float]:
    duration = 0.70
    source = noise(round(duration * RATE), 9000 + variant, 1600)
    result = []
    for index, value in enumerate(source):
        t = index / RATE
        sample = 0.0
        for offset, strength in [(0.02, 1.0), (0.21, 0.85), (0.40, 0.9)]:
            local = t - offset
            if 0.0 <= local < 0.21:
                tone = math.sin(TAU * local * (155 + variant * 24)) + math.sin(TAU * local * 370) * 0.2
                sample += (tone * 0.7 + value * 0.5) * envelope(local, 0.21, 9.0, 0.0015) * strength
        result.append(sample)
    return result


def write(name: str, samples: list[float], peak: float = 0.76, loop: bool = False) -> dict:
    mean = sum(samples) / len(samples)
    samples = [value - mean for value in samples]
    maximum = max(abs(value) for value in samples)
    samples = [value * peak / max(maximum, 1e-9) for value in samples]
    if loop:
        seam = samples[-1] - samples[0]
        width = min(1024, len(samples))
        for index in range(width):
            samples[-width + index] -= seam * (0.5 - 0.5 * math.cos(math.pi * index / (width - 1)))
        correction = min(1.0, peak / max(abs(value) for value in samples))
        samples = [value * correction for value in samples]
    else:
        fade = round(0.002 * RATE)
        for index in range(fade):
            samples[index] *= index / fade
            samples[-index - 1] *= index / fade
    path = OUTPUT / (name + ".wav")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(struct.pack("<" + "h" * len(samples), *(round(value * 32767) for value in samples)))
    return {"file": name, "seconds": round(len(samples) / RATE, 3), "peak": round(max(abs(value) for value in samples), 4), "rms": round(math.sqrt(sum(value * value for value in samples) / len(samples)), 4), "seam_delta": round(abs(samples[0] - samples[-1]), 5) if loop else None}


def preview() -> None:
    sequence = [("engine_cruise", 0.8), ("engine_boost", 0.8), ("laser_1", None), ("autocannon_1", None), ("plasma_1", None), ("shield_hit_1", None), ("explosion_1", None), ("jump_arrive", None), ("knock_1", None), ("door_open_1", None)]
    destination = ROOT / ".godot" / "sfx-preview.wav"
    with wave.open(str(destination), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        for name, length in sequence:
            with wave.open(str(OUTPUT / (name + ".wav")), "rb") as source:
                data = source.readframes(round(length * RATE) if length else source.getnframes())
                values = list(struct.unpack("<" + "h" * (len(data) // 2), data))
                if length:
                    for index in range(round(0.025 * RATE)):
                        values[index] = round(values[index] * index / (0.025 * RATE))
                        values[-index - 1] = round(values[-index - 1] * index / (0.025 * RATE))
                data = struct.pack("<" + "h" * len(values), *(round(value * 0.5) for value in values))
                output.writeframes(data)
            output.writeframes(bytes(round(0.16 * RATE) * 2))


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    metrics = []
    for kind in ("laser", "autocannon", "plasma"):
        for variant in range(3):
            metrics.append(write(f"{kind}_{variant + 1}", weapon(kind, variant)))
    for variant in range(3):
        metrics.append(write(f"impact_{variant + 1}", impact(variant)))
        metrics.append(write(f"explosion_{variant + 1}", explosion(variant), 0.82))
    for variant in range(2):
        metrics.append(write(f"shield_hit_{variant + 1}", shield(variant)))
        metrics.append(write(f"door_open_{variant + 1}", door(variant), 0.6))
        metrics.append(write(f"knock_{variant + 1}", knock(variant), 0.65))
    metrics.append(write("shield_recharge", shield(0, True), 0.65))
    for kind in ("idle", "cruise", "boost"):
        metrics.append(write("engine_" + kind, engine(kind), 0.24, True))
    for kind in ("depart", "arrive", "takeoff", "landing"):
        metrics.append(write("jump_" + kind if kind in ("depart", "arrive") else kind, transit(kind), 0.7))
    for variant in range(3):
        metrics.append(write(f"ui_click_{variant + 1}", ui("click", variant), 0.5))
    for kind in ("confirm", "cancel"):
        metrics.append(write("ui_" + kind, ui(kind), 0.5))
    for metadata in OUTPUT.glob("*.wav.import"):
        text = metadata.read_text(encoding="utf-8")
        for compressed in ("compress/mode=1", "compress/mode=2"):
            text = text.replace(compressed, "compress/mode=0")
        metadata.write_text(text, encoding="utf-8")
    report = ROOT / ".godot" / "sfx-metrics.json"
    report.parent.mkdir(exist_ok=True)
    report.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print(f"Baked {len(metrics)} WAV files; {sum(row['seconds'] for row in metrics):.2f} seconds; {sum(path.stat().st_size for path in OUTPUT.glob('*.wav')) / 1048576:.2f} MiB")
    for row in metrics:
        if row["seam_delta"] is not None:
            print(row["file"], "loop seam:", row["seam_delta"])
    preview()


if __name__ == "__main__":
    main()
