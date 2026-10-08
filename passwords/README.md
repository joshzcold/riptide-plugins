# passwords

Fills logins on the site you're on from your password managers. It runs no
programs itself: add the plugin for your password manager, which brings this
one with it.

| Plugin | Password manager |
|---|---|
| [pass](../pass) | pass or gopass |
| [rbw](../rbw) | rbw, the unofficial Bitwarden client |
| [bitwarden](../bitwarden) | the official Bitwarden CLI (`bw`) |
| [keepassxc](../keepassxc) | a KeePassXC database (`keepassxc-cli`) |

`<Space>pp` (`:password-fill`) fills the username and password, `<Space>pu`
the username and `<Space>pw` the password. With several password managers on,
the picker lists the logins of all of them. Add this plugin yourself only to
change its options:

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "passwords", opts = {
  submit = true,                        -- press the form's button after :password-fill
  keys = { login = "<Ctrl-Shift-l>" },  -- your own keys; false for none
} })
```

It checks every login against the site itself, so a password manager plugin
can't put a lookalike site's login in the picker, and it fills nothing if the
tab moves to another site meanwhile. The [passwords guide](https://joshzcold.github.io/riptide/guide/passwords.html) has the rest.
