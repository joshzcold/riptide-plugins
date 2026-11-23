-- Run with: riptide --plugin-test passwords
-- Fake password managers register here directly; test/login.html is the
-- site, at http://plugin-test.localhost/.
-- The plugin loads after this file, so it's looked up when a test runs.
local function passwords() return require("passwords") end

-- A value from the page, through the page's own JavaScript.
local function js(code)
  local value, done
  rt.page.eval(code, function(v)
    value, done = v, true
  end)
  wait_until(function() return done end)
  return value
end

local function field(id)
  return js("document.getElementById('" .. id .. "').value")
end

local function wait_field(id, expected)
  wait_until(function() return field(id) == expected end)
end

local function open_login()
  run("open " .. page("login.html"))
  wait_for("load_finished", { pattern = "plugin-test.localhost" })
end
-- The open picker, once its logins have arrived.
local function open_picker()
  wait_until(function()
    local p = passwords().picker()
    return p and p.ready
  end)
  wait(200)
  return passwords().picker()
end

-- The status float's text, one line each.
local function status()
  local text = {}
  for _, line in ipairs(passwords().status or {}) do
    for _, chunk in ipairs(line) do table.insert(text, chunk[1]) end
    table.insert(text, "\n")
  end
  return table.concat(text)
end

local function login(label, saved, username, password)
  return { label = label, saved = saved, login = { username = username, password = password } }
end

-- A password manager that knows `entries`, answering after `delay` ms.
local function fake(entries, delay)
  return {
    find = function(_, cb, progress)
      if delay then
        progress("reading entries", 1, 2)
        rt.defer(delay, function() cb(entries) end)
      else
        cb(entries)
      end
    end,
    get = function(entry, cb) cb(entry.login) end,
  }
end

describe("passwords", function()
  before_each(function()
    passwords().register("one", nil)
    passwords().register("two", nil)
    clear_messages()
    open_login()
  end)

  it("never offers a login saved for a lookalike site", function()
    passwords().register("one", fake({
      login("evil", { "https://plugin-test.localhost.evil.net/" }, "eve", "pw-eve"),
      login("not", { "notplugin-test.localhost" }, "nat", "pw-nat"),
      login("here", { "http://plugin-test.localhost/" }, "ann", "pw-ann"),
    }))
    run("password-fill")
    -- Only one login is left, so it fills without asking.
    wait_field("pass", "pw-ann")
    assert.equals("ann", field("user"))
    assert.equals("", field("search"), "the search box outside the form is left alone")
  end)

  it("offers the logins of every password manager", function()
    passwords().register("one", fake({ login("a", { "plugin-test.localhost" }, "a", "pw-a") }))
    passwords().register("two", fake({ login("b", { "plugin-test.localhost" }, "b", "pw-b") }))
    run("password-fill-password")
    local picker = open_picker()
    picker.type("two")
    wait(200)
    picker.key("Enter")
    wait_field("pass", "pw-b")
    assert.equals("", field("user"), "only the password")
    assert.equals(nil, passwords().picker(), "the picker closed")
  end)

  it("searches the site's logins with :password-search, even for one", function()
    passwords().register("one", fake({ login("here", { "plugin-test.localhost" }, "ann", "pw-ann") }))
    run("password-search")
    local picker = open_picker()
    picker.key("A-u")
    wait_field("user", "ann")
    assert.equals("", field("pass"), "only the username")
    wait_until(function() return status():find("✓ Filled the username of here", 1, true) end)
  end)

  it("fills nothing when the picker is closed", function()
    passwords().register("one", fake({ login("a", { "plugin-test.localhost" }, "a", "pw-a") }))
    passwords().register("two", fake({ login("b", { "plugin-test.localhost" }, "b", "pw-b") }))
    run("password-fill")
    open_picker().key("Escape")
    wait_until(function() return passwords().picker() == nil end)
    wait(300)
    assert.equals("", field("pass"))
  end)

  it("shows each password manager's progress while it looks", function()
    passwords().register("one", fake({ login("here", { "plugin-test.localhost" }, "ann", "pw-ann") }, 1500))
    passwords().register("two", fake({}))
    run("password-fill")
    wait_until(function() return status():find("reading entries 1 of 2", 1, true) end)
    local during = status()
    assert.matches("Logins for plugin%-test%.localhost\n", during)
    assert.truthy(during:find(string.rep("█", 8) .. string.rep("░", 8), 1, true), during)
    assert.truthy(during:find("✓ two  0 logins", 1, true), during)
    wait_field("pass", "pw-ann")
    wait_until(function() return status():find("✓ Filled here", 1, true) end)
  end)

  it("shows no status float while a password manager asks for its password", function()
    -- A float shown during a question takes riptide's keyboard from it.
    local typed
    passwords().register("one", {
      find = function(_, cb, progress)
        progress("waiting for your master password", nil, nil, true)
        rt.ui.input({ prompt = "Master password", secret = true }, function(text)
          typed = text
          progress("unlocking the vault")
          rt.defer(800, function() cb({ login("here", { "plugin-test.localhost" }, "ann", "pw-ann") }) end)
        end)
      end,
      get = function(entry, cb) cb(entry.login) end,
    })
    passwords().register("two", fake({}, 3000))
    run("password-fill")
    wait(800)
    assert.falsy(passwords().status_open(), "no float during the question")
    keys("hunter2<Return>")
    wait_until(function() return typed ~= nil end)
    assert.equals("hunter2", typed)
    wait_until(function() return passwords().status_open() end)
    wait_field("pass", "pw-ann")
  end)

  it("says when no login is saved for the site", function()
    passwords().register("one", fake({}))
    run("password-fill")
    wait_until(function() return last_message() == "passwords: no login saved for plugin-test.localhost" end)
  end)

  it("fills nothing once the tab has moved to another site", function()
    passwords().register("one", fake({ login("here", { "plugin-test.localhost" }, "ann", "pw-ann") }, 1500))
    run("password-fill")
    -- While the password manager answers, the tab goes to another site with
    -- a login form; the login isn't filled there.
    run("open data:text/html,<form><input id=user><input id=pass type=password></form>")
    wait(2500)
    assert.equals("", field("pass"))
  end)
  it("health names the password managers it fills from", function()
    local lines, report = {}, {}
    for _, level in ipairs({ "ok", "warn", "error" }) do
      report[level] = function(text) table.insert(lines, level .. " " .. text) end
    end
    passwords().register("one", fake({}))
    passwords().health(report)
    passwords().register("one", nil)
    passwords().health(report)
    assert.equals("ok Fills from one", lines[1])
    assert.matches("^warn No password manager is set up", lines[2])
  end)
end)
