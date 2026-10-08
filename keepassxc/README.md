# keepassxc

Fills logins from a [KeePassXC](https://keepassxc.org/) database through `keepassxc-cli`, through the [passwords](../passwords) plugin, which
riptide adds with it.

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "keepassxc", opts = { database = "~/Passwords.kdbx" } })
```

`database` is required. Every fill asks for the database password, or keeps it
for `remember = 300` seconds; it goes to `keepassxc-cli` on its input. Options:
`keyfile`, `remember` and `command`.

The [passwords guide](https://joshzcold.github.io/riptide/guide/passwords.html) has the keys and the rest of the options.
