-- A cleaner riptide, like noice.nvim: the command line as a palette with its
-- matches in groups, questions in a framed box, pill tabs and a quiet status
-- bar. It's all CSS on riptide's own bars, in your theme's colors.
local M = {}

local opts = {}
local enabled = true

-- The command line and its matches (ui.overlay.position = "floating").
-- riptide sizes the box as rows times the row height, so every line keeps
-- that height: the room is added across, never down.
local PALETTE = [[
/* riptide takes the row height from the overlay's largest font; a large
   heading font makes every row taller, and the heading still draws small. */
:root { --font-category: bold 15pt "DejaVu Sans Mono", monospace; }
body.palette:not(.floating) {
  padding: 4px;
  background: var(--bg);
  border: 1px solid var(--noice-line);
}
body.palette:not(.floating) .command-input {
  line-height: var(--row-height);
  padding: 0 12px 0 34px;
  background: none;
  box-shadow: inset 0 -1px 0 var(--noice-line);
  position: relative;
}
body.palette:not(.floating) .command-input::before {
  content: "❯";
  position: absolute;
  left: 14px;
  color: var(--noice-accent);
  font-weight: bold;
}
body.palette:not(.floating) .header {
  line-height: var(--row-height);
  padding: 0 12px;
  background: none;
  color: var(--desc-fg);
  font-size: 0.8em;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
body.palette:not(.floating) .row {
  padding: 0 12px;
  border-radius: 4px;
}
body.palette:not(.floating) .row.selected { background: var(--noice-selected); color: var(--fg); }
body.palette:not(.floating) .row.selected .desc,
body.palette:not(.floating) .row.selected .time,
body.palette:not(.floating) .row.selected .detail { color: var(--desc-fg); }
body.palette:not(.floating) .row.selected .match { color: var(--match-fg); text-decoration: none; }
body.palette:not(.floating) .keyhint { padding: 0 12px; }
]]

-- Questions (prompt.position = "center" or "bottom"). The site asking stays
-- first and large: only the frame and spacing change.
local PROMPTS = [[
body.floating {
  border: 1px solid var(--prompt-accent);
  padding-left: 11px;
}
body.floating .header {
  padding: 0 4px 6px;
  font-size: 0.8em;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
body.floating .prompt-site { font-weight: bold; padding-bottom: 4px; }
body.floating .prompt-input { padding: 0 10px; border-radius: 4px; }
/* riptide gives each option a row and 4px. */
body.floating .prompt-option { height: calc(var(--row-height) + 4px); border-radius: 4px; }
]]

-- The tab bar: rounded tabs on the bar's own color, the current one tinted.
local TABS = [[
body:not(.vertical) #tabs { gap: 4px; padding: 5px 8px; box-sizing: border-box; }
body:not(.vertical) .tab,
body:not(.vertical) .tab:nth-child(odd),
body:not(.vertical) .tab:nth-child(even) {
  flex: 0 1 260px;
  background: none;
  color: var(--noice-muted);
  border-radius: 5px;
  padding: 3px 12px;
}
body:not(.vertical) .tab.selected {
  background: var(--noice-selected);
  color: var(--selected-fg);
  box-shadow: none;
}
body:not(.vertical) .tab.pinned:not(.selected) { background: none; color: var(--pinned-fg); }
/* A pinned tab shrunk to its icon (tabs.pinned.shrink) keeps riptide's width. */
body:not(.vertical) .tab.shrunk { flex: 0 0 auto; padding: 3px 8px; }
/* The dot only while loading or failed, so an idle tab's room is even. */
body:not(.vertical) .tab:not(.loading):not(.error) .indicator { display: none; }
body:not(.vertical) .tab .indicator {
  width: 6px;
  height: 6px;
  align-self: center;
  border-radius: 50%;
}
]]

-- The status bar: plain text on the bar's color, the mode as a pill.
local STATUSBAR = [[
#bar { padding: 3px 12px; gap: 2ch; }
#bar #right { color: var(--noice-muted); }
#bar.insert, #bar.passthrough, #bar.private { background: var(--bg); color: var(--fg); }
#bar.command #left { color: var(--noice-muted); }
#bar.insert #left, #bar.passthrough #left, #bar.private #left {
  flex: none;
  padding: 0 10px;
  border-radius: 4px;
  font-size: 0.85em;
  font-weight: bold;
}
#bar.insert #left { background: var(--insert-bg); color: var(--insert-fg); }
#bar.passthrough #left { background: var(--passthrough-bg); color: var(--passthrough-fg); }
#bar.private #left { background: var(--private-bg); color: var(--private-fg); }
#bar.insert .url, #bar.passthrough .url, #bar.private .url { color: var(--https); }
]]

-- The accent and its tints, from the theme unless opts.accent names one.
local function base()
  local accent = opts.accent or "var(--rt-completion-selected-bg, #7aa2f7)"
  return ":root {\n"
    .. "  --noice-accent: " .. accent .. ";\n"
    .. "  --noice-selected: color-mix(in srgb, var(--noice-accent) 24%, transparent);\n"
    .. "  --noice-line: color-mix(in srgb, currentColor 14%, transparent);\n"
    .. "  --noice-muted: color-mix(in srgb, currentColor 62%, transparent);\n"
    .. "}\n"
end

-- The stylesheet for the parts `opts` leaves on.
function M.css()
  local parts = { base() }
  for name, css in pairs({ cmdline = PALETTE, prompts = PROMPTS, tabs = TABS, statusbar = STATUSBAR }) do
    if opts[name] ~= false then parts[#parts + 1] = css end
  end
  table.sort(parts)
  return table.concat(parts, "\n")
end

function M.apply()
  rt.ui.css(enabled and M.css() or nil)
end

function M.toggle()
  enabled = not enabled
  M.apply()
  rt.notify(enabled and "noice: on" or "noice: off")
end

function M.setup(user_opts)
  opts = user_opts or {}
  if opts.accent ~= nil and (type(opts.accent) ~= "string" or opts.accent:find("[;{}]")) then
    rt.notify("noice: accent is a CSS color, like \"#7aa2f7\"", "error")
    opts.accent = nil
  end
  rt.command("noice", function() M.toggle() end, { desc = "Turn noice's look off or back on" })
  M.apply()
end

return M
