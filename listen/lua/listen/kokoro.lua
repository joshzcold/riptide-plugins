-- The script listen runs with `uv run --script` to read with Kokoro. Plugins
-- can't see their own folder, so listen writes it into its data folder. Each
-- line of text in becomes a WAV file out, with "Wrote PATH" logged.
return [=[
# /// script
# requires-python = ">=3.10,<3.14"
# dependencies = ["kokoro-onnx>=0.5,<0.7"]
# ///
"""Kokoro text to speech for riptide's listen plugin.

--list-voices prints the voices as JSON. Otherwise each line of stdin becomes
OUTPUT_DIR/NNNNN.wav, and "Wrote PATH" goes to stderr.
"""
import argparse
import json
import os
import sys
import wave

import numpy as np
from kokoro_onnx import Kokoro

# A voice's first letter is its language.
LANGS = {
    "a": "en-us", "b": "en-gb", "e": "es", "f": "fr-fr",
    "h": "hi", "i": "it", "p": "pt-br",
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--voices", required=True)
    parser.add_argument("--voice", default="af_heart")
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--output_dir")
    parser.add_argument("--list-voices", action="store_true")
    args = parser.parse_args()

    kokoro = Kokoro(args.model, args.voices)
    if args.list_voices:
        print(json.dumps([v for v in kokoro.get_voices() if v[:1] in LANGS]))
        return
    if not args.output_dir:
        sys.exit("--output_dir is needed")
    lang = LANGS.get(args.voice[:1], "en-us")
    os.makedirs(args.output_dir, exist_ok=True)
    n = 0
    for line in sys.stdin:
        text = line.strip()
        if not text:
            continue
        n += 1
        samples, rate = kokoro.create(text, voice=args.voice, speed=args.speed, lang=lang)
        pcm = (np.clip(samples, -1.0, 1.0) * 32767).astype("<i2").tobytes()
        path = os.path.join(args.output_dir, "%05d.wav" % n)
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(pcm)
        print("Wrote " + path, file=sys.stderr, flush=True)


if __name__ == "__main__":
    main()
]=]
