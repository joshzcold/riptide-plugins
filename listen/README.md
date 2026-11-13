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

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "listen" })
```

Then open `:listen-library`. Its Setup section checks for Ollama, the model,
Piper, a voice and ffmpeg, and for each one that's missing either does it for
you or shows the command for your system:

- **Ollama**: the install command, or how to start it if it's installed but
  not answering.
- **The model**: a button that pulls it through Ollama.
- **Piper**: a button that installs it with `uv tool install piper-tts` or
  `pipx install piper-tts`, whichever you have (pick one if both), or how to
  install uv first.
- **A voice**: pick one of a few English voices and download it (about 60 MB,
  from [piper-voices](https://huggingface.co/rhasspy/piper-voices)) into
  `voices/` beside the clips. Downloads only happen when you press the button.
- **ffmpeg** (optional): the install command.

Pressing `gA` before Piper and a voice are ready opens the library too.

Options, all optional:

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "listen", opts = {
  voice = os.getenv("HOME") .. "/.local/share/piper/en_US-lessac-medium.onnx", -- another voice
  model = "llama3.2",              -- any model in Ollama
  words = 150,                     -- about how long the summary is
  -- ollama = "http://localhost:11434",
  -- key = "gA",                   -- false for none
} })
```

With [ffmpeg](https://ffmpeg.org) installed, clips are saved as Opus, about a
tenth the size of the WAV Piper writes. `:pack-health` checks for piper, the
voice and ffmpeg too.

It brings [reader](../reader), for Readability. It asks to read the pages you
use it on, to run curl, piper and ffmpeg, and to read and delete the clips it
saved. It needs riptide 0.20 or newer, whose plugin pages can play audio.
