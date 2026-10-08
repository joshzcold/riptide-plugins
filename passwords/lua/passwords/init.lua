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

-- A password manager plugin's backend: find(host, cb) gives cb a list of
-- { label, saved = { addresses, names or path parts }, ... } or (nil, err);
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

-- Find the logins for the current site in every backend, let the user pick
-- one, and fill it. `what` is "login", "username" or "password".
local function fill(what)
  local host = site.host(rt.url())
  if not host then
    return rt.notify("passwords: this page has no site to fill a login for", "error")
  end
  if #order == 0 then
    return rt.notify("passwords: no password manager plugin is on; add pass, rbw, bitwarden or keepassxc", "error")
  end
  local names = { table.unpack(order) }
  site.each(names, function(name, done)
    backends[name].find(host, function(entries, err)
      done({ name = name, entries = entries, err = err })
    end)
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
    if #found == 0 then
      -- Nothing answered: every question was cancelled, or each one failed.
      if answered then rt.notify("passwords: no login saved for " .. host, "warning") end
      return
    end
    local several = #names > 1
    local function use(choice)
      backends[choice.name].get(choice.entry, function(login, why)
        if not login then
          return rt.notify("passwords: " .. tostring(why), "error")
        end
        rt.page.fill_login({
          host = host,
          username = what ~= "password" and login.username or nil,
          password = what ~= "username" and login.password or nil,
          submit = what == "login" and opts.submit or false,
        })
      end)
    end
    if #found == 1 then
      return use(found[1])
    end
    rt.ui.select(found, {
      prompt = "Login for " .. host,
      format = function(choice)
        return several and (choice.name .. ": " .. choice.entry.label) or choice.entry.label
      end,
    }, function(choice)
      if choice then use(choice) end
    end)
  end)
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
    keys = { login = "<Space>pp", username = "<Space>pu", password = "<Space>pw" }
  end
  if keys then
    local desc = { login = "Fill this site's login", username = "Fill this site's username", password = "Fill this site's password" }
    for what, lhs in pairs(keys) do
      rt.keymap.set("normal", lhs, function() fill(what) end, { desc = desc[what] })
      table.insert(bound, lhs)
    end
  end
end

return M
