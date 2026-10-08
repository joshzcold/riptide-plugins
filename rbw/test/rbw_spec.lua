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
end)
