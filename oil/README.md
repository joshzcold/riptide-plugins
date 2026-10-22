# oil

Edit your tabs, bookmarks and quickmarks as text in nvim, like
[oil.nvim](https://github.com/stevearc/oil.nvim) does for files. Each `:w`
applies what changed, and the list is shown again as it now is.

| Command | One line per | `:w` |
|---|---|---|
| `:oil tabs` (or `:oil`) | tab of this window: `/3 URL  title` | closes tabs whose lines are gone, reorders the rest as the lines are, and opens new URLs |
| `:oil bookmarks` | bookmark: `URL  title` | saves the bookmarks as listed |
| `:oil quickmarks` | quickmark: `name  URL` | saves the quickmarks as listed |

In the tab list, the `/3` keeps track of the tab, so move the whole line.
A line without one opens its URL in a background tab, and changing a tab's
URL closes that tab and opens the new one. Lines starting with `#` are left
out.

nvim runs in a float, from the [firenvim](../firenvim) plugin, which riptide
adds with this one; its options (the nvim command, the font) apply here too.
The file nvim edits is `riptide-tabs.oil` (or `-bookmarks`, `-quickmarks`),
so your config can give it a filetype.

It needs riptide 0.8, and asks to read and change your bookmarks and
quickmarks.
