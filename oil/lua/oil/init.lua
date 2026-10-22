-- Edit lists as text in nvim, like oil.nvim: the window's tabs, bookmarks
-- or quickmarks, one per line. Each :w applies what changed.
local firenvim = require("firenvim")

local M = {}

local HEADER = {
  tabs = "# Tabs: delete a line to close it, move lines to reorder, add a URL to open it. :w applies.",
  bookmarks = "# Bookmarks, one per line: URL, then the title. :w applies.",
  quickmarks = "# Quickmarks, one per line: name, then URL. :w applies.",
}

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The lines that aren't blank or comments.
local function entries(text)
  local out = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    line = trim(line)
    if line ~= "" and line:sub(1, 1) ~= "#" then table.insert(out, line) end
  end
  return out
end

-- Tabs ---------------------------------------------------------------------

-- Each tab gets an id for as long as the list is open, so lines can be
-- moved and the tab still found. `ids[n]` is the tab now at index n.
local function tabs_text(ids)
  local lines = { HEADER.tabs }
  for i, tab in ipairs(rt.tabs()) do
    table.insert(lines, ("/%d %s  %s"):format(ids[i], tab.url, tab.title))
  end
  return table.concat(lines, "\n")
end

-- Apply the edited tab list to the tabs `state.ids` named.
local function apply_tabs(state, text)
  local tabs = rt.tabs()
  if #tabs ~= #state.ids then
    return nil, "the tabs changed since the list was made; :q and open it again"
  end
  local index_of = {}
  for i, id in ipairs(state.ids) do index_of[id] = i end

  local wanted, seen, opened = {}, {}, {}
  for n, line in ipairs(entries(text)) do
    local id, url = line:match("^/(%d+)%s+(%S+)")
    if id then
      id = tonumber(id)
      if not index_of[id] then return nil, ("line %d: there's no tab /%d"):format(n, id) end
      if seen[id] then return nil, ("line %d: tab /%d is listed twice"):format(n, id) end
      if url == tabs[index_of[id]].url then
        seen[id] = true
        table.insert(wanted, { id = id })
      else
        -- Another URL: that tab closes, and the new one opens.
        table.insert(opened, url)
      end
    else
      table.insert(opened, line:match("^(%S+)"))
    end
  end

  local order = {}
  -- Close the tabs whose lines are gone, from the end so indexes hold.
  for i = #state.ids, 1, -1 do
    local id = state.ids[i]
    if not seen[id] then rt.close_tab(i) end
  end
  for _, id in ipairs(state.ids) do
    if seen[id] then table.insert(order, id) end
  end
  -- Then move each tab into its line's place.
  for place, entry in ipairs(wanted) do
    local at
    for i, id in ipairs(order) do
      if id == entry.id then at = i end
    end
    if at ~= place then
      rt.move_tab(at, place)
      table.insert(order, place, table.remove(order, at))
    end
  end
  -- New lines, and changed URLs, open in the background.
  for _, url in ipairs(opened) do rt.open(url, "tab-bg") end
  return #wanted .. " kept, " .. (#tabs - #wanted) .. " closed, " .. #opened .. " opened"
end

-- Bookmarks and quickmarks -------------------------------------------------

local function marks_text(kind, list)
  local lines = { HEADER[kind] }
  for _, mark in ipairs(list) do
    if kind == "bookmarks" then
      table.insert(lines, mark.title ~= "" and (mark.url .. "  " .. mark.title) or mark.url)
    else
      table.insert(lines, mark.name .. "  " .. mark.url)
    end
  end
  return table.concat(lines, "\n")
end

local function parse_marks(kind, text)
  local list = {}
  for n, line in ipairs(entries(text)) do
    local first, rest = line:match("^(%S+)%s*(.*)$")
    if kind == "bookmarks" then
      table.insert(list, { url = first, title = rest })
    else
      if rest == "" or rest:find("%s") then
        return nil, ("line %d: a quickmark is a name, then one URL"):format(n)
      end
      table.insert(list, { name = first, url = rest })
    end
  end
  return list
end

-- The open editor -----------------------------------------------------------

local editing

local function open(kind, text, apply)
  local handle
  handle = firenvim.edit({
    text = text,
    name = "riptide-" .. kind .. ".oil",
    title = "oil · " .. kind,
    line = 2,
    on_write = function(written)
      apply(written, function(message, err)
        if err then return rt.notify("oil: " .. err, "error") end
        rt.notify("oil: " .. message)
      end, handle)
    end,
    on_close = function() editing = nil end,
  })
  if not handle then
    return rt.notify("oil: nvim is already open", "warning")
  end
  editing = { kind = kind, handle = handle }
end

function M.open(kind)
  kind = kind ~= "" and kind or "tabs"
  if kind == "tabs" then
    local state = {}
    local function number()
      state.ids = {}
      for i = 1, #rt.tabs() do state.ids[i] = i end
    end
    number()
    return open("tabs", tabs_text(state.ids), function(written, done, handle)
      local message, err = apply_tabs(state, written)
      done(message, err)
      -- The tabs as they are now, once riptide has done it, numbered again.
      if message then
        rt.defer(300, function()
          number()
          handle.set_text(tabs_text(state.ids))
        end)
      end
    end)
  end
  if kind ~= "bookmarks" and kind ~= "quickmarks" then
    return rt.notify("oil: edit tabs, bookmarks or quickmarks", "error")
  end
  local read = kind == "bookmarks" and rt.bookmarks or rt.quickmarks
  local write = kind == "bookmarks" and rt.set_bookmarks or rt.set_quickmarks
  read(function(list, err)
    if not list then return rt.notify("oil: " .. tostring(err), "error") end
    open(kind, marks_text(kind, list), function(written, done)
      local parsed, bad = parse_marks(kind, written)
      if not parsed then return done(nil, bad) end
      write(parsed, function(ok, why)
        if not ok then return done(nil, why) end
        done(#parsed .. " " .. kind .. " saved")
      end)
    end)
  end)
end

-- The open editor, for tests: whether nvim is attached, and keys for it.
function M.editing()
  local s = firenvim.session()
  if not editing or not s then return nil end
  return s
end

function M.setup()
  rt.command("oil", function(args) M.open(trim(args or "")) end, {
    desc = "Edit your tabs, bookmarks or quickmarks as text in nvim",
    complete = function() return { "tabs", "bookmarks", "quickmarks" } end,
  })
end

return M
