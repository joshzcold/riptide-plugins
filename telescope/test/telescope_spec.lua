-- Run with: riptide --plugin-test telescope
local function telescope() return require("telescope") end

local function open_picker(what)
  run("telescope " .. what)
  wait_until(function()
    local p = telescope().picker()
    return p and p.ready
  end)
  wait(200)
  return telescope().picker()
end

describe("telescope", function()
  it("switches to the open tab picked by a fuzzy match", function()
    run("open " .. page("alpha.html"))
    wait_for("load_finished", { pattern = "plugin-test.localhost" })
    run("open -t " .. page("beta.html"))
    wait_for("load_finished", { pattern = "plugin-test.localhost" })

    local picker = open_picker("tabs")
    -- Out of order letters still find it: "alp" by fuzzy match on the title.
    picker.type("alp")
    wait(200)
    picker.key("Enter")
    wait_until(function() return rt.url():find("alpha") ~= nil end)
    assert.equals(nil, telescope().picker(), "the picker closed")
  end)

  it("opens a page from history in a new tab with Ctrl-t", function()
    run("open " .. page("beta.html"))
    wait_for("load_finished", { pattern = "plugin-test.localhost" })
    local before = #rt.tabs()

    local picker = open_picker("history")
    picker.type("alpha page")
    wait(400)
    picker.key("C-t")
    wait_until(function() return #rt.tabs() == before + 1 end)
    wait_until(function() return rt.url():find("alpha") ~= nil end)
  end)

  it("closes on Escape without opening anything", function()
    local url = rt.url()
    local picker = open_picker("all")
    picker.key("Escape")
    wait_until(function() return telescope().picker() == nil end)
    assert.equals(url, rt.url())
  end)
end)
