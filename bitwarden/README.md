# bitwarden

Fills logins from the official [Bitwarden CLI](https://bitwarden.com/help/cli/) (`bw`), through the [passwords](../passwords) plugin, which
riptide adds with it.

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "bitwarden" })
```

The first fill asks for the master password and keeps the session until
riptide quits or `:password-lock`. The password goes to `bw` in its
environment, never on its command line. Option: `command`.

The [passwords guide](https://joshzcold.github.io/riptide/guide/passwords.html) has the keys and the rest of the options.
