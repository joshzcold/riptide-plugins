# firenvim

Edits text fields in nvim, drawn right over the field, like
[firenvim](https://github.com/glacambre/firenvim) does in Firefox and Chrome.
It runs your nvim with your config, so your keys, plugins and colors are
there.

Focus a text area or text input and press `<Ctrl-Shift-e>` (or run
`:firenvim`). Each `:w` puts the text back in the field, as if you had typed
it, so the page sees it; `:q` closes nvim and puts the cursor back in the
field. While nvim is open it gets every key, Escape included; `<Shift-Escape>`
closes it without writing.

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "firenvim", opts = {
  auto = "textarea",       -- open by itself on text areas; "all" for any text field; "off" by default
  key = "<Ctrl-Shift-e>",  -- false for no key
  font = "14px JetBrains Mono",
  extension = "md",        -- the file nvim edits, for its filetype
} })
```

The file is named after the site and the field, e.g. `github.com_comment.md`,
so your config can match it, and `vim.g.started_by_riptide` is set:

```lua
-- init.lua
vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "github.com_*",
  callback = function() vim.bo.filetype = "markdown" end,
})
if vim.g.started_by_riptide then vim.o.laststatus = 0 end
```

`auto` opens nvim when you focus a field and riptide enters insert mode. It
leaves a field alone once you've closed nvim on it, and moving straight from
one field to another doesn't open it, since riptide is already in insert
mode; press the key there.

## How it works

The plugin starts `nvim --headless`, which listens on a random port on
127.0.0.1 for one WebSocket connection with a one-time token, from this
plugin's page only. The page draws nvim's screen and sends it your keys and
clicks over nvim's own RPC. nvim quits when the page closes, or if the page
never connects.

It needs riptide 0.4.1 or newer, for float pages that cover a field and take
every key, and for `network = ["127.0.0.1"]`. It asks to run programs (nvim),
to read and fill fields on every site, and to connect to 127.0.0.1.
