-- Run with: riptide --plugin-test rbw

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
describe("rbw", function()
  it("skips entries for lookalike sites, and submits", function()
    open_login()
    run("password-fill")
    -- One login belongs here, so there's nothing to pick.
    wait_until(function() return js("window.__submitted") == "ann/pw-ann" end)
  end)
  it("health finds its tool, or says how to get it", function()
    local function health()
      local lines, report = {}, {}
      for _, level in ipairs({ "ok", "warn", "error" }) do
        report[level] = function(text) table.insert(lines, level .. " " .. text) end
      end
      require("rbw").health(report)
      return lines
    end
    assert.matches("^ok .*fake%-rbw found", health()[1])
    require("rbw").setup({ command = "/nonexistent/fake-rbw" })
    assert.matches("^error /nonexistent/.* isn't installed or isn't on your PATH", health()[1])
    -- Back to the test tool for anything after this.
    require("rbw").setup({ command = plugin_test.dir .. "/test/bin/fake-rbw" })
  end)
end)
