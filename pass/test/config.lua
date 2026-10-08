-- pass, on the store of empty entries in test/store and test/bin/fake-pass.
rt.pack.add({
  dir = plugin_test.dir,
  name = "pass",
  opts = { command = plugin_test.dir .. "/test/bin/fake-pass", store = plugin_test.dir .. "/test/store" },
})
