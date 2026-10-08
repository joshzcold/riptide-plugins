# bitwarden

Fills logins from the official [Bitwarden CLI](https://bitwarden.com/help/cli/) (`bw`), through the [passwords](../passwords) plugin, which
riptide adds with it.

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "bitwarden" })
```

The first fill asks for the master password and keeps the session until
riptide quits or `:password-lock`. The password goes to `bw` in its
environment, never on its command line. Option: `command`.

On riptide 0.4 and newer, you can save the master password on the Plugins tab:
it's kept in your OS keyring, and the vault then unlocks without asking.

The [passwords guide](https://joshzcold.github.io/riptide/guide/passwords.html) has the keys and the rest of the options.
