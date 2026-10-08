-- rbw through test/bin/fake-rbw, with the passwords plugin submitting the form.
rt.pack.add({
  { dir = plugin_test.dir .. "/../passwords", opts = { submit = true } },
  { dir = plugin_test.dir, name = "rbw", opts = { command = plugin_test.dir .. "/test/bin/fake-rbw" } },
})
