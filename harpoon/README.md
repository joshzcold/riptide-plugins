# harpoon

Mark a handful of pages and jump straight to them, like
[harpoon](https://github.com/ThePrimeagen/harpoon).

| Key | Command | |
|---|---|---|
| `<Space>a` | `:harpoon-add` | mark this page |
| `<Space>1` … `<Space>4` | `:harpoon-go 1` … | jump to mark 1 … 4 |
| `<Space>h` | `:harpoon` | list the marks |
| | `:harpoon-clear` | forget every mark |

A jump switches to the page's tab if it's open in this window, and opens it
in the current tab otherwise. In the list, `j`/`k` move, `Enter` or a number
jumps, `J`/`K` reorder and `d` removes a mark.

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "harpoon", opts = {
  slots = 9,     -- <Space>1 … <Space>9
  keys = false,  -- no keys; use the commands
} })
```

Switching to an open tab needs riptide 0.8, and so do the list's keys, which
riptide's floats missed until then (riptide#54). On older riptides a jump
opens the page in the current tab, and the list shows the marks.
