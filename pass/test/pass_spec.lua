-- Run with: riptide --plugin-test pass

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
-- The passwords picker, once its logins have arrived.
local function open_picker()
  local passwords = require("passwords")
  wait_until(function()
    local p = passwords.picker()
    return p and p.ready
  end)
  wait(200)
  return passwords.picker()
end

describe("pass", function()
  it("offers the site's entries and fills the one picked", function()
    open_login()
    run("password-fill")
    -- Two entries belong here; the lookalike sites' don't.
    local picker = open_picker()
    picker.type("alice")
    wait(200)
    picker.key("Enter")
    wait_field("pass", "pw-alice")
    assert.equals("alice@example.com", field("user"))

    -- The username alone, from the path after the site.
    run("password-fill-username")
    picker = open_picker()
    picker.type("bob")
    wait(200)
    picker.key("Enter")
    wait_field("user", "bob")
    assert.equals("pw-alice", field("pass"), "only the username changed")
  end)
  it("health finds its tool, or says how to get it", function()
    local function health()
      local lines, report = {}, {}
      for _, level in ipairs({ "ok", "warn", "error" }) do
        report[level] = function(text) table.insert(lines, level .. " " .. text) end
      end
      require("pass").health(report)
      return lines
    end
    assert.matches("^ok .*fake%-pass found", health()[1])
    require("pass").setup({ command = "/nonexistent/fake-pass", store = plugin_test.dir .. "/test/store" })
    assert.matches("^error /nonexistent/.* isn't installed or isn't on your PATH", health()[1])
    -- Back to the test tool for anything after this.
    require("pass").setup({ command = plugin_test.dir .. "/test/bin/fake-pass", store = plugin_test.dir .. "/test/store" })
  end)
end)
