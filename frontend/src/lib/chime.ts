/**
 * chime.ts — Programmatic notification chime using Web Audio API.
 *
 * Generates a pleasant two-tone chime (A5 → E6, a perfect fifth)
 * entirely in code. No external audio file needed.
 *
 * Usage:
 *   import { playChime } from '../lib/chime';
 *   playChime();
 */

let audioCtx: AudioContext | null = null;

function getAudioContext(): AudioContext {
    if (!audioCtx) {
        audioCtx = new (window.AudioContext ||
            (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)();
    }
    return audioCtx;
}

/**
 * Play a two-tone notification chime.
 * Returns a promise that resolves when the chime finishes (~400ms).
 *
 * Silently no-ops if Web Audio API is unavailable or browser blocks audio.
 */
export function playChime(volume = 0.3): Promise<void> {
    return new Promise((resolve) => {
        try {
            const ctx = getAudioContext();

            // Resume context if suspended (autoplay policy)
            if (ctx.state === 'suspended') {
                ctx.resume().catch(() => { });
            }

            const now = ctx.currentTime;

            // Master gain
            const masterGain = ctx.createGain();
            masterGain.gain.value = volume;
            masterGain.connect(ctx.destination);

            // Tone 1: A5 (880 Hz), 150ms with exponential decay
            const osc1 = ctx.createOscillator();
            const gain1 = ctx.createGain();
            osc1.type = 'sine';
            osc1.frequency.value = 880;
            gain1.gain.setValueAtTime(0.6, now);
            gain1.gain.exponentialRampToValueAtTime(0.01, now + 0.15);
            osc1.connect(gain1);
            gain1.connect(masterGain);
            osc1.start(now);
            osc1.stop(now + 0.15);

            // Tone 2: E6 (1320 Hz), 200ms with exponential decay, starts after 200ms gap
            const osc2 = ctx.createOscillator();
            const gain2 = ctx.createGain();
            osc2.type = 'sine';
            osc2.frequency.value = 1320;
            gain2.gain.setValueAtTime(0.6, now + 0.2);
            gain2.gain.exponentialRampToValueAtTime(0.01, now + 0.4);
            osc2.connect(gain2);
            gain2.connect(masterGain);
            osc2.start(now + 0.2);
            osc2.stop(now + 0.4);

            // Clean up after both tones finish
            osc2.onended = () => {
                masterGain.disconnect();
                resolve();
            };
        } catch {
            // Web Audio API not supported — silently ignore
            resolve();
        }
    });
}
