"""Extract a monophonic, equal-tempered melody from the menu MP3.

This is a development helper. The generated FPGA design only uses the compact
note table embedded in Menu_Theme_Player.v and has no audio-decoder dependency.
"""
from pathlib import Path
import math
import argparse
import miniaudio
import numpy as np


parser = argparse.ArgumentParser()
parser.add_argument("source", nargs="?", default="menu_theme.mp3")
parser.add_argument("--start", type=float, default=1.0)
parser.add_argument("--end", type=float, default=25.0)
parser.add_argument("--low-midi", type=int, default=62)
parser.add_argument("--high-midi", type=int, default=84)
parser.add_argument("--hop", type=float, default=0.125)
args = parser.parse_args()

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / args.source
SAMPLE_RATE = 12_000
HOP_SECONDS = args.hop
START_SECONDS = args.start
END_SECONDS = args.end
MIDI_NOTES = np.arange(args.low_midi, args.high_midi + 1)


decoded = miniaudio.decode_file(
    str(SOURCE),
    output_format=miniaudio.SampleFormat.FLOAT32,
    nchannels=1,
    sample_rate=SAMPLE_RATE,
)
samples = np.asarray(decoded.samples, dtype=np.float32)
hop = int(SAMPLE_RATE * HOP_SECONDS)
window_size = hop * 2
starts = range(int(START_SECONDS * SAMPLE_RATE),
               min(int(END_SECONDS * SAMPLE_RATE), len(samples) - window_size), hop)

salience = []
energy = []
nfft = 8192
freq_step = SAMPLE_RATE / nfft
for start in starts:
    frame = samples[start:start + window_size]
    energy.append(float(np.sqrt(np.mean(frame * frame))))
    spectrum = np.abs(np.fft.rfft((frame - frame.mean()) * np.hanning(window_size), nfft))
    row = []
    for midi in MIDI_NOTES:
        fundamental = 440.0 * (2.0 ** ((midi - 69) / 12.0))
        value = 0.0
        for harmonic, weight in ((1, 1.0), (2, 0.55), (3, 0.32), (4, 0.18)):
            center = int(round(fundamental * harmonic / freq_step))
            if center + 2 < len(spectrum):
                value += weight * float(np.max(spectrum[center - 2:center + 3]))
        row.append(math.log1p(value))
    salience.append(row)

salience = np.asarray(salience)
frames, pitches = salience.shape
score = np.full((frames, pitches), -1e30)
back = np.zeros((frames, pitches), dtype=np.int16)
score[0] = salience[0]
for frame in range(1, frames):
    for pitch in range(pitches):
        jumps = np.abs(np.arange(pitches) - pitch)
        transition = 0.42 * jumps + 1.8 * (jumps >= 7) + 3.0 * (jumps >= 12)
        candidates = score[frame - 1] - transition
        previous = int(np.argmax(candidates))
        score[frame, pitch] = candidates[previous] + salience[frame, pitch]
        back[frame, pitch] = previous

path = np.zeros(frames, dtype=np.int16)
path[-1] = int(np.argmax(score[-1]))
for frame in range(frames - 1, 0, -1):
    path[frame - 1] = back[frame, path[frame]]

notes = []
for index, pitch in enumerate(path):
    midi = int(MIDI_NOTES[pitch])
    note = -1 if energy[index] < 0.025 else midi
    if notes and notes[-1][0] == note:
        notes[-1][1] += 1
    else:
        notes.append([note, 1])

names = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
for midi, ticks in notes:
    name = "REST" if midi < 0 else f"{names[midi % 12]}{midi // 12 - 1}"
    frequency = 0 if midi < 0 else round(440.0 * (2.0 ** ((midi - 69) / 12.0)))
    print(f"{name:5s} {frequency:4d} Hz  {ticks:2d} ticks")
