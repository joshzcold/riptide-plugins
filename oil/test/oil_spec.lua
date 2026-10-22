-- Run with: riptide --plugin-test oil
-- Needs nvim on PATH, and the firenvim plugin beside this one.
local function oil() return require("oil") end

local function visit(file, target)
  run("open " .. (target or "") .. " " .. page(file))
  wait_for("load_finished", { pattern = "plugin-test.localhost" })
end

local function editing()
  wait_until(function()
    local s = oil().editing()
    return s and s.attached
  end, 15000)
  return oil().editing()
end

-- After a :w, oil says what it did, then shows the list again.
local function applied()
  wait_until(function() return (last_message() or ""):find("^oil:") ~= nil end, 15000)
  wait(800)
end

local function titles()
  local out = {}
  for _, tab in ipairs(rt.tabs()) do table.insert(out, (tab.title:gsub(" page$", ""))) end
  return table.concat(out, " ")
end

describe("oil", function()
  it("closes, reorders and opens tabs from the edited list", function()
    visit("alpha.html")
    visit("beta.html", "-t")
    visit("gamma.html", "-t")
    wait_until(function() return titles() == "alpha beta gamma" end)

    run("oil tabs")
    local nvim = editing()
    -- Line 1 is the header: drop beta, then move gamma above alpha.
    clear_messages()
    nvim.input(":g/beta/d<CR>:3m1<CR>:w<CR>")
    applied()
    assert.equals("gamma alpha", titles())

    -- A new line opens its URL in a tab.
    clear_messages()
    nvim.input("Go" .. page("beta.html") .. "<Esc>:w<CR>")
    applied()
    wait_until(function() return #rt.tabs() == 3 end)
    nvim.input(":q!<CR>")
    wait_until(function() return oil().editing() == nil end)
  end)

  it("renames a bookmark", function()
    visit("alpha.html")
    run("bookmark-add")
    run("oil bookmarks")
    local nvim = editing()
    clear_messages()
    nvim.input(":%s/alpha\\.html.*/alpha.html  renamed/<CR>:w<CR>")
    applied()
    local title
    wait_until(function()
      rt.bookmarks(function(list)
        for _, mark in ipairs(list or {}) do
          if mark.url:find("alpha") then title = mark.title end
        end
      end)
      return title == "renamed"
    end)
    nvim.input(":q<CR>")
    wait_until(function() return oil().editing() == nil end)
  end)
end)
