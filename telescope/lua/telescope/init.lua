-- A fuzzy finder over open tabs, history, bookmarks and quickmarks, like
-- telescope.nvim: a float page lists them, filters as you type, and opens
-- the one you pick.
local M = {}

local SOURCES = { "tabs", "quickmarks", "bookmarks", "history" }
local TITLES = {
  all = "Find",
  tabs = "Tabs",
  history = "History",
  bookmarks = "Bookmarks",
  quickmarks = "Quickmarks",
}

local opts = {}
local bound = {}
local picker

-- The items of `source`, each { kind, title, url, ... }, to `done(items)`.
local function gather(source, done)
  if source == "tabs" then
    local items = {}
    for _, tab in ipairs(rt.tabs()) do
      if not tab.current then
        table.insert(items, { kind = "tab", index = tab.index, title = tab.title, url = tab.url })
      end
    end
    return done(items)
  end
  local function listed(list, err)
    if not list then
      rt.notify("telescope: " .. tostring(err), "error")
      return done({})
    end
    local items = {}
    for _, entry in ipairs(list) do
      if source == "quickmarks" then
        table.insert(items, { kind = "quickmark", title = entry.name, url = entry.url })
      elseif source == "bookmarks" then
        table.insert(items, { kind = "bookmark", title = entry.title, url = entry.url })
      else
        table.insert(items, { kind = "history", title = entry.title, url = entry.url, when = entry.last_visit })
      end
    end
    done(items)
  end
  if source == "history" then
    rt.history("", listed)
  elseif source == "bookmarks" then
    rt.bookmarks(listed)
  else
    rt.quickmarks(listed)
  end
end

-- Every source of `what` ("all" or one), in SOURCES order, to `done(items)`.
local function gather_all(what, done)
  local wanted = what == "all" and SOURCES or { what }
  local results, left = {}, #wanted
  for i, source in ipairs(wanted) do
    gather(source, function(items)
      results[i] = items
      left = left - 1
      if left == 0 then
        local all = {}
        for j = 1, #wanted do
          for _, item in ipairs(results[j]) do table.insert(all, item) end
        end
        done(all)
      end
    end)
  end
end

local function choose(item, where)
  if item.kind == "tab" and where == "current" then
    rt.select_tab(item.index)
  else
    rt.open(item.url, where)
  end
end

-- Open the picker over `what`: "all", or one of SOURCES.
function M.open(what)
  what = what ~= "" and what or "all"
  if not TITLES[what] then
    return rt.notify("telescope: pick from all, tabs, history, bookmarks or quickmarks", "error")
  end
  if picker then picker.page:close() end
  local p = { what = what }
  picker = p
  p.page = rt.ui.page({
    path = "index.html",
    where = "float",
    position = "center",
    title = TITLES[what],
    width = 820,
    height = 460,
    keys = "all",
    on_message = function(name, data, page)
      if picker ~= p then return end
      if name == "ready" then
        gather_all(what, function(items)
          p.ready = true
          page:send("items", { items = items, history = what == "all" or what == "history" })
        end)
      elseif name == "search" then
        -- Older history than the recent entries listed first.
        rt.history(data.query or "", function(list)
          local items = {}
          for _, entry in ipairs(list or {}) do
            table.insert(items, { kind = "history", title = entry.title, url = entry.url, when = entry.last_visit })
          end
          page:send("history", { query = data.query, items = items })
        end)
      elseif name == "choose" then
        picker = nil
        page:close()
        choose(data.item, data.where or "current")
      elseif name == "close" then
        picker = nil
        page:close()
      end
    end,
  })
end

-- The open picker, for tests: whether its items have arrived, and keys for it.
function M.picker()
  if not picker then return nil end
  local p = picker
  return {
    ready = p.ready == true,
    type = function(text) p.page:send("type", { text = text }) end,
    key = function(key) p.page:send("key", { key = key }) end,
  }
end

function M.setup(user_opts)
  opts = user_opts or {}
  rt.command("telescope", function(args) M.open((args or ""):match("^%s*(%S*)")) end, {
    desc = "Fuzzy-find tabs, history, bookmarks and quickmarks",
    complete = function() return { "all", "tabs", "history", "bookmarks", "quickmarks" } end,
  })

  for _, lhs in ipairs(bound) do rt.keymap.del("normal", lhs) end
  bound = {}
  if opts.keys ~= false then
    local keys = {
      ["<Space>ff"] = { "all", "Find tabs, history, bookmarks and quickmarks" },
      ["<Space>ft"] = { "tabs", "Find an open tab" },
      ["<Space>fh"] = { "history", "Find in history" },
      ["<Space>fb"] = { "bookmarks", "Find a bookmark" },
      ["<Space>fq"] = { "quickmarks", "Find a quickmark" },
    }
    for lhs, what in pairs(keys) do
      rt.keymap.set("normal", lhs, function() M.open(what[1]) end, { desc = what[2] })
      table.insert(bound, lhs)
    end
  end
end

return M
