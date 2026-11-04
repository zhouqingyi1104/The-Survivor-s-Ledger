"""Rebuild the project's original, seamless night-watch music without samples.

Usage (existing NumPy, SciPy and FFmpeg only; no downloads):
    python -I tools/pipeline/synth_night_music.py build/night-music-qa \
        --asset-path assets/audio/music/night_watch.ogg --verify-reproducible

The output directory receives the source WAV, Vorbis asset, decoded measurements
and a four-second preview straddling the loop. Only the OGG belongs in assets.
All notes, envelopes and circular room reflections are synthesized here. The
fixed arrangement and seed make WAV/OGG bytes repeatable with the same toolchain.
Machine measurements do not establish whether a person enjoys the composition.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import tempfile

import numpy as np
from scipy.io import wavfile


SAMPLE_RATE = 44100
SECONDS = 56
SAMPLES = SAMPLE_RATE * SECONDS
SEED = 20261104
PEAK_DBFS = -7.0
NAME = "night_watch"
BAR = 3.5


def hz(midi: int) -> float:
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def smooth(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def place_loop(mix: np.ndarray, sound: np.ndarray, start: float, pan: float) -> None:
    """Wrap note tails into the head rather than fading the complete track out."""
    first = int(round(start * SAMPLE_RATE)) % SAMPLES
    left = math.sqrt((1.0 - pan) * 0.5)
    right = math.sqrt((1.0 + pan) * 0.5)
    stereo = sound[:, None] * np.array([left, right])[None, :]
    before = min(len(sound), SAMPLES - first)
    mix[first:first + before] += stereo[:before]
    if before < len(sound):
        mix[:len(sound) - before] += stereo[before:]


def rounded_note(midi: int, seconds: float, attack: float, decay: float,
                 amplitude: float, phase: float) -> np.ndarray:
    """Soft plucked string: no metal/noise strike and very little upper spectrum."""
    t = np.arange(int(round(seconds * SAMPLE_RATE)), dtype=np.float64) / SAMPLE_RATE
    env = smooth(t / attack) * np.exp(-t / decay)
    env *= smooth((seconds - t) / min(0.8, seconds * 0.3))
    fundamental = 2.0 * np.pi * hz(midi) * t
    # Harmonic decay is faster than the fundamental, leaving room for warning SFX.
    sound = np.sin(fundamental + phase)
    sound += 0.14 * np.sin(2.0 * fundamental + phase * 0.7) * np.exp(-t / 0.45)
    sound += 0.025 * np.sin(3.0 * fundamental) * np.exp(-t / 0.2)
    return amplitude * env * sound


def compose() -> np.ndarray:
    rng = np.random.default_rng(SEED)
    t = np.arange(SAMPLES, dtype=np.float64) / SAMPLE_RATE
    loop_phase = 2.0 * np.pi * t / SECONDS
    mix = np.zeros((SAMPLES, 2), dtype=np.float64)

    # A quiet D/A bed. Integer cycles over the complete piece make the continuous
    # tones and their slow swells periodic, including derivatives at the join.
    for midi, amplitude, pan, phase in [(38, 0.095, -0.15, 0.4),
                                       (45, 0.040, 0.2, 2.1),
                                       (50, 0.017, 0.0, 1.2)]:
        cycles = round(hz(midi) * SECONDS)
        swell = 0.76 + 0.12 * np.sin(loop_phase + phase)
        swell += 0.06 * np.sin(2.0 * loop_phase - phase)
        tone = np.sin(cycles * loop_phase + phase)
        tone += 0.08 * np.sin(cycles * loop_phase * 2.0 + phase)
        gains = np.sqrt(np.array([(1.0 - pan) * 0.5, (1.0 + pan) * 0.5]))
        mix += amplitude * (swell * tone)[:, None] * gains[None, :]

    # Sixteen unhurried bars (68 4/7 BPM). The bass changes only every two bars;
    # rounded half-time pulses have a long attack, without a drum transient.
    bass = [38, 38, 41, 41, 36, 36, 43, 45]
    for bar in range(16):
        if bar % 2 == 0:
            sound = rounded_note(bass[bar // 2], 7.8, 0.18, 2.7, 0.12, 0.0)
            place_loop(mix, sound, bar * BAR + 0.08, -0.05)
        for beat in (0.0, 1.75):
            sound = rounded_note(50, 2.5, 0.23, 0.7, 0.016, 0.0)
            place_loop(mix, sound, bar * BAR + beat + 0.3, 0.0)

    # D-minor pentatonic: D/F/G/A/C. Deliberate spaces allow the existing wind,
    # bells, night watch and door impacts to remain audible during play.
    phrases = [
        [(0.45, 62), (2.25, 69), (5.3, 67)],
        [(0.8, 65), (4.4, 62)],
        [(1.15, 60), (3.75, 65), (5.65, 67)],
        [(0.9, 69), (4.65, 67)],
        [(0.55, 62), (2.6, 65), (5.45, 69)],
        [(1.2, 72), (4.6, 69)],
        [(0.75, 67), (3.5, 65), (5.65, 62)],
        [(1.05, 60), (4.1, 62)],
    ]
    for phrase, notes in enumerate(phrases):
        for when, midi in notes:
            sound = rounded_note(midi, 5.4, 0.024, 1.15,
                                 float(rng.uniform(0.042, 0.058)),
                                 float(rng.uniform(0.0, 2.0 * np.pi)))
            place_loop(mix, sound, phrase * 7.0 + when,
                       float(rng.uniform(-0.43, 0.43)))

    # Circular room reflections preserve the loop without a lossy end crossfade.
    dry = mix.copy()
    for delay, gain, cross in [(0.163, 0.12, True), (0.431, 0.08, False),
                               (0.827, 0.05, True), (1.343, 0.025, False)]:
        wet = np.roll(dry, int(round(delay * SAMPLE_RATE)), axis=0)
        mix += gain * (wet[:, ::-1] if cross else wet)
    mix -= np.mean(mix, axis=0)
    mix *= 10.0 ** (PEAK_DBFS / 20.0) / float(np.max(np.abs(mix)))
    return np.round(mix * 32767.0).astype(np.int16)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def encode(ffmpeg: str, source: Path, target: Path) -> None:
    # bitexact also fixes the Ogg serial number; metadata has no time/path values.
    subprocess.run([ffmpeg, "-nostdin", "-y", "-v", "error", "-i", str(source),
                    "-map_metadata", "-1", "-fflags", "+bitexact",
                    "-flags:a", "+bitexact", "-c:a", "libvorbis", "-q:a", "5",
                    "-metadata", "title=Night Watch", "-metadata",
                    "comment=Original procedural composition; seed 20261104",
                    str(target)], check=True)


def decode(ffmpeg: str, source: Path) -> np.ndarray:
    raw = subprocess.run([ffmpeg, "-nostdin", "-v", "error", "-i", str(source),
                          "-f", "f32le", "-acodec", "pcm_f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").reshape((-1, 2)).astype(np.float64)


def measurements(samples: np.ndarray) -> dict:
    peak = float(np.max(np.abs(samples)))
    rms = float(np.sqrt(np.mean(samples ** 2)))
    differences = np.abs(np.diff(samples, axis=0))
    reference = float(np.quantile(differences, 0.99))
    seam = float(np.max(np.abs(samples[0] - samples[-1])))
    near = np.concatenate([samples[-512:], samples[:512]])
    near_p99 = float(np.quantile(np.abs(np.diff(near, axis=0)), 0.99))
    spectrum = np.fft.rfft(samples, axis=0)
    energy = np.sum(np.abs(spectrum) ** 2, axis=1)
    frequencies = np.fft.rfftfreq(len(samples), 1.0 / SAMPLE_RATE)
    return {
        "sample_rate": SAMPLE_RATE,
        "channels": 2,
        "samples": len(samples),
        "seconds": len(samples) / SAMPLE_RATE,
        "peak": peak,
        "peak_dbfs": 20.0 * math.log10(max(peak, 1e-12)),
        "rms": rms,
        "rms_dbfs": 20.0 * math.log10(max(rms, 1e-12)),
        "clipped_samples": int(np.count_nonzero(np.abs(samples) >= 1.0)),
        "dc_per_channel": np.mean(samples, axis=0).tolist(),
        "stereo_difference_rms": float(np.sqrt(np.mean((samples[:, 0] - samples[:, 1]) ** 2))),
        "seam_delta": seam,
        "background_difference_p99": reference,
        "seam_to_background_p99": seam / max(reference, 1e-12),
        "seam_window_difference_p99": near_p99,
        "seam_window_to_background_p99": near_p99 / max(reference, 1e-12),
        "energy_above_2000hz_fraction": float(np.sum(energy[frequencies > 2000.0]) / np.sum(energy)),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--asset-path", type=Path)
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    parser.add_argument("--verify-reproducible", action="store_true")
    args = parser.parse_args()
    if args.asset_path and args.asset_path.name != NAME + ".ogg":
        parser.error("--asset-path must end in night_watch.ogg; other tracks are never replaced")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    # Keep source WAVs and QA previews out of Godot's asset import scan.
    (args.output_dir / ".gdignore").touch()
    wav = args.output_dir / (NAME + ".wav")
    ogg = args.output_dir / (NAME + ".ogg")
    pcm = compose()
    wavfile.write(wav, SAMPLE_RATE, pcm)
    encode(args.ffmpeg, wav, ogg)
    decoded = decode(args.ffmpeg, ogg)
    wav_info = measurements(pcm.astype(np.float64) / 32768.0)
    ogg_info = measurements(decoded)
    valid = all([
        len(decoded) == SAMPLES,
        ogg_info["clipped_samples"] == 0,
        -8.0 < ogg_info["peak_dbfs"] < -5.0,
        ogg_info["rms"] > 0.01,
        ogg_info["stereo_difference_rms"] > 0.001,
        ogg_info["seam_to_background_p99"] < 2.0,
        ogg_info["seam_window_to_background_p99"] < 2.0,
        ogg_info["energy_above_2000hz_fraction"] < 0.01,
    ])
    report = {
        "composition": "Original procedural D-minor pentatonic night watch",
        "seed": SEED,
        "wav_sha256": sha256(wav),
        "ogg_sha256": sha256(ogg),
        "wav": wav_info,
        "decoded_ogg": ogg_info,
        "machine_checks_pass": valid,
        "human_listening": "NOT RUN",
    }
    if args.verify_reproducible:
        with tempfile.TemporaryDirectory(prefix="night-watch-rebuild-") as tmp:
            again_wav = Path(tmp) / wav.name
            again_ogg = Path(tmp) / ogg.name
            wavfile.write(again_wav, SAMPLE_RATE, compose())
            encode(args.ffmpeg, again_wav, again_ogg)
            report["repeat_wav_sha256"] = sha256(again_wav)
            report["repeat_ogg_sha256"] = sha256(again_ogg)
            same = (report["wav_sha256"] == report["repeat_wav_sha256"]
                    and report["ogg_sha256"] == report["repeat_ogg_sha256"])
            report["reproducible_with_current_toolchain"] = same
            valid = valid and same
    report["machine_checks_pass"] = valid
    (args.output_dir / "analysis.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    two_seconds = SAMPLE_RATE * 2
    seam_preview = np.concatenate([decoded[-two_seconds:], decoded[:two_seconds]])
    wavfile.write(args.output_dir / "loop_seam_preview.wav", SAMPLE_RATE,
                  np.round(np.clip(seam_preview, -1.0, 1.0) * 32767.0).astype(np.int16))
    if not valid:
        raise SystemExit("FAIL: see output analysis.json; asset was not copied")
    if args.asset_path:
        args.asset_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ogg, args.asset_path)
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
