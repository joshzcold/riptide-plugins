-- firenvim, on an nvim without your config.
rt.pack.add({
  dir = plugin_test.dir,
  name = "firenvim",
  opts = { command = plugin_test.dir .. "/test/bin/nvim-clean" },
})
