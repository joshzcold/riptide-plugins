-- bw through test/bin/fake-bw, whose master password is "correct".
rt.pack.add({
  dir = plugin_test.dir,
  name = "bitwarden",
  opts = { command = plugin_test.dir .. "/test/bin/fake-bw" },
})
