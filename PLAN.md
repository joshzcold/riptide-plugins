# Plan: more Vim and Neovim favourites as riptide plugins

[firenvim](firenvim), [telescope](telescope), [harpoon](harpoon), [oil](oil),
[flash](flash) and [reader](reader) are done. What's left is follow-ups to
them.

## Reader follow-ups

- **Images:** plugin pages may only show their own images (`img-src 'self'
  data:`), so reader view shows each image's description instead. Showing
  them needs riptide to let a plugin page load images from the article's
  site, e.g. an `images` permission.

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

- **Labels after the match**, as flash.nvim draws them, rather than over
  its first character.
