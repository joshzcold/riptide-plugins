-- oil, and the firenvim it edits in, on an nvim without your config.
rt.pack.add({
  {
    dir = plugin_test.dir .. "/../firenvim",
    name = "firenvim",
    opts = { command = plugin_test.dir .. "/../firenvim/test/bin/nvim-clean" },
  },
  { dir = plugin_test.dir, name = "oil" },
})
