-- Run with: riptide --plugin-test listen
local function listen() return require("listen") end

local function make_clip()
  run("open " .. page("article.html"))
  wait_for("load_finished", { pattern = "plugin-test.localhost" })
  local before = #listen().clips()
  keys("gA")
  local ok = pcall(wait_until, function() return #listen().clips() > before end, 8000)
  if not ok then error("no clip: " .. table.concat(messages(), " / ")) end
  return listen().clips()[1]
end

describe("listen", function()
  before_each(function()
    listen().curl = plugin_test.dir .. "/test/bin/fake-curl"
    for _, clip in ipairs(listen().clips()) do listen().delete(clip.id) end
  end)

  it("saves a spoken summary of the page's article", function()
    local clip = make_clip()
    assert.equals("Life in the tide pools", clip.title)
    assert.equals("Tide pools\nTide pools teem with life, says llama3.2.", clip.summary)
    assert.matches("%.wav$", clip.file, "no ffmpeg in the test config")
    assert.truthy(math.abs(clip.seconds - 0.5) < 0.01, tostring(clip.seconds))
    local file = io.open(listen().dir() .. "/" .. clip.file, "rb")
    assert.truthy(file)
    file:close()
    assert.equals(0, #listen().pending)
    assert.matches("^listen: ready", last_message())
  end)

  it("lists the clips and plays one", function()
    local clip = make_clip()
    listen().shown, listen().loaded = nil, nil
    run("listen-library")
    wait_until(function() return listen().shown ~= nil end, 8000)
    assert.equals(1, listen().shown.clips)
    assert.truthy(rt.url():match("^riptide://listen%.plugin/"))
    local pages = listen().pages
    pages[#pages]:send("play", { id = clip.id })
    wait_until(function() return listen().loaded ~= nil end, 8000)
    assert.falsy(listen().loaded.error)
  end)

  it("deletes a clip and its file", function()
    local clip = make_clip()
    local path = listen().dir() .. "/" .. clip.file
    listen().delete(clip.id)
    assert.equals(0, #listen().clips())
    assert.falsy(io.open(path, "rb"))
  end)

  it("says what Ollama said when it fails", function()
    listen().setup({ voice = "v.onnx", model = "missing", piper = plugin_test.dir .. "/test/bin/fake-piper", dir = listen().dir() })
    run("open " .. page("article.html"))
    wait_for("load_finished", { pattern = "plugin-test.localhost" })
    clear_messages()
    keys("gA")
    wait_until(function() return last_message() and last_message():match("not found") end, 8000)
    assert.equals('listen: Ollama: model "missing" not found, try pulling it first', last_message())
    assert.equals(0, #listen().pending)
  end)

  it("says so when a page has no article", function()
    run("open " .. page("empty.html"))
    wait_for("load_finished", { pattern = "plugin-test.localhost" })
    clear_messages()
    keys("gA")
    wait_until(function() return last_message() == "listen: no article found on this page" end)
  end)
end)
