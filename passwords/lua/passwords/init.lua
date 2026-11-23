-- The passwords core: fills the login form on the current site from the
-- password managers that registered with it (the pass, rbw, bitwarden and
-- keepassxc plugins). It checks every login against the site itself, and
-- fills only while the tab is still on the site it looked up.
local site = require("passwords.site")

local M = { site = site }

-- Backends by name, in the order they registered.
local backends, order = {}, {}
local opts = {}
local bound = {}

-- A password manager plugin's backend: find(host, cb, progress) gives cb a
-- list of { label, saved = { addresses, names or path parts }, ... } or
-- (nil, err), and may call progress(text, n, total, asking) as it works, with
-- asking true just before it asks for a password;
-- get(entry, cb) gives cb { username, password } or (nil, why); forget(),
-- if any, drops an unlocked session. `backend` nil removes one.
function M.register(name, backend)
  if backend and not backends[name] then table.insert(order, name) end
  if not backend then
    for i, n in ipairs(order) do
      if n == name then table.remove(order, i) end
    end
  end
  backends[name] = backend
end

local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
-- The status float waits this long, so a quick lookup doesn't flash it.
local SHOW_AFTER = 250

local function bar(n, total)
  local width = 16
  local filled = total > 0 and math.floor(width * n / total + 0.5) or 0
  return string.rep("█", filled) .. string.rep("░", width - filled)
end

-- The status float of the lookup in progress; its last lines are kept in
-- M.status for the tests.
local status

local function status_lines(s)
  local lines = { { { s.title, "title" } } }
  for _, row in ipairs(s.rows) do
    local line = { { row.name, "accent" }, { "  " } }
    if row.error then
      line[1] = { "✗ " .. row.name, "error" }
      table.insert(line, { row.error, "error" })
    elseif row.found then
      line[1] = { "✓ " .. row.name, "accent" }
      table.insert(line, { row.found == 1 and "1 login" or (row.found .. " logins"), "muted" })
    else
      line[1] = { SPINNER[s.frame % #SPINNER + 1] .. " " .. row.name, "accent" }
      if row.total then
        table.insert(line, { bar(row.n or 0, row.total), "accent" })
        table.insert(line, { string.format("  %s %d of %d", row.text, row.n or 0, row.total), "muted" })
      else
        table.insert(line, { (row.text or "starting") .. "…", "muted" })
      end
    end
    table.insert(lines, line)
  end
  if s.footer then table.insert(lines, s.footer) end
  return lines
end

-- Whether a float shown now would take the keyboard from a question: riptide
-- leaves a newly shown float with the keyboard while it asks something.
local function asking(s)
  local mode = rt.mode()
  if mode == "prompt" or mode == "yesno" then return true end
  for _, row in ipairs(s.rows) do
    if row.asking then return true end
  end
  return false
end

local function draw(s, timeout)
  if status ~= s then return end
  local lines = status_lines(s)
  M.status = lines
  if s.float then
    if s.float:is_open() then s.float:update({ lines = lines, timeout = timeout }) end
  elseif (s.shown or timeout) and not asking(s) then
    s.float = rt.ui.float({ title = "passwords", lines = lines, position = "top-right", width = 64, timeout = timeout })
  end
end

-- A status float for a lookup of `names` on `host`, with a row each.
local function start_status(host, names)
  if status then M.end_status() end
  local s = { title = "Logins for " .. host, rows = {}, by_name = {}, frame = 0 }
  for _, name in ipairs(names) do
    local row = { name = name }
    table.insert(s.rows, row)
    s.by_name[name] = row
  end
  status = s
  local ticks = 0
  s.ticker = rt.every(100, function()
    ticks = ticks + 1
    s.frame = s.frame + 1
    if not s.shown and ticks * 100 >= SHOW_AFTER then s.shown = true end
    draw(s)
  end)
  draw(s)
  return s
end

-- Ends the status float: closes it, or leaves `footer` up for a moment.
function M.end_status(footer, highlight)
  local s = status
  if not s then
    -- After the picker, the lookup's float is gone: say what happened in a new one.
    if footer then
      M.status = { { { footer, highlight or "info" } } }
      rt.ui.float({ title = "passwords", lines = M.status, position = "top-right", width = 64,
        timeout = highlight == "error" and 8000 or 3000 })
    end
    return
  end
  if s.ticker then s.ticker:stop() end
  if footer then
    s.footer = { { footer, highlight or "info" } }
    s.shown = true
    draw(s, highlight == "error" and 8000 or 3000)
  else
    M.status = status_lines(s)
    if s.float and s.float:is_open() then s.float:close() end
  end
  status = nil
end

-- Asks `name` for the logins saved for `host`, keeping its status row up to date.
local function ask_backend(s, name, host, done)
  local row = s.by_name[name]
  local answered = false
  backends[name].find(host, function(entries, err)
    if answered then return end
    answered = true
    if err then
      row.error = err
    elseif entries then
      row.found = #entries
    else
      row.error = "cancelled"
    end
    draw(s)
    done({ name = name, entries = entries, err = err })
  end, function(text, n, total, asks)
    if answered then return end
    row.text, row.n, row.total, row.asking = text, n, total, asks == true
    -- A float still being shown when the question opens would take its keyboard.
    if row.asking and s.float then
      s.float:close()
      s.float = nil
    end
    draw(s)
  end)
end

-- Finds the logins for `host` in every backend, checked against the site:
-- `done(found, answered)`, with `found` a list of { name, entry }.
local function lookup(host, done)
  local names = { table.unpack(order) }
  local s = start_status(host, names)
  site.each(names, function(name, finished)
    ask_backend(s, name, host, finished)
  end, function(results)
    local found, answered = {}, false
    for _, result in ipairs(results) do
      if result.err then
        rt.notify("passwords: " .. result.name .. ": " .. result.err, "error")
      end
      answered = answered or result.entries ~= nil
      for _, entry in ipairs(result.entries or {}) do
        -- The backend's own check isn't trusted: a lookalike never gets here.
        if site.any_matches(entry.saved or {}, host) then
          table.insert(found, { name = result.name, entry = entry })
        end
      end
    end
    done(found, answered, s)
  end)
end

-- Fills `choice` ({ name, entry }) on `host`; `what` is "login", "username" or "password".
local function use(choice, host, what)
  backends[choice.name].get(choice.entry, function(login, why)
    if not login then
      M.end_status("✗ " .. tostring(why), "error")
      return rt.notify("passwords: " .. tostring(why), "error")
    end
    rt.page.fill_login({
      host = host,
      username = what ~= "password" and login.username or nil,
      password = what ~= "username" and login.password or nil,
      submit = what == "login" and opts.submit or false,
    })
    local filled = what == "login" and "Filled " or ("Filled the " .. what .. " of ")
    M.end_status("✓ " .. filled .. choice.entry.label)
  end)
end

-- Whether the status float is open, for the tests.
function M.status_open()
  return status ~= nil and status.float ~= nil and status.float:is_open()
end

-- The open picker page, if any.
local picker

-- Lets you pick one of `found` on a float page, filtering as you type.
local function pick(found, host, what)
  if picker then picker.page:close() end
  local p = { found = found }
  picker = p
  local items = {}
  for i, choice in ipairs(found) do
    items[i] = { id = i, manager = choice.name, label = choice.entry.label }
  end
  p.page = rt.ui.page({
    path = "picker.html",
    where = "float",
    position = "center",
    title = "Login for " .. host,
    width = 640,
    height = math.min(360, 100 + #items * 21),
    keys = "all",
    on_message = function(name, data, page)
      if picker ~= p then return end
      if name == "ready" then
        p.ready = true
        page:send("items", { host = host, what = what, items = items })
      elseif name == "choose" then
        picker = nil
        page:close()
        local choice = found[tonumber(data.id)]
        local how = ({ login = true, username = true, password = true })[data.what] and data.what or what
        if choice then use(choice, host, how) end
      elseif name == "close" then
        picker = nil
        page:close()
        M.end_status()
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

-- Find the logins for the current site in every backend, let the user pick
-- one, and fill it. `what` is "login", "username" or "password"; `always_pick`
-- opens the picker even for a single login.
local function fill(what, always_pick)
  local host = site.host(rt.url())
  if not host then
    return rt.notify("passwords: this page has no site to fill a login for", "error")
  end
  if #order == 0 then
    return rt.notify("passwords: no password manager plugin is on; add pass, rbw, bitwarden or keepassxc", "error")
  end
  lookup(host, function(found, answered)
    if #found == 0 then
      -- Nothing answered: every question was cancelled, or each one failed.
      if answered then
        M.end_status("No login saved for " .. host, "warning")
        rt.notify("passwords: no login saved for " .. host, "warning")
      else
        M.end_status()
      end
      return
    end
    if #found == 1 and not always_pick then
      return use(found[1], host, what)
    end
    M.end_status()
    pick(found, host, what)
  end)
end

function M.health(report)
  if #order == 0 then
    report.warn("No password manager is set up: add pass, rbw, bitwarden or keepassxc too")
  else
    report.ok("Fills from " .. table.concat(order, ", "))
  end
end

-- Commands and keys; again with other opts replaces the keys.
function M.setup(user_opts)
  opts = user_opts or {}
  rt.command("password-fill", function() fill("login") end,
    "Fill the username and password saved for this site")
  rt.command("password-fill-username", function() fill("username") end,
    "Fill only the username saved for this site")
  rt.command("password-fill-password", function() fill("password") end,
    "Fill only the password saved for this site")
  rt.command("password-search", function() fill("login", true) end,
    "Search this site's logins and pick one to fill")
  rt.command("password-lock", function()
    local locked = {}
    for _, name in ipairs(order) do
      if backends[name].forget then
        backends[name].forget()
        table.insert(locked, name)
      end
    end
    if #locked > 0 then
      rt.notify("passwords: locked " .. table.concat(locked, ", ") .. "; the next fill asks for the password again")
    else
      rt.notify("passwords: no password manager here keeps a session; their own agents lock them")
    end
  end, "Forget the password managers' unlocked sessions (bitwarden, keepassxc)")

  for _, lhs in ipairs(bound) do rt.keymap.del("normal", lhs) end
  bound = {}
  local keys = opts.keys
  if keys == nil then
    keys = { login = "<Space>pp", username = "<Space>pu", password = "<Space>pw", search = "<Space>ps" }
  end
  if keys then
    local desc = {
      login = "Fill this site's login",
      username = "Fill this site's username",
      password = "Fill this site's password",
      search = "Search this site's logins",
    }
    for what, lhs in pairs(keys) do
      local function run()
        if what == "search" then fill("login", true) else fill(what) end
      end
      rt.keymap.set("normal", lhs, run, { desc = desc[what] })
      table.insert(bound, lhs)
    end
  end
end

return M
