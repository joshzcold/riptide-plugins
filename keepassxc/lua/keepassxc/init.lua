-- keepassxc-cli on a .kdbx database, for the passwords plugin. Every fill asks
-- for the database password, unless `remember` keeps it in memory for that
-- many seconds. The password goes to keepassxc-cli on its input, never its
-- command line, and never leaves this plugin.
local passwords = require("passwords")
local site = passwords.site

local M = {}

-- The home folder, for "~/" in paths; the sandbox can't read $HOME, the shell can.
local home
rt.spawn({ "sh", "-c", 'printf %s "$HOME"' }, function(r)
  if r.code == 0 and r.stdout ~= "" then home = r.stdout end
end)

local function expand(path)
  if path and home and path:sub(1, 2) == "~/" then
    return home .. path:sub(2)
  end
  return path
end

-- Lines of `text`, empty ones included, so attributes keep their places.
local function fields(text)
  local out = {}
  for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(out, (line:gsub("\r$", "")))
  end
  return out
end

function M.new(opts)
  if not opts.database then
    error("keepassxc: set opts.database to your .kdbx file in rt.pack.add")
  end
  local cmd = opts.command or "keepassxc-cli"
  local remember = tonumber(opts.remember) or 0
  local cached, cached_at
  local backend = {}

  local function argv(sub, ...)
    local out = { cmd, sub, "-q" }
    if opts.keyfile then
      table.insert(out, "-k")
      table.insert(out, expand(opts.keyfile))
    end
    table.insert(out, expand(opts.database))
    for _, a in ipairs({ ... }) do
      table.insert(out, a)
    end
    return out
  end

  local function with_password(cb)
    if cached and remember > 0 and os.time() - cached_at < remember then
      return cb(cached)
    end
    cached = nil
    local function ask()
      rt.ui.input({ prompt = "KeePassXC database password", secret = true }, function(password)
        if not password then
          return cb(nil)
        end
        if remember > 0 then
          cached, cached_at = password, os.time()
        end
        cb(password)
      end)
    end
    -- The password saved on the Plugins tab, from the OS keyring (riptide 0.4+).
    if rt.secret then
      rt.secret.get("password", function(password)
        if password then cb(password) else ask() end
      end)
    else
      ask()
    end
  end

  function backend.find(host, cb)
    with_password(function(password)
      if not password then
        return cb(nil)
      end
      local input = { stdin = password .. "\n" }
      site.run(rt.spawn, argv("search", site.search_term(host)), input, function(out)
        local paths = {}
        for _, path in ipairs(site.lines(out)) do
          if #paths < site.MAX_CANDIDATES then
            table.insert(paths, path)
          end
        end
        site.each(paths, function(path, done)
          site.run(rt.spawn, argv("show", "-s", "-a", "Title", "-a", "UserName", "-a", "Password", "-a", "URL", path), input,
            function(shown)
              local f = fields(shown)
              local title, username, pass, url = f[1], f[2], f[3], f[4]
              if not pass or pass == "" or not site.any_matches({ url, title }, host) then
                return done(nil)
              end
              local label = path
              if username ~= "" then
                label = label .. " (" .. username .. ")"
              end
              done({ label = label, saved = { url, title }, login = { username = username ~= "" and username or nil, password = pass } })
            end,
            function() done(nil) end)
        end, function(entries) cb(entries) end)
      end, function(err)
        -- Most likely a wrong password; don't keep it.
        cached = nil
        cb(nil, err)
      end)
    end)
  end

  function backend.get(entry, cb)
    cb(entry.login)
  end

  function backend.forget()
    cached = nil
  end

  return backend
end

-- Registers with the passwords plugin; rt.pack.add's opts set it up again.
function M.setup(opts)
  passwords.register("keepassxc", M.new(opts or {}))
end

return M
