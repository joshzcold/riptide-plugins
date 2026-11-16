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

local bin = plugin_test.dir .. "/test/bin/"

-- The arguments listen last ran Kokoro's script with.
local function ran()
  local f = assert(io.open(bin .. ".ran", "rb"))
  local args = f:read("a")
  f:close()
  return args
end

-- The test config's options, with these changed.
local base
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
    listen().setup(base)
    listen().status = nil
    listen().curl = bin .. "fake-curl"
    os.remove(bin .. ".pulled")
    listen().uv = bin .. "fake-uv"
    if not listen().ready() then
      local installed
      listen().install(function(err) installed = err or true end)
      wait_until(function() return installed ~= nil end, 8000)
      assert.equals(true, installed)
    end
    assert.falsy(listen().use_voice("af_heart"))
    for _, clip in ipairs(listen().clips()) do listen().delete(clip.id) end
  end)

  it("reads the article aloud, paragraph by paragraph", function()
    local clip = make_clip()
    assert.equals("article", clip.mode)
    assert.equals("Life in the tide pools", clip.title)
    assert.falsy(clip.summary)
    assert.matches("%.wav$", clip.file, "no ffmpeg in the test config")
    assert.matches("%-%-voice af_heart %-%-output_dir ", ran())
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

  it("shows its progress in a float while it reads", function()
    local function shown()
      local text = {}
      for _, line in ipairs(listen().progress or {}) do
        for _, chunk in ipairs(line) do table.insert(text, chunk[1]) end
        table.insert(text, "\n")
      end
      return table.concat(text)
    end
    io.open(bin .. ".slow", "w"):close()
    run("open " .. page("article.html"))
    wait_for("load_finished", { pattern = "plugin-test.localhost" })
    listen().progress = nil
    keys("gA")
    local ok = pcall(wait_until, function() return shown():match("2 of 5 paragraphs") end, 8000)
    os.remove(bin .. ".slow")
    local during, job = shown(), listen().pending[1]
    wait_until(function() return #listen().clips() == 1 end, 8000)
    assert.truthy(ok, during)
    assert.equals("Life in the tide pools\n" .. string.rep("█", 10) .. string.rep("░", 14) .. "  2 of 5 paragraphs\n", during)
    assert.equals(5, job.total)
    assert.equals("Life in the tide pools\nReady · 0:04 · :listen-library\n", shown())
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
    assert.truthy(item(listen().status, "kokoro").ok)
    assert.equals("Heart, English (American), female", item(listen().status, "voice").detail)
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

  it("installs Kokoro from the setup and lists its voices", function()
    for _, name in ipairs(listen().KOKORO_FILES) do os.remove(listen().kokoro_dir() .. "/" .. name) end
    assert.falsy(listen().ready())
    listen().status = nil
    listen().act("check")
    local kokoro = checked("kokoro")
    assert.falsy(kokoro.ok)
    assert.equals("kokoro", kokoro.action.name)
    assert.falsy(item(listen().status, "voice"))
    assert.falsy(listen().status.ready)

    listen().status = nil
    listen().act("kokoro")
    checked("kokoro", function(i) return i.ok end)
    for _, name in ipairs({ "kokoro-v1.0.onnx", "voices-v1.0.bin", "kokoro.py" }) do
      assert.truthy(io.open(listen().kokoro_dir() .. "/" .. name, "rb"), name)
    end
    local voice = checked("voice")
    assert.equals("voice", voice.action.name)
    assert.equals("af_heart", voice.action.selected)
    assert.equals("English (American)", voice.action.group)
    assert.equals("English (British)", voice.action.choices[3].group)
    assert.equals("Emma · female", voice.action.choices[3].label)
    assert.truthy(voice.action.keep)
  end)

  it("switches the voice", function()
    clear_messages()
    listen().act("voice", { choice = "bf_emma" })
    assert.equals("bf_emma", listen().voice())
    assert.equals("listen: reading with Emma, English (British), female from now on", last_message())
    make_clip()
    assert.matches("%-%-voice bf_emma", ran())
    assert.truthy(listen().use_voice("zz_nobody"))
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

  it("opens the setup, which says how to install uv, when Kokoro can't run", function()
    listen().uv = "no-such-uv"
    run("open " .. page("article.html"))
    wait_for("load_finished", { pattern = "plugin-test.localhost" })
    keys("gA")
    wait_until(function() return rt.url():match("^riptide://listen%.plugin/") end, 8000)
    local kokoro = checked("kokoro")
    assert.falsy(kokoro.ok)
    assert.falsy(kokoro.action)
    assert.matches("needs uv", kokoro.detail)
    assert.equals(0, #listen().clips())
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
