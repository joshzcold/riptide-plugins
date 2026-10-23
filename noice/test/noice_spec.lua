-- Run with: riptide --plugin-test noice
local function noice() return require("noice") end

describe("noice", function()
  it("styles every part by default, in the theme's colors", function()
    noice().setup({})
    local css = noice().css()
    for _, part in ipairs({ "body.palette:not(.floating)", "body.floating", "#tabs", "#bar" }) do
      assert.truthy(css:find(part, 1, true), part)
    end
    assert.truthy(css:find("--rt-completion-selected-bg", 1, true))
  end)

  it("leaves out the parts turned off, and takes an accent", function()
    noice().setup({ tabs = false, statusbar = false, accent = "#bb9af7" })
    local css = noice().css()
    assert.truthy(css:find("body.palette:not(.floating)", 1, true))
    assert.falsy(css:find("#tabs", 1, true))
    assert.falsy(css:find("#bar", 1, true))
    assert.truthy(css:find("--noice-accent: #bb9af7;", 1, true))
  end)

  it("refuses an accent that isn't a color", function()
    clear_messages()
    noice().setup({ accent = "red; } body { display: none" })
    assert.falsy(noice().css():find("display: none", 1, true))
    wait_until(function() return (last_message() or ""):find("accent is a CSS color", 1, true) ~= nil end)
  end)

  it(":noice turns the look off and on", function()
    noice().setup({})
    clear_messages()
    run("noice")
    wait_until(function() return last_message() == "noice: off" end)
    run("noice")
    wait_until(function() return last_message() == "noice: on" end)
  end)
end)
