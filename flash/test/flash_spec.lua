-- Run with: riptide --plugin-test flash
-- The spec's keys() don't reach floats, so it types through M.typing, as
-- the float's keys do.
local function flash() return require("flash") end

local function js(code)
  local value, done
  rt.page.eval(code, function(v) value, done = v, true end)
  wait_until(function() return done end)
  return value
end

local function open_text()
  run("open " .. page("text.html"))
  wait_for("load_finished", { pattern = "plugin-test.localhost" })
end

describe("flash", function()
  it("labels each place two characters show and starts caret mode at the one picked", function()
    open_text()
    run("flash")
    flash().typing("be")
    wait(600)
    assert.equals("a,s", js("Array.from(document.querySelectorAll('[aria-hidden] span')).map(s => s.textContent).join(',')"))
    -- Labels go top to bottom: "s" is the second beta.
    flash().typing("s")
    wait_until(function() return rt.mode() == "caret" end)
    assert.equals("second", js("getSelection().focusNode.parentElement.id"))
    assert.equals(6, js("getSelection().focusOffset"))
    assert.equals(0, js("document.querySelectorAll('[aria-hidden] span').length"), "the labels are gone")
    run("mode-leave")
  end)

  it("follows the link at the only match without asking for a label", function()
    open_text()
    run("flash follow")
    flash().typing("go")
    wait_until(function() return rt.url():find("target") ~= nil end)
  end)

  it("jumps into text inside an iframe, and starts caret mode there", function()
    run("open " .. page("framed.html"))
    wait_for("load_finished", { pattern = "plugin-test.localhost" })
    local inner = "document.querySelector('iframe').contentDocument"
    wait_until(function() return js(inner .. "?.getElementById('deep') ? 'yes' : 'no'") == "yes" end)
    run("flash")
    flash().typing("qu")
    wait_until(function() return rt.mode() == "caret" end)
    assert.equals("deep", js(inner .. ".getSelection().focusNode.parentElement.id"))
    assert.equals(0, js(inner .. ".getSelection().focusOffset"))
    run("mode-leave")
  end)

  it("says so when the characters aren't on screen", function()
    open_text()
    clear_messages()
    run("flash")
    flash().typing("zq")
    wait_until(function() return last_message() == "flash: zq isn't on screen" end)
  end)
end)
