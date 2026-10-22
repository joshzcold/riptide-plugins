# Plan: more Vim and Neovim favourites as riptide plugins

[firenvim](firenvim), [telescope](telescope), [harpoon](harpoon), [oil](oil)
and [flash](flash) are done. These are next, in order. Each entry says what it is, how it would work in riptide, and what
riptide would need that plugins can't do today.

## 1. search and translate the selection

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

## 2. reader mode

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

## Flash follow-ups

- **Frames:** label text inside iframes too, with `rt.page.eval` in each
  frame, placing labels with each frame's offset as hints do.
- **Labels after the match**, as flash.nvim draws them, rather than over
  its first character.
