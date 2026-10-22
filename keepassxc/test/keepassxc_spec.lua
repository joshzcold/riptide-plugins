-- Run with: riptide --plugin-test keepassxc

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
describe("keepassxc", function()
  it("reads the database with its password", function()
    open_login()
    run("password-fill")
    wait(300)
    keys("dbpass<Return>")
    wait_field("pass", "pw-carl")
    assert.equals("carl", field("user"))
  end)
  it("health finds its tool, or says how to get it", function()
    local function health()
      local lines, report = {}, {}
      for _, level in ipairs({ "ok", "warn", "error" }) do
        report[level] = function(text) table.insert(lines, level .. " " .. text) end
      end
      require("keepassxc").health(report)
      return lines
    end
    assert.matches("^ok .*fake%-keepassxc%-cli found", health()[1])
    require("keepassxc").setup({ command = "/nonexistent/fake-keepassxc-cli", database = "~/x.kdbx" })
    assert.matches("^error /nonexistent/.* isn't installed or isn't on your PATH", health()[1])
    -- Back to the test tool for anything after this.
    require("keepassxc").setup({ command = plugin_test.dir .. "/test/bin/fake-keepassxc-cli", database = "~/x.kdbx" })
  end)
end)
