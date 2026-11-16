# listen

Hear the article on the page you're on read aloud by
[Kokoro](https://huggingface.co/hexgrad/Kokoro-82M), or a short summary of it
written by a local LLM, and keep the clips to play later, with the text
following along.

`gA` (or `:listen`) finds the article with reader's Readability and has Kokoro
read it into a clip, paragraph by paragraph. `:listen summary` asks
[Ollama](https://ollama.com) for a short summary meant to be heard and reads
that instead (`read = "summary"` makes it what `gA` does). It works in the
background, so keep browsing; a message says when the clip is ready. Articles
longer than about an hour of speech are cut there.

`:listen-library` lists your clips, newest first, to play (at 0.75× to 2×),
filter, open the page it came from, or delete. While one plays, its text shows
under the player with the paragraph being read marked and scrolled into view;
click a paragraph to jump to it. Scrolling the text yourself pauses following
for a few seconds.

Nothing leaves your computer: Kokoro reads on your CPU, summaries are written
by Ollama on `localhost`, and the clips are saved in `~/.local/share/riptide/listen` (or the `dir`
option).

## Setup

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "listen" })
```

Then open `:listen-library`. Its Setup section checks for Kokoro, its voice and
ffmpeg, and, for summaries, Ollama and the model. For each one that's missing,
it either does it for you or shows the command for your system:

- **Ollama**: the install command, or how to start it if it's installed but
  not answering.
- **The model**: a button that pulls it through Ollama.
- **Kokoro**: **Install Kokoro** downloads its model and voices (about 350 MB,
  from [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx)) into
  `voices/kokoro/` beside the clips. It needs [uv](https://docs.astral.sh/uv/),
  or the page shows how to install it: listen writes a small script there and
  runs it with `uv run --script`, which installs its Python packages the first
  time, so the first clip takes a little longer.
- **The voice**: pick a language, then any of Kokoro's 41 voices in it:
  English (American and British), Spanish, French, Hindi, Italian and
  Brazilian Portuguese. Heart is the default; it and Bella are the ones
  Kokoro's authors grade best. Switching is instant, and the Setup title
  names the voice in use. New clips use it; earlier clips keep the voice they
  were read in. Each voice reads its own language, so pick an English one for
  English articles.
- **ffmpeg** (optional): the install command.

Install commands are given for Debian and Ubuntu (and their derivatives),
Fedora, Arch, openSUSE, macOS with Homebrew and Windows, and left out where
there's no package that works out of the box, e.g. ffmpeg on openSUSE or RHEL;
the page links to the project's downloads instead.

Pressing `gA` before Kokoro is ready opens the library too.

Options, all optional:

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "listen", opts = {
  read = "article",                -- or "summary"
  model = "llama3.2",              -- any model in Ollama, for summaries
  words = 150,                     -- about how long the summary is
  -- ollama = "http://localhost:11434",
  -- key = "gA",                   -- false for none
} })
```

With [ffmpeg](https://ffmpeg.org) installed, clips are compressed to `.ogg`,
about a tenth the size of the `.wav` Kokoro writes. `:pack-health` checks for
Kokoro and ffmpeg too.

It brings [reader](../reader), for Readability. It asks to read the pages you
use it on, to run curl, uv and ffmpeg, and to read and delete the clips it
saved. It needs riptide 0.20 or newer, whose plugin pages can play audio.
