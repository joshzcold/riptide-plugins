-- No ffmpeg, and clips in a throwaway folder; the spec swaps in test/bin's curl and uv.
local dir = os.tmpname()
os.remove(dir)
rt.pack.add({
  dir = plugin_test.dir,
  name = "listen",
  opts = {
    ffmpeg = "no-such-ffmpeg",
    dir = dir,
  },
})
