-- Run with: riptide --plugin-test firenvim
-- Needs nvim on PATH; test/bin/nvim-clean runs it without your config.
local function firenvim() return require("firenvim") end

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

local function open_notes()
  run("open " .. page("textarea.html"))
  wait_for("load_finished", { pattern = "plugin-test.localhost" })
end

local function attached()
  wait_until(function()
    local s = firenvim().session()
    return s and s.attached
  end, 6000)
  return firenvim().session()
end

describe("firenvim", function()
  it("edits the focused text area in nvim and puts it back on :w", function()
    open_notes()
    js("document.getElementById('notes').focus()")
    run("firenvim")
    local nvim = attached()
    assert.equals("first line\nsecond", field("notes"), "nothing changes before :w")

    nvim.input("GA!<Esc>:w<CR>")
    wait_until(function() return field("notes") == "first line\nsecond!" end)

    nvim.input(":q<CR>")
    wait_until(function() return firenvim().session() == nil end)
    assert.equals("notes", js("document.activeElement.id"), "the field has the focus again")
  end)

  it("puts the text back when :wq writes and quits at once", function()
    open_notes()
    js("document.getElementById('notes').focus()")
    run("firenvim")
    attached().input("ggcconly line<Esc>:wq<CR>")
    wait_until(function() return firenvim().session() == nil end)
    assert.equals("only line\nsecond", field("notes"))
  end)

  it("puts nothing back when nvim quits without writing", function()
    open_notes()
    js("document.getElementById('title').focus()")
    run("firenvim")
    attached().input("ccchanged<Esc>:q!<CR>")
    wait_until(function() return firenvim().session() == nil end)
    assert.equals("a title", field("title"))
  end)

  it("opens by itself on a text area with auto, but not on an input", function()
    firenvim().setup({ auto = "textarea", command = plugin_test.dir .. "/test/bin/nvim-clean" })
    -- Focus from the page's script then enters insert mode, as a click does.
    rt.set("input.insert_mode.auto_load", true)
    open_notes()
    js("document.getElementById('title').focus()")
    wait(1000)
    assert.equals(nil, firenvim().session(), "an input isn't a text area")

    -- Leaving the input leaves insert mode, so the text area enters it again.
    js("document.activeElement.blur()")
    wait(300)
    js("document.getElementById('notes').focus()")
    attached().input(":q<CR>")
    wait_until(function() return firenvim().session() == nil end)
    -- Focus is back on the text area, which doesn't open it again.
    wait(1000)
    assert.equals(nil, firenvim().session())
    firenvim().setup({ command = plugin_test.dir .. "/test/bin/nvim-clean" })
  end)

  it("leaves a field or a site alone once told to, from the float's ignore button", function()
    firenvim().setup({ auto = "textarea", command = plugin_test.dir .. "/test/bin/nvim-clean" })
    rt.set("input.insert_mode.auto_load", true)
    local function focus_notes()
      open_notes()
      js("document.getElementById('notes').focus()")
    end
    run("open " .. page("textarea.html"))
    wait_for("load_finished", { pattern = "plugin-test.localhost" })
    run("firenvim-forget")

    -- Its close button, then 1: never on this field. The next visit doesn't open.
    focus_notes()
    attached().dismiss()
    wait(300)
    keys("1")
    focus_notes()
    wait(1500)
    assert.equals(nil, firenvim().session(), "left alone")

    -- Forgotten, it opens again; 3: just this time, so it opens next time too.
    run("firenvim-forget")
    focus_notes()
    attached().dismiss()
    wait(300)
    keys("3")
    focus_notes()
    attached().input(":q<CR>")
    wait_until(function() return firenvim().session() == nil end)

    -- 2: never on this site.
    focus_notes()
    attached().dismiss()
    wait(300)
    keys("2")
    focus_notes()
    wait(1500)
    assert.equals(nil, firenvim().session(), "the site is left alone")

    run("firenvim-forget")
    firenvim().setup({ command = plugin_test.dir .. "/test/bin/nvim-clean" })
  end)

  it("opens a field in the filetype last set for it on the site", function()
    open_notes()
    run("firenvim-forget")
    js("document.getElementById('notes').focus()")
    run("firenvim")
    attached().input(":set ft=markdown<CR>:q<CR>")
    wait_until(function() return firenvim().session() == nil end)

    -- Another page of the site, the same field: nvim says its filetype.
    open_notes()
    js("document.getElementById('notes').focus()")
    run("firenvim")
    attached().input(":call setline(1, &ft)<CR>:wq<CR>")
    wait_until(function() return firenvim().session() == nil end)
    assert.equals("markdown\nsecond", field("notes"))
    run("firenvim-forget")
  end)

  it("edits a field inside an iframe", function()
    -- Older riptides run rt.page.eval in the main frame only, and say no frame.
    local frame, done
    rt.page.eval("1", function(_, _, id) frame, done = id, true end, { frame = "focused" })
    wait_until(function() return done end)
    if not frame then return end

    run("open " .. page("framed.html"))
    wait_for("load_finished", { pattern = "plugin-test.localhost" })
    local inner = "document.querySelector('iframe').contentDocument.getElementById('notes')"
    wait_until(function() return js(inner .. "?.value") == "in the frame" end)
    js(inner .. ".focus()")
    run("firenvim")
    attached().input("A, edited<Esc>:wq<CR>")
    wait_until(function() return firenvim().session() == nil end)
    assert.equals("in the frame, edited", js(inner .. ".value"))
  end)

  it("says so when no text field has the focus", function()
    open_notes()
    clear_messages()
    run("firenvim")
    wait_until(function() return last_message() == "firenvim: focus a text field first" end)
  end)
end)
