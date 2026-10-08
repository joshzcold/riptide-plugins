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
local function login(label, saved, username, password)
  return { label = label, saved = saved, login = { username = username, password = password } }
end

-- A password manager that knows `entries`, answering after `delay` ms.
local function fake(entries, delay)
  return {
    find = function(_, cb)
      if delay then
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
    wait(300)
    keys("2")
    wait_field("pass", "pw-b")
    assert.equals("", field("user"), "only the password")
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
end)
