# telescope

A fuzzy finder over your open tabs, history, bookmarks and quickmarks, like
[telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).

| Key | Command | Finds |
|---|---|---|
| `<Space>ff` | `:telescope` | everything |
| `<Space>ft` | `:telescope tabs` | open tabs in this window |
| `<Space>fh` | `:telescope history` | history |
| `<Space>fb` | `:telescope bookmarks` | bookmarks |
| `<Space>fq` | `:telescope quickmarks` | quickmarks |

Type to filter: each word must match, in order of its letters, in the title
or the URL, and a capital letter makes it match case. History is searched
again as you type, so older pages turn up too.

| In the picker | |
|---|---|
| `Enter` | open it here, or switch to the tab |
| `Ctrl-t` / `Ctrl-b` | open it in a new tab / a background tab |
| `Ctrl-n` `Ctrl-p`, `Down` `Up`, `Tab` | move |
| `Ctrl-w`, `Ctrl-u` | delete a word, the whole prompt |
| `Esc` | close |

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "telescope", opts = {
  keys = false,  -- no <Space>f… keys; use :telescope
} })
```

It needs riptide 0.8, and asks to read your history, bookmarks and
quickmarks.
