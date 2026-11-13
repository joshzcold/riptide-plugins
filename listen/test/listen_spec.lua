-- Run with: riptide --plugin-test listen
local function listen() return require("listen") end

-- A clip of the test article: gA, or :listen with mode.
local function make_clip(mode)
  run("open " .. page("article.html"))
  wait_for("load_finished", { pattern = "plugin-test.localhost" })
  local before = #listen().clips()
  if mode then run("listen " .. mode) else keys("gA") end
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

  it("reads the article aloud, paragraph by paragraph", function()
    local clip = make_clip()
    assert.equals("article", clip.mode)
    assert.equals("Life in the tide pools", clip.title)
    assert.falsy(clip.summary)
    assert.matches("%.wav$", clip.file, "no ffmpeg in the test config")
    local text = listen().text(clip)
    assert.equals("Life in the tide pools", text[1].text)
    assert.truthy(text[1].heading)
    assert.matches("^Tide pools are small worlds", text[2].text)
    assert.matches("^When the water comes back", text[#text].text)
    -- The title, then the four paragraphs; the byline, ad and nav are left out.
    assert.equals(5, #text)
    -- Each part is half a second, with 0.4 s between paragraphs.
    for i, p in ipairs(text) do
      assert.truthy(math.abs(p.start - (i - 1) * 0.9) < 0.01, i .. ": " .. tostring(p.start))
    end
    assert.truthy(math.abs(clip.seconds - (#text * 0.9 - 0.4)) < 0.01, tostring(clip.seconds))
    local file = io.open(listen().dir() .. "/" .. clip.file, "rb")
    assert.truthy(file)
    file:close()
    assert.falsy(io.open(listen().dir() .. "/" .. clip.id .. ".parts", "rb"))
    assert.equals(0, #listen().pending)
    assert.matches("^listen: ready", last_message())
  end)

  it("reads a summary with :listen summary", function()
    local clip = make_clip("summary")
    assert.equals("summary", clip.mode)
    assert.equals("Tide pools\nTide pools teem with life, says llama3.2.", clip.summary)
    local text = listen().text(clip)
    assert.equals(2, #text)
    assert.equals("Tide pools Tide pools teem with life, says llama3.2.", text[2].text)
  end)

  it("drops an LLM's preamble and keeps its paragraphs", function()
    assert.equals("Agents learn.", listen().clean("Here's a summary of the article in a short script: Agents learn."))
    local paragraphs = listen().paragraphs("One.\nStill one.\n\nTwo.\n\n\n")
    assert.equals(2, #paragraphs)
    assert.equals("One. Still one.", paragraphs[1].text)
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
    assert.equals(#listen().text(clip), listen().loaded.timed)
  end)

  it("deletes a clip and its file", function()
    local clip = make_clip()
    local path = listen().dir() .. "/" .. clip.file
    listen().delete(clip.id)
    assert.equals(0, #listen().clips())
    assert.falsy(io.open(path, "rb"))
  end)

  it("says what Ollama said when it fails", function()
    with({ read = "summary", model = "missing" })
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
    -- From the catalog, by language: Great Britain's English, then the US's, then German.
    local keys = {}
    for _, c in ipairs(voice.action.choices) do table.insert(keys, c.value) end
    assert.same({ "en_GB-alba-medium", "en_US-amy-medium", "en_US-libritts_r-medium", "de_DE-thorsten-high" }, keys)
    assert.equals("English (United States)", voice.action.group)
    assert.equals("Download and use (63 MB)", voice.action.choices[1].button)
    assert.matches("904 speakers", voice.action.choices[3].label)
    listen().status = nil
    listen().act("voice", { choice = "en_GB-alba-medium" })
    voice = checked("voice", function(i) return i.ok end)
    local path = listen().voices_dir() .. "/en_GB-alba-medium.onnx"
    assert.equals(path, listen().voice())
    assert.truthy(io.open(path .. ".json", "rb"))
    assert.falsy(io.open(path .. ".part", "rb"))
    assert.equals("en_GB-alba-medium", voice.action.selected)
    assert.truthy(voice.action.keep)
  end)

  it("switches voices, at once to one already downloaded", function()
    with({ voice = false })
    local dir = listen().voices_dir()
    listen().status = nil
    listen().act("voice", { choice = "en_US-amy-medium" })
    local voice = checked("voice", function(i) return i.action.selected == "en_US-amy-medium" end)
    assert.equals(dir .. "/en_US-amy-medium.onnx", listen().voice())
    for _, c in ipairs(voice.action.choices) do
      if c.value == "en_US-amy-medium" then assert.equals("Use", c.button) end
    end

    -- Alba was downloaded by the test before; picking it needs no download.
    listen().act("voice", { choice = "en_GB-alba-medium" })
    assert.equals(dir .. "/en_GB-alba-medium.onnx", listen().voice())
    assert.equals("listen: reading with Alba, English (Great Britain), medium from now on", last_message())
  end)

  it("downloads a voice from another language", function()
    with({ voice = false })
    listen().status = nil
    listen().act("voice", { choice = "de_DE-thorsten-high" })
    local voice = checked("voice", function(i) return i.action.selected == "de_DE-thorsten-high" end)
    assert.equals("German (Germany)", voice.action.group)
    local f = assert(io.open(listen().voices_dir() .. "/de_DE-thorsten-high.onnx", "rb"))
    assert.equals("fake de_DE-thorsten-high.onnx", f:read("a"))
    f:close()
  end)

  it("offers a few voices when the catalog can't be fetched", function()
    with({ voice = false })
    local base_url = listen().VOICE_BASE
    listen().forget_catalog()
    listen().VOICE_BASE = "https://down.invalid/"
    listen().status = nil
    listen().act("check")
    local voice = checked("voice")
    listen().VOICE_BASE = base_url
    assert.equals(#listen().VOICES, #voice.action.choices)
    assert.matches("^couldn't fetch the list of voices", voice.error)
    listen().forget_catalog()
  end)

  it("leaves the voice to the config when its option is set", function()
    listen().status = nil
    listen().act("check")
    local voice = checked("voice")
    assert.truthy(voice.ok)
    assert.falsy(voice.action)
    assert.matches("voice option in your config", voice.detail)
  end)

  it("says how to install Ollama when it doesn't answer", function()
    with({ ollama = "http://down.invalid", read = "summary" })
    listen().status = nil
    listen().act("check")
    local ollama = checked("ollama")
    assert.falsy(ollama.ok)
    assert.matches("down.invalid", ollama.detail)
    assert.falsy(listen().status.ready)

    -- Reading articles doesn't need Ollama.
    with({ ollama = "http://down.invalid" })
    listen().status = nil
    listen().act("check")
    ollama = checked("ollama")
    assert.truthy(ollama.optional)
    assert.matches("^only for summaries", ollama.detail)
    assert.truthy(listen().status.ready)
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

  it("tells distros apart by /etc/os-release", function()
    local cases = {
      { 'ID=ubuntu\nID_LIKE=debian\n', "debian" },
      { 'ID=linuxmint\nID_LIKE="ubuntu debian"\n', "debian" },
      { 'ID=fedora\n', "fedora" },
      { 'ID="rocky"\nID_LIKE="rhel centos fedora"\n', "linux" },
      { 'ID=manjaro\nID_LIKE=arch\n', "arch" },
      { 'ID="opensuse-tumbleweed"\nID_LIKE="opensuse suse"\n', "suse" },
      { 'ID=nixos\n', "linux" },
    }
    for _, case in ipairs(cases) do
      assert.equals(case[2], listen().system(case[1]), case[1])
    end
  end)

  it("leaves out install commands it doesn't know", function()
    local install = listen().install_command
    assert.equals("sudo dnf install ffmpeg-free", install("ffmpeg", "fedora"))
    assert.falsy(install("ffmpeg", "suse"))
    assert.falsy(install("ffmpeg", "linux"))
    assert.equals("brew install ffmpeg", install("ffmpeg", "macos", true))
    assert.falsy(install("ffmpeg", "macos", false))
    assert.falsy(install("ollama", "macos", false))
    assert.matches("astral.sh/uv/install.sh", install("uv", "macos", false))
    assert.falsy(install("curl", "windows"))
  end)
end)
