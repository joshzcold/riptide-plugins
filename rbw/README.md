# rbw

Fills logins from [rbw](https://github.com/doy/rbw), the unofficial Bitwarden client, through the [passwords](../passwords) plugin, which
riptide adds with it.

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "rbw" })
```

rbw's own agent and pinentry unlock the vault. An entry belongs to a site when
one of its saved addresses (or its name) is the site. Option: `command`.

The [passwords guide](https://joshzcold.github.io/riptide/guide/passwords.html) has the keys and the rest of the options.
