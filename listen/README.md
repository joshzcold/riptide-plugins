# listen

Hear the article on the page you're on read aloud by
[Piper](https://github.com/OHF-Voice/piper1-gpl), or a short summary of it
written by a local LLM, and keep the clips to play later, with the text
following along.

`gA` (or `:listen`) finds the article with reader's Readability and has Piper
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

Nothing leaves your computer: summaries are written by Ollama on `localhost`,
and the clips are saved in `~/.local/share/riptide/listen` (or the `dir`
option).

## Setup

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "listen" })
```

Then open `:listen-library`. Its Setup section checks for Piper, a voice and
ffmpeg, and, for summaries, Ollama and the model. For each one that's missing,
it either does it for you or shows the command for your system:

- **Ollama**: the install command, or how to start it if it's installed but
  not answering.
- **The model**: a button that pulls it through Ollama.
- **Piper**: a button that installs it with `uv tool install piper-tts` or
  `pipx install piper-tts`, whichever you have (pick one if both), or how to
  install uv first.
- **A voice**: pick a language, then any of
  [piper-voices](https://huggingface.co/rhasspy/piper-voices)' voices in it
  (182 in 58 languages; the list is fetched when you open the page and kept
  for a week), and download it into `voices/` beside the clips. Each shows its
  quality and download size; downloads only happen when you press the button.
  The list stays afterwards, so you can switch voices any time (instantly, to
  one you've already downloaded); the Setup title names the voice in use. New
  clips use it; earlier clips keep the voice they were read in. Voices with
  several speakers read with the first. If the list can't be fetched, a few
  English voices are offered.
- **ffmpeg** (optional): the install command.

Install commands are given for Debian and Ubuntu (and their derivatives),
Fedora, Arch, openSUSE, macOS with Homebrew and Windows, and left out where
there's no package that works out of the box, e.g. ffmpeg on openSUSE or RHEL;
the page links to the project's downloads instead.

Pressing `gA` before Piper and a voice are ready opens the library too.

Options, all optional:

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "listen", opts = {
  voice = os.getenv("HOME") .. "/.local/share/piper/en_US-lessac-medium.onnx", -- any Piper voice; replaces the picker
  read = "article",                -- or "summary"
  model = "llama3.2",              -- any model in Ollama, for summaries
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
