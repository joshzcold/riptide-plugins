-- Run with: riptide --plugin-test bitwarden

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
local function clear(id)
  js("(() => { document.getElementById('" .. id .. "').value = ''; return 1; })()")
end

describe("bitwarden", function()
  it("asks for the master password once, until locked", function()
    open_login()
    run("password-fill")
    wait(300)
    keys("correct<Return>")
    wait_field("pass", "pw-bea")
    -- The session is kept: no question the second time.
    clear("pass")
    run("password-fill-password")
    wait_field("pass", "pw-bea")
    -- :password-lock forgets it. A wrong password unlocks nothing, so the
    -- next fill asks again.
    run("password-lock")
    clear("pass")
    run("password-fill")
    wait(300)
    keys("wrong<Return>")
    wait(1000)
    assert.equals("", field("pass"))
    run("password-fill")
    wait(300)
    keys("correct<Return>")
    wait_field("pass", "pw-bea")
  end)
  it("health finds its tool, or says how to get it", function()
    local function health()
      local lines, report = {}, {}
      for _, level in ipairs({ "ok", "warn", "error" }) do
        report[level] = function(text) table.insert(lines, level .. " " .. text) end
      end
      require("bitwarden").health(report)
      return lines
    end
    assert.matches("^ok .*fake%-bw found", health()[1])
    require("bitwarden").setup({ command = "/nonexistent/fake-bw" })
    assert.matches("^error /nonexistent/.* isn't installed or isn't on your PATH", health()[1])
    -- Back to the test tool for anything after this.
    require("bitwarden").setup({ command = plugin_test.dir .. "/test/bin/fake-bw" })
  end)
end)
