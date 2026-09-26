"""Generate the small original audio set used by the pinball prototype."""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path


SAMPLE_RATE = 22_050
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "audio"
random.seed(7)


def blank(seconds: float) -> list[float]:
    return [0.0] * int(seconds * SAMPLE_RATE)


def envelope(t: float, duration: float, attack: float = 0.01, release: float = 0.08) -> float:
    attack_gain = min(1.0, t / max(attack, 0.0001))
    release_gain = min(1.0, (duration - t) / max(release, 0.0001))
    return max(0.0, min(attack_gain, release_gain))


def oscillator(phase: float, kind: str) -> float:
    if kind == "square":
        return 1.0 if math.sin(phase) >= 0.0 else -1.0
    if kind == "triangle":
        return 2.0 / math.pi * math.asin(math.sin(phase))
    return math.sin(phase)


def add_tone(
    data: list[float],
    start: float,
    duration: float,
    frequency: float,
    volume: float = 0.25,
    kind: str = "sine",
    end_frequency: float | None = None,
    attack: float = 0.01,
    release: float = 0.08,
) -> None:
    first = int(start * SAMPLE_RATE)
    count = min(int(duration * SAMPLE_RATE), len(data) - first)
    phase = 0.0
    target = frequency if end_frequency is None else end_frequency
    for index in range(max(0, count)):
        t = index / SAMPLE_RATE
        ratio = t / max(duration, 0.0001)
        current_frequency = frequency + (target - frequency) * ratio
        phase += math.tau * current_frequency / SAMPLE_RATE
        data[first + index] += oscillator(phase, kind) * volume * envelope(
            t, duration, attack, release
        )


def add_noise(
    data: list[float], start: float, duration: float, volume: float = 0.1
) -> None:
    first = int(start * SAMPLE_RATE)
    count = min(int(duration * SAMPLE_RATE), len(data) - first)
    previous = 0.0
    for index in range(max(0, count)):
        t = index / SAMPLE_RATE
        raw = random.uniform(-1.0, 1.0)
        previous = previous * 0.55 + raw * 0.45
        data[first + index] += previous * volume * envelope(t, duration, 0.001, duration * 0.7)


def write_wav(name: str, data: list[float]) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    peak = max(1.0, max(abs(sample) for sample in data) * 1.05)
    frames = bytearray()
    for sample in data:
        frames.extend(struct.pack("<h", int(max(-1.0, min(1.0, sample / peak)) * 32767)))
    with wave.open(str(OUTPUT_DIR / name), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(frames)


def make_charge() -> list[float]:
    data = blank(1.0)
    add_tone(data, 0.0, 1.0, 105.0, 0.22, "triangle", 145.0, 0.03, 0.03)
    add_tone(data, 0.0, 1.0, 210.0, 0.08, "sine", 290.0, 0.03, 0.03)
    return data


def make_launch() -> list[float]:
    data = blank(0.32)
    add_noise(data, 0.0, 0.22, 0.16)
    add_tone(data, 0.0, 0.30, 180.0, 0.36, "triangle", 720.0, 0.005, 0.11)
    return data


def make_collision() -> list[float]:
    data = blank(0.16)
    add_noise(data, 0.0, 0.055, 0.18)
    add_tone(data, 0.0, 0.15, 720.0, 0.32, "sine", 390.0, 0.001, 0.12)
    return data


def make_notes(notes: list[tuple[float, float, float]], seconds: float, kind: str = "triangle") -> list[float]:
    data = blank(seconds)
    for start, duration, frequency in notes:
        add_tone(data, start, duration, frequency, 0.28, kind)
        add_tone(data, start, duration, frequency * 2.0, 0.07, "sine")
    return data


def make_negative() -> list[float]:
    data = blank(0.65)
    add_tone(data, 0.0, 0.62, 300.0, 0.35, "triangle", 85.0, 0.005, 0.2)
    add_noise(data, 0.0, 0.22, 0.07)
    return data


def make_tick() -> list[float]:
    data = blank(0.10)
    add_noise(data, 0.0, 0.035, 0.18)
    add_tone(data, 0.0, 0.085, 1100.0, 0.25, "sine", 760.0, 0.001, 0.06)
    return data


def make_fanfare(victory: bool) -> list[float]:
    notes = [
        (0.00, 0.28, 392.00),
        (0.28, 0.28, 523.25),
        (0.56, 0.28, 659.25),
        (0.84, 0.65 if not victory else 1.55, 783.99),
    ]
    data = make_notes(notes, 1.55 if not victory else 2.55, "square")
    if victory:
        for frequency in (392.00, 493.88, 587.33, 783.99):
            add_tone(data, 1.18, 1.25, frequency, 0.11, "triangle", release=0.45)
    return data


def make_failure() -> list[float]:
    return make_notes(
        [(0.0, 0.42, 329.63), (0.36, 0.42, 261.63), (0.72, 0.78, 196.00)],
        1.55,
        "triangle",
    )


def make_bgm() -> list[float]:
    # Original 16-second, 120 BPM heroic/chiptune loop in D minor.
    seconds = 16.0
    data = blank(seconds)
    beat = 0.5
    chords = [
        (146.83, 174.61, 220.00),  # Dm
        (116.54, 146.83, 174.61),  # Bb
        (174.61, 220.00, 261.63),  # F
        (130.81, 164.81, 196.00),  # C
    ]
    melody = [
        293.66, 349.23, 440.00, 523.25, 440.00, 349.23, 293.66, 349.23,
        233.08, 293.66, 349.23, 440.00, 349.23, 293.66, 261.63, 293.66,
        349.23, 440.00, 523.25, 698.46, 523.25, 440.00, 392.00, 349.23,
        261.63, 329.63, 392.00, 523.25, 440.00, 392.00, 329.63, 293.66,
    ]
    for beat_index, frequency in enumerate(melody):
        start = beat_index * beat
        add_tone(data, start, beat * 0.82, frequency, 0.12, "square", attack=0.004, release=0.08)
    for bar in range(8):
        chord = chords[bar % len(chords)]
        bar_start = bar * 2.0
        add_tone(data, bar_start, 1.82, chord[0] / 2.0, 0.18, "triangle", release=0.12)
        for step in range(8):
            frequency = chord[step % 3] * 2.0
            add_tone(data, bar_start + step * 0.25, 0.20, frequency, 0.055, "triangle", release=0.04)
        for step in range(4):
            add_noise(data, bar_start + step * beat, 0.045, 0.035)
    # A tiny edge fade avoids clicks while keeping the loop pulse intact.
    fade_samples = int(0.015 * SAMPLE_RATE)
    for index in range(fade_samples):
        gain = index / fade_samples
        data[index] *= gain
        data[-1 - index] *= gain
    return data


def main() -> None:
    assets = {
        "charge_loop.wav": make_charge(),
        "launch.wav": make_launch(),
        "collision.wav": make_collision(),
        "score_100.wav": make_notes([(0.0, 0.2, 523.25), (0.16, 0.2, 659.25), (0.32, 0.42, 783.99)], 0.8, "square"),
        "score_50.wav": make_notes([(0.0, 0.2, 440.00), (0.18, 0.35, 659.25)], 0.58),
        "extra_ball.wav": make_notes([(0.0, 0.18, 659.25), (0.13, 0.18, 783.99), (0.26, 0.18, 987.77), (0.39, 0.38, 1318.51)], 0.82),
        "negative.wav": make_negative(),
        "tick.wav": make_tick(),
        "buff_confirm.wav": make_notes([(0.0, 0.22, 523.25), (0.18, 0.38, 783.99)], 0.62),
        "level_clear.wav": make_fanfare(False),
        "victory.wav": make_fanfare(True),
        "failure.wav": make_failure(),
        "bgm_adventure.wav": make_bgm(),
    }
    for name, data in assets.items():
        write_wav(name, data)
    print(f"Generated {len(assets)} original audio files in {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
