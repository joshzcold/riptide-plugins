-- Fake curl and piper from test/bin, and clips in a throwaway folder.
local dir = os.tmpname()
os.remove(dir)
rt.pack.add({
  dir = plugin_test.dir,
  name = "listen",
  opts = {
    voice = plugin_test.dir .. "/test/voice/test-voice.onnx",
    piper = plugin_test.dir .. "/test/bin/fake-piper",
    ffmpeg = "no-such-ffmpeg",
    dir = dir,
  },
})
