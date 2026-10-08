# riptide-plugins

Plugins for [riptide](https://github.com/joshzcold/riptide), each in its own
folder. Add one to `config.lua` with `subdir`:

```lua
rt.pack.add({
  { "https://github.com/joshzcold/riptide-plugins", subdir = "passwords", opts = { backend = "pass" } },
  { "https://github.com/joshzcold/riptide-plugins", subdir = "reading-list", opts = {} },
})
```

riptide pins each one to a commit in `rt-pack-lock.json`; `:plugins` shows
them and checks for updates.

| Plugin | |
|---|---|
| [passwords](passwords) | Fill logins from pass, gopass, rbw, the Bitwarden CLI or KeePassXC |
| [reading-list](reading-list) | Save pages to read later |

## Writing one

Start from [riptide-plugin-template](https://github.com/joshzcold/riptide-plugin-template),
then add the plugin here as a folder with its `riptide-plugin.toml`,
`lua/<name>/` and `test/*_spec.lua`. `riptide --plugin-test <folder>` runs
its tests; CI runs every folder's on each push. The
[plugin guide](https://joshzcold.github.io/riptide/configuration/plugins.html)
covers the API, permissions and testing.
