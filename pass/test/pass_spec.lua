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
describe("pass", function()
  it("offers the site's entries and fills the one picked", function()
    open_login()
    run("password-fill")
    -- Two entries belong here; the lookalike sites' don't. The picker's keys
    -- follow the entries' order.
    wait(500)
    keys("1")
    wait_field("pass", "pw-alice")
    assert.equals("alice@example.com", field("user"))

    -- The username alone, from the path after the site.
    run("password-fill-username")
    wait(500)
    keys("2")
    wait_field("user", "bob")
    assert.equals("pw-alice", field("pass"), "only the username changed")
  end)
end)
