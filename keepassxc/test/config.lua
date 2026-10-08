-- keepassxc-cli through test/bin/fake-keepassxc-cli: the database is
-- ~/x.kdbx and its password "dbpass".
rt.pack.add({
  dir = plugin_test.dir,
  name = "keepassxc",
  opts = { command = plugin_test.dir .. "/test/bin/fake-keepassxc-cli", database = "~/x.kdbx" },
})
