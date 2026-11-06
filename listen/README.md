# listen

Hear a spoken summary of the page you're on, written by a local LLM and read
aloud by [Piper](https://github.com/OHF-Voice/piper1-gpl), and keep the clips
to play later.

`gA` (or `:listen`) finds the article with reader's Readability, asks
[Ollama](https://ollama.com) for a short summary meant to be heard, and has
Piper read it into a clip. It works in the background, so keep browsing;
a message says when the clip is ready. `:listen-library` lists your clips,
newest first, to play (at 0.75× to 2×), filter, read the summary, open the
page it came from, or delete.

Nothing leaves your computer: the article goes to Ollama on `localhost`, and
the clips are saved in `~/.local/share/riptide/listen` (or the `dir` option).

## Setup

```sh
ollama pull llama3.2
pipx install piper-tts
```

Then pick a voice from [piper-voices](https://huggingface.co/rhasspy/piper-voices)
and save its `.onnx` and `.onnx.json` side by side, e.g. in `~/.local/share/piper`.

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "listen", opts = {
  voice = os.getenv("HOME") .. "/.local/share/piper/en_US-lessac-medium.onnx",
  model = "llama3.2",              -- any model you've pulled in Ollama
  words = 150,                     -- about how long the summary is
  -- ollama = "http://localhost:11434",
  -- key = "gA",                   -- false for none
} })
```

With [ffmpeg](https://ffmpeg.org) installed, clips are saved as Opus, about a
tenth the size of the WAV Piper writes. `:pack-health` checks for curl, piper,
the voice and ffmpeg.

It brings [reader](../reader), for Readability. It asks to read the pages you
use it on, to run curl, piper and ffmpeg, and to read and delete the clips it
saved. Playing a clip needs a riptide newer than 0.17.0 (riptide#159).
