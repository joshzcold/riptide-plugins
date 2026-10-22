-- Run with: riptide --plugin-test reader
local function reader() return require("reader") end

describe("reader", function()
  it("shows the article's text in a tab of its own, without scripts, styles or images", function()
    run("open " .. page("article.html"))
    wait_for("load_finished", { pattern = "plugin-test.localhost" })
    reader().shown = nil
    run("reader")
    wait_until(function() return reader().shown ~= nil end, 8000)
    local shown = reader().shown
    assert.equals("Life in the tide pools", shown.title)
    assert.equals(4, shown.paragraphs)
    assert.equals(1, shown.images, "the image is a placeholder")
    assert.equals(1, shown.links, "the field guide link, not the menu")
    assert.equals(0, shown.unsafe)
    assert.truthy(rt.url():match("^riptide://reader%.plugin/"))
  end)

  it("says so when a page has no article", function()
    run("open " .. page("empty.html"))
    wait_for("load_finished", { pattern = "plugin-test.localhost" })
    clear_messages()
    run("reader")
    wait_until(function() return last_message() == "reader: no article found on this page" end)
  end)
end)
