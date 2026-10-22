# Plan: more Vim and Neovim favourites as riptide plugins

[firenvim](firenvim), [telescope](telescope) and [harpoon](harpoon) are
done. These are next, in order. Each entry says what it is, how it would work in riptide, and what
riptide would need that plugins can't do today.

## 1. oil-style editing

Like [oil.nvim](https://github.com/stevearc/oil.nvim): edit lists as text in
nvim, and `:w` applies the changes.

- `:oil tabs` opens the window's tabs as lines (`url  title`) in nvim, drawn
  in a float the way firenvim does it. Deleting a line closes that tab,
  reordering lines reorders the tabs, and a new line opens a URL.
  `:oil bookmarks` and `:oil quickmarks` work the same way on those lists.
- It reuses firenvim's bridge (headless nvim, WebSocket, write-back on `:w`);
  it could depend on firenvim's modules, or share a small `nvim` module.
- **Riptide:**
  - closing and moving tabs: `rt.close_tab(index)` and `rt.move_tab(from, to)`.
  - changing bookmarks and quickmarks: write calls to go with
    `rt.bookmarks()` and `rt.quickmarks()`, under the `history` permission or
    a new write permission.
  - Without these it would need the broad `commands` permission
    (`:tab-close`, `:tab-move`).
- **Open question:** tab ids. `rt.tabs()` gives indexes, which shift as
  tabs close. Applying the edit in one pass, back to front, avoids that;
  stable ids would be cleaner.
- **Size:** medium.

## 2. flash jumping

Like [flash.nvim](https://github.com/folke/flash.nvim) and
[leap.nvim](https://github.com/ggandor/leap.nvim): type a couple of
characters, and every place they appear in the visible text gets a label;
type the label to jump there.

- `s` then two characters labels the matches; the label puts the caret
  there in caret mode, so `v` and `y` can select and copy from it. `S` does
  the same but follows a link at the match, if there is one.
- **Riptide:**
  - Matching and labels can be drawn by the plugin with `rt.page.eval` and
    `rt.page.css`, in the main frame and, with riptide#46, the focused frame.
  - Starting caret mode at a given place needs riptide to take a text
    position, e.g. `rt.page.caret_at(...)`, or the plugin selecting the
    match in the page before running caret mode (which needs `commands`).
- **Open question:** frames. Labels across several cross-origin frames need
  `rt.page.eval` in every frame, like hints, rather than one frame.
- **Size:** medium.

## 3. search and translate the selection

Like [Surfingkeys](https://github.com/brookhong/Surfingkeys)' selection
search.

- In caret or visual mode, `gs` searches the selected text with a search
  engine picked from `url.searchengines`, and `gT` shows a translation in a
  float.
- **Riptide:** nothing new for search: `rt.page.selection` and `rt.open`.
  Reading `url.searchengines` needs the `settings` permission, or an option
  listing the engines. Translation needs a service: the `network`
  permission for its host, and fetching from Lua (riptide has no HTTP call
  for plugins yet), or `rt.spawn` of a command such as `trans`.
- **Size:** small for search; translation depends on the service.

## 4. reader mode

Like [zen-mode.nvim](https://github.com/folke/zen-mode.nvim) for pages: the
article alone, in clean type.

- `:reader` extracts the article with
  [Readability.js](https://github.com/mozilla/readability) and shows it in a
  plugin page, in a tab or a side panel, with the original's links.
- **Riptide:** the page's HTML is read with `rt.page.eval`
  (`document.documentElement.outerHTML`); Readability runs in the plugin's
  page, which ships it as a file. Images from other sites would need
  `img-src` for them in the page's CSP, which plugin pages don't have.
- **Size:** small to medium.

## Telescope follow-ups

- **Command palette:** pick any riptide command and run it. It needs the
  `commands` permission, and a list of commands with their descriptions,
  e.g. `rt.commands()`.
- **More pickers:** open windows (needs `rt.tabs` for every window),
  downloads, sessions.
- **Preview:** show the page beside the list. Plugin pages can only frame
  `https` hosts listed in `frames`, so this would need riptide to render a
  preview itself.
