# riptide-plugins

Plugins for [riptide](https://github.com/joshzcold/riptide), each in its own
folder. Add one to `config.lua` with `subdir`:

```lua
rt.pack.add({
  { "https://github.com/joshzcold/riptide-plugins", subdir = "pass" },  -- brings "passwords"
  { "https://github.com/joshzcold/riptide-plugins", subdir = "reading-list", opts = {} },
})
```

riptide pins each one to a commit in `rt-pack-lock.json`; `:plugins` shows
them and checks for updates.

| Plugin | |
|---|---|
| [passwords](passwords) | Fill logins on the site you're on; the four below bring it |
| [pass](pass) | Logins from pass or gopass |
| [rbw](rbw) | Logins from rbw, the unofficial Bitwarden client |
| [bitwarden](bitwarden) | Logins from the official Bitwarden CLI |
| [keepassxc](keepassxc) | Logins from a KeePassXC database |
| [reading-list](reading-list) | Save pages to read later |

## Writing one

Start from [riptide-plugin-template](https://github.com/joshzcold/riptide-plugin-template),
then add the plugin here as a folder with its `riptide-plugin.toml`
(listing in `dependencies` any plugin here it builds on),
`lua/<name>/` and `test/*_spec.lua`. `riptide --plugin-test <folder>` runs
its tests; CI runs every folder's on each push. The
[plugin guide](https://joshzcold.github.io/riptide/configuration/plugins.html)
covers the API, permissions and testing.
