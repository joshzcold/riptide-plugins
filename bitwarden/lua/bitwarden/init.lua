-- The official Bitwarden CLI (bw) for the passwords plugin. The first fill
-- asks for the master password and unlocks the vault; the session key is kept
-- in memory until riptide quits or :password-lock. The password goes to bw
-- through its environment, never its command line, and never leaves this plugin.
local passwords = require("passwords")
local site = passwords.site

local M = {}

function M.new(opts)
  local cmd = opts.command or "bw"
  local session
  local backend = {}

  local function unlock(cb)
    if session then
      return cb(session)
    end
    -- With the password: unlock, keeping the session key.
    local function with(password)
      if not password or password == "" then
        return cb(nil)
      end
      site.run(rt.spawn, { cmd, "unlock", "--passwordenv", "RT_BW_PASSWORD", "--raw" },
        { env = { RT_BW_PASSWORD = password } },
        function(out)
          session = out:match("%S+")
          cb(session)
        end,
        function(err) cb(nil, err) end)
    end
    local function ask()
      rt.ui.input({ prompt = "Bitwarden master password", secret = true }, with)
    end
    -- The master password saved on the Plugins tab, from the OS keyring (riptide 0.4+).
    if rt.secret then
      rt.secret.get("master_password", function(password)
        if password then with(password) else ask() end
      end)
    else
      ask()
    end
  end

  local function search(host, cb, retried)
    unlock(function(key, err)
      if not key then
        return cb(nil, err)
      end
      site.run(rt.spawn, { cmd, "list", "items", "--search", site.search_term(host) }, { env = { BW_SESSION = key } },
        function(out)
          local ok, items = pcall(rt.json.decode, out)
          if not ok or type(items) ~= "table" then
            return cb(nil, "bw's answer wasn't a list of items")
          end
          local entries = {}
          for _, item in ipairs(items) do
            local login = type(item) == "table" and item.login
            if type(login) == "table" and login.password then
              local saved = { item.name }
              for _, uri in ipairs(login.uris or {}) do
                table.insert(saved, type(uri) == "table" and uri.uri or uri)
              end
              if site.any_matches(saved, host) then
                local label = item.name or "?"
                if login.username and login.username ~= "" then
                  label = label .. " (" .. login.username .. ")"
                end
                table.insert(entries, { label = label, saved = saved, login = { username = login.username, password = login.password } })
              end
            end
          end
          cb(entries)
        end,
        function(e)
          -- The vault locked again (bw lock, a timeout): ask once more.
          session = nil
          if retried or not (e:lower():find("lock") or e:lower():find("session")) then
            return cb(nil, e)
          end
          search(host, cb, true)
        end)
    end)
  end

  backend.find = search

  function backend.get(entry, cb)
    cb(entry.login)
  end

  function backend.forget()
    session = nil
  end

  return backend
end

-- Registers with the passwords plugin; rt.pack.add's opts set it up again.
function M.setup(opts)
  passwords.register("bitwarden", M.new(opts or {}))
end

return M
