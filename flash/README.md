# flash

Jump to any text on screen by typing two of its characters, like
[flash.nvim](https://github.com/folke/flash.nvim) and
[leap.nvim](https://github.com/ggandor/leap.nvim).

| Key | Command | |
|---|---|---|
| `<Space>s` | `:flash` | jump there and start caret mode, to move or select from it (`v`, then `y`) |
| `<Space>S` | `:flash follow` | follow the link the text is in |

Type two characters: every place they show on screen gets a label, and
typing a label jumps there. With only one place, it jumps straight away.
A capital letter makes the search match case; `Escape` cancels.

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "flash", opts = {
  key = "s",         -- instead of <Space>s, if you don't use riptide's s… split keys
  follow_key = false,
} })
```

It labels text in the page and in its iframes, such as Gmail's chat, open
shadow roots included, and starts caret mode in the frame the text is in.
It needs riptide 0.8, and asks to read and label the pages you use it on.
