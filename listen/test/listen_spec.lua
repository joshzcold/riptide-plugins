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

-- The test config's options, with these changed.
local base, installers
local function with(changes)
  local opts = {}
  for k, v in pairs(base) do opts[k] = v end
  for k, v in pairs(changes) do opts[k] = v end
  listen().setup(opts)
end

local function item(status, id)
  for _, i in ipairs(status.items) do
    if i.id == id then return i end
  end
end

-- The setup's checks, as the page last got them.
local function checked(id, pred)
  wait_until(function()
    local status = listen().status
    local i = status and item(status, id)
    return i and not i.busy and (not pred or pred(i))
  end, 8000)
  return item(listen().status, id)
end

describe("listen", function()
  before_each(function()
    base = base or listen().options()
    installers = installers or listen().installers
    listen().installers = installers
    listen().setup(base)
    listen().status = nil
    listen().curl = plugin_test.dir .. "/test/bin/fake-curl"
    os.remove(plugin_test.dir .. "/test/bin/.pulled")
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
    with({ model = "missing" })
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

  it("shows the setup as ready when everything is there", function()
    listen().setup_shown = nil
    run("listen-library")
    wait_until(function() return listen().setup_shown ~= nil end, 8000)
    assert.equals(0, listen().setup_shown.left)
    assert.truthy(listen().status.ready)
    assert.truthy(item(listen().status, "model").ok)
    assert.falsy(item(listen().status, "ffmpeg").ok)
    assert.truthy(item(listen().status, "ffmpeg").optional)
  end)

  it("pulls a model that isn't there", function()
    with({ model = "qwen3" })
    listen().status = nil
    listen().act("check")
    local model = checked("model")
    assert.falsy(model.ok)
    assert.equals("pull", model.action.name)
    listen().status = nil
    listen().act("pull")
    checked("model", function(i) return i.ok end)
    assert.truthy(listen().status.ready)
  end)

  it("downloads a voice when none is set", function()
    with({ voice = false })
    listen().status = nil
    listen().act("check")
    local voice = checked("voice")
    assert.falsy(voice.ok)
    assert.equals("en_US-lessac-medium", voice.action.choices[1].value)
    listen().status = nil
    listen().act("voice", { choice = "en_GB-alba-medium" })
    checked("voice", function(i) return i.ok end)
    local path = listen().voices_dir() .. "/en_GB-alba-medium.onnx"
    assert.equals(path, listen().voice())
    assert.truthy(io.open(path .. ".json", "rb"))
    assert.falsy(io.open(path .. ".part", "rb"))
  end)

  it("says how to install Ollama when it doesn't answer", function()
    with({ ollama = "http://down.invalid" })
    listen().status = nil
    listen().act("check")
    local ollama = checked("ollama")
    assert.falsy(ollama.ok)
    assert.matches("down.invalid", ollama.detail)
    assert.falsy(listen().status.ready)
  end)

  it("opens the setup instead when there's no voice", function()
    with({ voice = plugin_test.dir .. "/test/voice/none.onnx" })
    run("open " .. page("article.html"))
    wait_for("load_finished", { pattern = "plugin-test.localhost" })
    keys("gA")
    wait_until(function() return rt.url():match("^riptide://listen%.plugin/") end, 8000)
    assert.matches("isn't there", checked("voice").detail)
  end)

  it("installs piper with whichever of uv and pipx is there", function()
    local bin = plugin_test.dir .. "/test/bin/"
    os.remove(bin .. ".installed")
    listen().installers = {
      { name = "uv", program = bin .. "fake-uv", args = { "tool", "install", "piper-tts" } },
      { name = "pipx", program = "no-such-pipx", args = { "install", "piper-tts" } },
    }
    with({ piper = "no-such-piper" })
    listen().status = nil
    listen().act("check")
    local piper = checked("piper")
    assert.falsy(piper.ok)
    assert.equals("Install with uv", piper.action.label)
    assert.equals("uv", piper.action.choice)
    clear_messages()
    listen().act("piper", { choice = "uv" })
    wait_until(function() return last_message() == "listen: installed piper" end, 8000)
    local f = assert(io.open(bin .. ".installed", "rb"))
    assert.equals("tool install piper-tts", f:read("a"))
    f:close()
    os.remove(bin .. ".installed")
  end)

  it("says how to install uv when neither uv nor pipx is there", function()
    listen().installers = { { name = "uv", program = "no-such-uv", args = {} } }
    with({ piper = "no-such-piper" })
    listen().status = nil
    listen().act("check")
    local piper = checked("piper")
    assert.falsy(piper.action)
    assert.equals("uv tool install piper-tts", piper.commands[#piper.commands])
  end)
end)
