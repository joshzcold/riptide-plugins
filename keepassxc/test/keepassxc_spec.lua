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
end)
