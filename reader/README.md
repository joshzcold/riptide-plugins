# reader

Read the article on a page alone, cleanly typeset, in a tab of its own, like
Firefox's Reader View or [zen-mode.nvim](https://github.com/folke/zen-mode.nvim).

`gR` (or `:reader`) finds the article with Mozilla's
[Readability](https://github.com/mozilla/readability) and opens it in a new
tab: the title, byline and reading time, then the text, without the page's
menus, ads, scripts or styles. riptide's own keys work there as on any page:
`j`/`k` and `gg`/`G` to scroll, `+`/`-` to zoom. Links open in that tab, or
a new one with `Ctrl` or the middle button; the site's name at the top goes
back to the page.

Images aren't shown, only their descriptions, since plugin pages can't load
images from other sites. It follows your light or dark preference.

```lua
rt.pack.add({ "https://github.com/joshzcold/riptide-plugins", subdir = "reader", opts = {
  key = "<Space>r",  -- instead of gR; false for none
} })
```

It asks to read the pages you use it on. Readability.js is Apache-2.0; see
[LICENSE-readability.md](LICENSE-readability.md).
