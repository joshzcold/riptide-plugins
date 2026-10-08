# pass

Fills logins from [pass](https://www.passwordstore.org/) or [gopass](https://www.gopass.pw/), through the [passwords](../passwords) plugin, which
riptide adds with it.

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "pass" })
```

An entry belongs to a site when part of its path is the site, such as
`websites/example.com/alice`. The first line is the password; the username is a
`login:`, `user:`, `username:` or `email:` line, or else the path part after the
site. Options: `gopass = true`, `store = "~/.password-store"` and `command`.
Use a graphical pinentry: riptide has no terminal for a text one.

The [passwords guide](https://joshzcold.github.io/riptide/guide/passwords.html) has the keys and the rest of the options.
