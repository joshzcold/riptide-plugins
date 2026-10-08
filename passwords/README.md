# passwords

Fill logins from your password manager's command line tool: pass, gopass,
rbw, the Bitwarden CLI or KeePassXC.

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "passwords", opts = { backend = "pass" } })
```

The first time it loads, riptide asks you to allow it to run programs (your
password manager) and to fill in pages. `<Space>pp` fills the username and
password, `<Space>pu` the username, `<Space>pw` the password. The
[passwords guide](https://joshzcold.github.io/riptide/guide/passwords.html)
has every option.
