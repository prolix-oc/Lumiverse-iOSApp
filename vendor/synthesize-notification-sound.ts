#!/usr/bin/env bun
import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

// Original, related D-major sound marks. Additive/FM synthesis only: no samples.
// Short stages introduce the motif; completion resolves it with two warm chord
// voicings, a rounded mallet melody, a soft octave answer and a diffused tail.
const sampleRate = 44_100, tau = Math.PI * 2;
const frequency = (midi: number) => 440 * 2 ** ((midi - 69) / 12);
type Voice = "pad" | "mallet" | "glass";
function synthesize(name: string, duration: number, peakDB: number,
  score: (note: (midi: number, start: number, gain: number, decay: number, kind?: Voice) => void) => void) {
  const samples = new Float64Array(Math.round(sampleRate * duration));
  function note(midi: number, start: number, gain: number, decay: number, kind: Voice = "mallet") {
    const hz = frequency(midi), attack = kind === "pad" ? 0.065 : kind === "glass" ? 0.014 : 0.006;
    for (let i = Math.round(start * sampleRate); i < samples.length; i++) {
      const t = i / sampleRate - start;
      const envelope = (1 - Math.exp(-t / attack)) ** 2 * Math.exp(-t / decay);
      const phase = tau * hz * t;
      // A restrained FM transient adds a wood/glass character, rather than the
      // hard high-frequency strike of a metallic notification bell.
      const tone = kind === "pad"
        ? 0.64 * Math.sin(phase) + 0.18 * Math.sin(phase * 1.0018 + 0.2) + 0.18 * Math.sin(phase * 0.9982 - 0.2)
          + 0.045 * Math.sin(phase * 2) * Math.exp(-t / 0.2)
        : Math.sin(phase + (kind === "glass" ? 0.42 : 0.25) * Math.exp(-t / 0.085) * Math.sin(phase * 2))
          + 0.12 * Math.sin(phase * 2) * Math.exp(-t / 0.15)
          + 0.035 * Math.sin(phase * 3) * Math.exp(-t / 0.07);
      samples[i] += gain * envelope * tone;
    }
  }
  score(note);
  // Parallel, gently low-passed reflections. No feedback or nonlinear clipping.
  const dry = samples.slice();
  for (const [delay, gain] of [[0.047, 0.13], [0.079, 0.10], [0.127, 0.075], [0.193, 0.045], [0.293, 0.025]] as const) {
    const offset = Math.round(delay * sampleRate);
    let filtered = 0;
    for (let i = offset; i < samples.length; i++) {
      filtered += 0.32 * (dry[i - offset]! - filtered);
      samples[i] += filtered * gain;
    }
  }
  let mean = 0;
  for (const value of samples) mean += value / samples.length;
  let peak = 0;
  for (let i = 0; i < samples.length; i++) {
    const endFade = Math.min(1, (samples.length - 1 - i) / (sampleRate * Math.min(0.3, duration * 0.25)));
    const startFade = Math.min(1, i / (sampleRate * 0.004));
    samples[i] = (samples[i]! - mean) * endFade ** 2 * startFade;
    peak = Math.max(peak, Math.abs(samples[i]!));
  }
  const wav = Buffer.alloc(44 + samples.length * 2);
  wav.write("RIFF", 0); wav.writeUInt32LE(wav.length - 8, 4); wav.write("WAVEfmt ", 8);
  wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(sampleRate, 24); wav.writeUInt32LE(sampleRate * 2, 28);
  wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34); wav.write("data", 36);
  wav.writeUInt32LE(samples.length * 2, 40);
  const level = 10 ** (peakDB / 20) / peak;
  let energy = 0;
  for (let i = 0; i < samples.length; i++) {
    const value = samples[i]! * level;
    energy += value * value;
    wav.writeInt16LE(Math.round(value * 32767), 44 + i * 2);
  }
  const output = resolve(import.meta.dir, "../ios/sounds");
  mkdirSync(output, { recursive: true });
  writeFileSync(join(output, `lumiverse-${name}.wav`), wav);
  console.log(`${name}: ${duration}s, PCM16 mono 44.1 kHz, peak ${peakDB} dBFS, RMS ${(10 * Math.log10(energy / samples.length)).toFixed(1)} dBFS`);
}

synthesize("prepare", 0.75, -8, note => {
  note(62, 0, 0.1, 0.16, "pad");
  note(74, 0.008, 0.28, 0.12); note(81, 0.105, 0.13, 0.12, "glass");
});
synthesize("think", 1.05, -8, note => {
  note(66, 0, 0.11, 0.23, "pad"); note(69, 0, 0.08, 0.2, "pad");
  note(78, 0.008, 0.19, 0.16); note(81, 0.145, 0.17, 0.16); note(85, 0.29, 0.11, 0.17, "glass");
});
synthesize("respond", 1.2, -7, note => {
  note(69, 0, 0.1, 0.25, "pad"); note(76, 0, 0.06, 0.24, "pad");
  for (const [midi, start, gain] of [[74, 0.008, 0.20], [78, 0.105, 0.18], [81, 0.22, 0.16], [86, 0.36, 0.10]])
    note(midi!, start!, gain!, 0.18);
});
synthesize("complete", 2.85, -3, note => {
  // Gmaj9 opens into Dmaj9/add6. Spread the voices so the chord stays clear
  // through a phone speaker, with little energy below 190 Hz or above 4 kHz.
  for (const [midi, gain] of [[55, 0.065], [62, 0.075], [66, 0.055], [69, 0.045], [71, 0.04]])
    note(midi!, 0, gain!, 0.35, "pad");
  for (const [midi, gain] of [[62, 0.08], [66, 0.075], [69, 0.055], [73, 0.04], [76, 0.04], [83, 0.02]])
    note(midi!, 0.39, gain!, 0.52, "pad");
  for (const [midi, start, gain] of [[74, 0.008, 0.23], [78, 0.115, 0.20], [81, 0.24, 0.19], [85, 0.405, 0.12], [86, 0.57, 0.19]])
    note(midi!, start!, gain!, 0.27, "glass");
  note(78, 0.76, 0.055, 0.32); note(81, 0.87, 0.045, 0.29); note(86, 1.0, 0.04, 0.34, "glass");
});
