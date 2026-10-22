-- Run with: riptide --plugin-test harpoon
local function harpoon() return require("harpoon") end

local function visit(file, target)
  run("open " .. (target or "") .. " " .. page(file))
  wait_for("load_finished", { pattern = "plugin-test.localhost" })
end

local function urls()
  local out = {}
  for _, mark in ipairs(harpoon().marks()) do table.insert(out, mark.url:match("[^/]+$")) end
  return table.concat(out, " ")
end

describe("harpoon", function()
  before_each(function()
    run("harpoon-clear")
  end)

  it("marks pages once each and jumps back to them", function()
    visit("alpha.html")
    keys("<Space>a")
    keys("<Space>a")
    wait_until(function() return last_message() == "harpoon: already mark 1" end)
    visit("beta.html")
    keys("<Space>a")
    assert.equals("alpha.html beta.html", urls())

    keys("<Space>1")
    wait_until(function() return rt.url():find("alpha") ~= nil end)
  end)

  it("switches to a marked page's open tab rather than opening it again", function()
    if not rt.select_tab then return end -- riptide 0.7 and older open it again
    visit("alpha.html")
    keys("<Space>a")
    visit("beta.html", "-t")
    local tabs = #rt.tabs()
    keys("<Space>1")
    wait_until(function() return rt.url():find("alpha") ~= nil end)
    assert.equals(tabs, #rt.tabs(), "no new tab")
  end)

  -- The spec's keys() don't reach floats, so this drives what the list's
  -- keys call; the list itself is checked by hand.
  it("reorders and removes marks", function()
    visit("alpha.html")
    keys("<Space>a")
    visit("beta.html")
    keys("<Space>a")
    harpoon().move(1, 1)
    assert.equals("beta.html alpha.html", urls())
    assert.equals(2, harpoon().move(2, 1), "the last one stays last")
    harpoon().remove(1)
    assert.equals("alpha.html", urls())
  end)
end)
