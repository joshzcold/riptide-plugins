-- Marks a handful of pages, in order, and jumps straight to them, like
-- ThePrimeagen's harpoon: to the page's tab if it's open, or opens it.
local M = {}

local store = rt.store("harpoon")
local opts = {}
local bound = {}
local list

-- The marks, each { url, title }, in order.
function M.marks()
  return store.get("marks") or {}
end

local function save(marks)
  store.set("marks", marks)
end

-- A page and its URL with another fragment are the same page.
local function same(a, b)
  return (a or ""):gsub("#.*$", "") == (b or ""):gsub("#.*$", "")
end

function M.add()
  local url, title = rt.url(), rt.title()
  if not url:match("^%a[%w+.-]*://") or url:match("^riptide://") then
    return rt.notify("harpoon: this page can't be marked", "warning")
  end
  local marks = M.marks()
  for i, mark in ipairs(marks) do
    if same(mark.url, url) then
      return rt.notify("harpoon: already mark " .. i)
    end
  end
  table.insert(marks, { url = url, title = title })
  save(marks)
  rt.notify("harpoon: marked " .. #marks .. ": " .. (title ~= "" and title or url))
end

-- Jump to mark `n`: its tab if one is open in this window, or open it here.
function M.go(n)
  local mark = M.marks()[n]
  if not mark then
    return rt.notify("harpoon: no mark " .. n, "warning")
  end
  -- rt.select_tab is newer than riptide 0.7.
  if rt.select_tab then
    for _, tab in ipairs(rt.tabs()) do
      if same(tab.url, mark.url) then
        if not tab.current then rt.select_tab(tab.index) end
        return
      end
    end
  end
  if not same(rt.url(), mark.url) then rt.open(mark.url, "current") end
end

function M.remove(n)
  local marks = M.marks()
  if not marks[n] then return end
  table.remove(marks, n)
  save(marks)
end

-- Move mark `n` by `by` places.
function M.move(n, by)
  local marks = M.marks()
  local to = n + by
  if not marks[n] or not marks[to] then return n end
  marks[n], marks[to] = marks[to], marks[n]
  save(marks)
  return to
end

-- The list: j/k move, Enter or a number jumps, d removes, J/K reorder.
local function lines(selected)
  local marks = M.marks()
  if #marks == 0 then
    return { { { "No marks yet: <Space>a marks this page", "muted" } } }
  end
  local out = {}
  for i, mark in ipairs(marks) do
    local title = mark.title ~= "" and mark.title or mark.url
    out[i] = {
      { (i == selected and "> " or "  ") .. i .. "  ", i == selected and "accent" or "muted" },
      { title, i == selected and "accent" or "title" },
      { "  " .. mark.url, "url" },
    }
  end
  table.insert(out, "")
  table.insert(out, { { "Enter/1-9 go · j/k move · J/K reorder · d remove · Esc close", "muted" } })
  return out
end

function M.show()
  if list and list.float:is_open() then list.float:close() end
  local state = { selected = 1 }
  list = state
  local function redraw(float)
    local count = #M.marks()
    state.selected = math.max(1, math.min(state.selected, count))
    float:update({ lines = lines(state.selected) })
  end
  local function go(float, n)
    float:close()
    M.go(n)
  end
  local keys = {
    j = function(f) state.selected = state.selected + 1 redraw(f) end,
    k = function(f) state.selected = state.selected - 1 redraw(f) end,
    ["<Down>"] = function(f) state.selected = state.selected + 1 redraw(f) end,
    ["<Up>"] = function(f) state.selected = state.selected - 1 redraw(f) end,
    ["<Enter>"] = function(f) go(f, state.selected) end,
    J = function(f) state.selected = M.move(state.selected, 1) redraw(f) end,
    K = function(f) state.selected = M.move(state.selected, -1) redraw(f) end,
    d = function(f) M.remove(state.selected) redraw(f) end,
    q = function(f) f:close() end,
  }
  for n = 1, 9 do
    keys[tostring(n)] = function(f) go(f, n) end
  end
  state.float = rt.ui.float({
    title = "Harpoon",
    lines = lines(state.selected),
    width = 90,
    keys = keys,
  })
end

function M.setup(user_opts)
  opts = user_opts or {}
  rt.command("harpoon", function() M.show() end, "Show the marked pages")
  rt.command("harpoon-add", function() M.add() end, "Mark this page")
  rt.command("harpoon-go", function(args)
    local n = tonumber(args)
    if n then M.go(math.floor(n)) else rt.notify("harpoon: :harpoon-go takes a mark's number", "error") end
  end, "Jump to a marked page by its number")
  rt.command("harpoon-clear", function()
    save({})
    rt.notify("harpoon: cleared the marks")
  end, "Forget every mark")

  for _, lhs in ipairs(bound) do rt.keymap.del("normal", lhs) end
  bound = {}
  if opts.keys == false then return end
  local function bind(lhs, fn, desc)
    rt.keymap.set("normal", lhs, fn, { desc = desc })
    table.insert(bound, lhs)
  end
  bind("<Space>a", M.add, "Harpoon: mark this page")
  bind("<Space>h", M.show, "Harpoon: the marked pages")
  local slots = math.max(0, math.min(9, math.floor(tonumber(opts.slots) or 4)))
  for n = 1, slots do
    bind("<Space>" .. n, function() M.go(n) end, "Harpoon: jump to mark " .. n)
  end
end

return M
