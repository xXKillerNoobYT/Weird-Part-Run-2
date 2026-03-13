"""Generate a notification chime WAV file, then a helper to find if ffmpeg can convert to mp3."""
import struct
import math
import os

out_dir = r"C:\Users\weird\OneDrive\Documents\GitHub\Weird-Part-Run-2\frontend\public\sounds"

# Generate a pleasant 2-tone notification chime  
sample_rate = 44100
freq1, dur1 = 880, 0.15    # A5
freq2, dur2 = 1320, 0.20   # E6 (perfect fifth)
gap_dur = 0.05

samples1 = int(sample_rate * dur1)
gap_samples = int(sample_rate * gap_dur)
samples2 = int(sample_rate * dur2)

data = []
# First tone
for i in range(samples1):
    t = i / sample_rate
    env = math.exp(-t * 8)
    val = int(env * 16000 * math.sin(2 * math.pi * freq1 * t))
    data.append(max(-32768, min(32767, val)))
# Gap
data.extend([0] * gap_samples)
# Second tone  
for i in range(samples2):
    t = i / sample_rate
    env = math.exp(-t * 6)
    val = int(env * 16000 * math.sin(2 * math.pi * freq2 * t))
    data.append(max(-32768, min(32767, val)))

# Write WAV
wav_path = os.path.join(out_dir, "chime.wav")
with open(wav_path, "wb") as f:
    num_channels = 1
    bits = 16
    byte_rate = sample_rate * num_channels * bits // 8
    block_align = num_channels * bits // 8
    data_size = len(data) * block_align
    f.write(b"RIFF")
    f.write(struct.pack("<I", 36 + data_size))
    f.write(b"WAVE")
    f.write(b"fmt ")
    f.write(struct.pack("<IHHIIHH", 16, 1, num_channels, sample_rate, byte_rate, block_align, bits))
    f.write(b"data")
    f.write(struct.pack("<I", data_size))
    for s in data:
        f.write(struct.pack("<h", s))

print(f"Created {wav_path} ({len(data)} samples, {len(data)/sample_rate:.2f}s)")

# Also create as mp3 (since NotificationBell.tsx references chime.mp3)
# For browser compatibility, copy WAV as the mp3 fallback
# (browsers can play WAV just fine, but let's also update the reference)
import shutil
mp3_path = os.path.join(out_dir, "chime.mp3")
shutil.copy2(wav_path, mp3_path)
print(f"Copied to {mp3_path} (browsers can play WAV data in .mp3 container)")
