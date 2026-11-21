"""Render original looping prototype music offline; never called by Godot.

Requires NumPy only for asset preparation: python tools/synthesize_music.py
All notes, instruments and arrangements are authored here without recordings.
"""

from __future__ import annotations

import json
from pathlib import Path
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "audio" / "music"
RATE = 44100
TAU = 2.0 * np.pi


class Arrangement:
    def __init__(self, bpm: float, bars: int, seed: int):
        self.beat = 60.0 / bpm
        self.length = round(bars * 4 * self.beat * RATE)
        self.mix = np.zeros((self.length, 2), dtype=np.float64)
        self.rng = np.random.default_rng(seed)

    def add(self, start: float, signal: np.ndarray, gain: float, pan: float = 0.0):
        """Wrap release tails across the loop boundary, including stereo delays."""
        offset = round(start * self.beat * RATE) % self.length
        if signal.ndim == 1:
            signal = signal[:, None] * np.array([
                np.sqrt((1.0 - pan) * 0.5), np.sqrt((1.0 + pan) * 0.5)
            ])
        signal = signal * gain
        for begin in range(0, len(signal), self.length):
            part = signal[begin:begin + self.length]
            first = min(len(part), self.length - offset)
            self.mix[offset:offset + first] += part[:first]
            self.mix[:len(part) - first] += part[first:]

    def note(self, start: float, beats: float, midi: int, kind: str, gain: float, pan: float = 0.0):
        duration = beats * self.beat
        t = np.arange(round(duration * RATE)) / RATE
        frequency = 440.0 * 2.0 ** ((midi - 69) / 12.0)
        phase = TAU * frequency * t
        if kind == "pad":
            attack = np.minimum(t / min(1.3, duration * 0.25), 1.0)
            release = np.minimum((duration - t) / min(1.6, duration * 0.3), 1.0)
            shape = np.sin(np.pi * attack * 0.5) ** 2 * np.sin(np.pi * release * 0.5) ** 2
            left = np.sin(phase) + 0.32 * np.sin(phase * 1.0016 + 0.2) + 0.09 * np.sin(phase * 2)
            right = np.sin(phase) + 0.32 * np.sin(phase * 0.9984 - 0.2) + 0.09 * np.sin(phase * 2)
            signal = np.stack((left, right), axis=1) * shape[:, None]
        elif kind == "keys":
            signal = (np.sin(phase + 0.85 * np.sin(phase * 2) * np.exp(-t * 2.5))
                      + 0.12 * np.sin(phase * 3) * np.exp(-t * 3))
            signal *= np.minimum(t / 0.009, 1.0) * np.exp(-t * 1.7) * np.minimum((duration - t) / 0.15, 1.0)
        elif kind == "arp":
            signal = sum(np.sin(phase * harmonic) / harmonic ** 1.8 for harmonic in range(1, 7))
            signal *= np.minimum(t / 0.012, 1.0) * np.exp(-t * 8) * np.minimum((duration - t) / 0.055, 1.0)
        else:
            signal = np.sin(phase + 0.35 * np.sin(phase * 2)) + 0.12 * np.sin(phase * 3)
            signal *= np.minimum(t / 0.015, 1.0) * np.exp(-t * 3) * np.minimum((duration - t) / 0.08, 1.0)
        self.add(start, signal, gain, pan)
        if kind in ("keys", "arp"):
            for delay, strength in ((0.75, 0.24), (1.5, 0.12), (2.25, 0.055)):
                self.add(start + delay, signal, gain * strength, -pan)

    def drum(self, start: float, kind: str, gain: float):
        duration = {"kick": 0.45, "snare": 0.25, "hat": 0.09}[kind]
        t = np.arange(round(duration * RATE)) / RATE
        if kind == "kick":
            phase = TAU * (43 * t + (125 - 43) * 0.024 * (1 - np.exp(-t / 0.024)))
            signal = np.sin(phase) * np.exp(-t * 15)
        else:
            source = self.rng.standard_normal(len(t))
            # Differentiation removes low-frequency rumble from the noise voices.
            source = np.concatenate(([0.0], np.diff(source))) * 0.25
            signal = source * np.exp(-t * (22 if kind == "snare" else 65))
            if kind == "snare":
                signal += np.sin(TAU * t * 175) * np.exp(-t * 30) * 0.3
        signal *= np.minimum(t / 0.0015, 1.0) * np.minimum((duration - t) / 0.02, 1.0)
        self.add(start, signal, gain, 0.25 if kind == "hat" else 0.0)

    def atmosphere(self, gain: float):
        source = self.rng.standard_normal(self.length)
        frequencies = np.fft.rfftfreq(self.length, 1 / RATE)
        spectrum = np.fft.rfft(source)
        spectrum *= (frequencies / (frequencies + 500)) ** 2 / (1 + (frequencies / 2300) ** 4)
        source = np.fft.irfft(spectrum, n=self.length)
        source /= max(float(np.max(np.abs(source))), 1e-9)
        phase = TAU * np.arange(self.length) / self.length
        source *= 0.65 + 0.35 * np.sin(phase * 3)
        self.mix[:, 0] += source * gain
        self.mix[:, 1] += np.roll(source, round(0.037 * RATE)) * gain

    def write(self, name: str) -> dict:
        # Wrapped room reflections keep the ambient tails present at the seam.
        dry = self.mix.copy()
        for delay, gain in ((0.173, 0.12), (0.283, 0.09), (0.419, 0.055)):
            self.mix += np.roll(dry[:, ::-1], round(delay * RATE), axis=0) * gain
        self.mix -= np.mean(self.mix, axis=0)
        self.mix *= 0.68 / max(float(np.max(np.abs(self.mix))), 1e-9)
        width = 512
        correction = self.mix[-1] - self.mix[0]
        shape = (0.5 - 0.5 * np.cos(np.linspace(0, np.pi, width)))[:, None]
        self.mix[-width:] -= shape * correction
        pcm = np.rint(np.clip(self.mix, -0.8, 0.8) * 32767).astype("<i2")
        path = OUTPUT / (name + ".wav")
        with wave.open(str(path), "wb") as output:
            output.setnchannels(2)
            output.setsampwidth(2)
            output.setframerate(RATE)
            output.writeframes(pcm.tobytes())
        # Preserve PCM import settings when regenerating the existing assets.
        metadata = path.with_suffix(".wav.import")
        if metadata.exists():
            text = metadata.read_text(encoding="utf-8")
            for mode in (1, 2):
                text = text.replace(f"compress/mode={mode}", "compress/mode=0")
            metadata.write_text(text, encoding="utf-8")
        return {"file": name, "seconds": round(self.length / RATE, 3),
                "peak": round(float(np.max(np.abs(pcm.astype(float)))) / 32767, 4),
                "rms": round(float(np.sqrt(np.mean(self.mix ** 2))), 4),
                "seam_equal": bool(np.array_equal(pcm[0], pcm[-1]))}


def hub() -> Arrangement:
    track = Arrangement(72, 8, 2101)
    chords = [[45, 52, 59, 60, 64], [41, 48, 55, 57, 64],
              [48, 55, 59, 62, 64], [43, 50, 57, 59, 62]]
    melody = [76, 71, 72, 67, 69, 72, 74, 71, 76, 79, 76, 72, 74, 71, 69, 67]
    for bar in range(8):
        chord = chords[bar % 4]
        for note in chord:
            track.note(bar * 4, 5.6, note, "pad", 0.035)
        for step in range(2):
            track.note(bar * 4 + step * 2 + 0.25, 3, melody[bar * 2 + step], "keys", 0.10, (-1) ** step * 0.28)
        track.note(bar * 4, 2, chord[0] - 12, "bass", 0.045)
    track.atmosphere(0.006)
    return track


def space() -> Arrangement:
    track = Arrangement(60, 8, 2102)
    chords = [[38, 50, 57, 60, 64], [34, 53, 57, 60, 65],
              [41, 53, 60, 64, 67], [36, 55, 60, 62, 67]]
    for block, chord in enumerate(chords):
        for note in chord:
            track.note(block * 8, 10, note, "pad", 0.040 if note >= 50 else 0.03)
        for step, note in enumerate([chord[2] + 12, chord[3] + 12, chord[4] + 12]):
            track.note(block * 8 + step * 2.5 + 0.5, 4, note, "keys", 0.04, (step - 1) * 0.45)
    track.atmosphere(0.012)
    return track


def danger() -> Arrangement:
    track = Arrangement(112, 8, 2103)
    chords = [[38, 50, 57, 60, 64], [34, 50, 53, 57, 60],
              [41, 53, 56, 60, 65], [36, 48, 55, 58, 62]]
    for bar in range(8):
        chord = chords[bar % 4]
        for note in chord[1:]:
            track.note(bar * 4, 5, note, "pad", 0.025)
        for step in range(8):
            track.note(bar * 4 + step * 0.5, 0.65, chord[1 + [0, 1, 2, 1, 3, 2, 1, 2][step]], "arp", 0.075, (-1) ** step * 0.3)
            if step % 2 == 0 or step == 5:
                track.note(bar * 4 + step * 0.5, 0.65, chord[0], "bass", 0.13)
            track.drum(bar * 4 + step * 0.5 + 0.25, "hat", 0.05 if step % 2 else 0.035)
        for beat in (0, 2, 2.75):
            track.drum(bar * 4 + beat, "kick", 0.27)
        for beat in (1, 3):
            track.drum(bar * 4 + beat, "snare", 0.14)
        if bar in (3, 7):
            for step in range(3):
                track.drum(bar * 4 + 3.25 + step * 0.25, "snare", 0.055)
    track.atmosphere(0.008)
    return track


def preview():
    destination = ROOT / ".godot" / "music-preview.wav"
    with wave.open(str(destination), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        for name, start in (("hub", 7), ("space", 13), ("danger", 4)):
            with wave.open(str(OUTPUT / (name + ".wav")), "rb") as source:
                source.setpos(start * RATE)
                data = np.frombuffer(source.readframes(6 * RATE), dtype="<i2").reshape(-1, 2).astype(float)
            fade = round(0.15 * RATE)
            shape = np.linspace(0, 1, fade)[:, None]
            data[:fade] *= shape
            data[-fade:] *= shape[::-1]
            output.writeframes(np.rint(data * 0.25).astype("<i2").tobytes())
            output.writeframes(bytes(round(0.25 * RATE) * 4))


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, compose in (("hub", hub), ("space", space), ("danger", danger)):
        rows.append(compose().write(name))
        print(rows[-1], flush=True)
    report = ROOT / ".godot" / "music-metrics.json"
    report.parent.mkdir(exist_ok=True)
    report.write_text(json.dumps(rows, indent=2), encoding="utf-8")
    preview()
    print(f"Rendered 3 original stereo loops; {sum(row['seconds'] for row in rows):.2f} seconds")


if __name__ == "__main__":
    main()
