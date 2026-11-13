-- A spoken summary of the page you're on: Readability finds the article, a
-- local LLM in Ollama writes a summary meant to be heard, and Piper reads it
-- into a clip. :listen-library lists the clips and plays them.
local readability = require("reader.readability")

local M = {}

-- The programs it runs; the tests swap in fakes.
M.curl = "curl"

-- Clips being made, newest last: { id, title, url, stage }.
M.pending = {}

local opts = {}
local bound = {}
local store = rt.store()
local libraries = {}

local MAX_CHARS = 20000

-- In the page: the article's title and text, or null if there's none.
local EXTRACT_JS = "(() => {\n" .. readability .. [[

  const article = new Readability(document.cloneNode(true)).parse();
  if (!article || !article.textContent || (article.length ?? 0) < 200) return null;
  return {
    title: article.title || document.title,
    site: article.siteName || location.hostname,
    text: article.textContent.replace(/\s+/g, " ").trim().slice(0, ]] .. MAX_CHARS .. [[),
    url: location.href,
  };
})()]]

local PROMPT = [[Summarize this article as a short script to be read aloud, about %d words.
Write plain spoken sentences: no headings, lists, markdown, links or emoji.
Start with what it's about, not with "This article".

Title: %s

%s]]

local function notify(text, level) rt.notify("listen: " .. text, level) end

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

function M.dir()
  if opts.dir and opts.dir ~= "" then return opts.dir end
  local home = os.getenv("HOME") or "."
  if rt.platform == "macos" then return home .. "/Library/Application Support/riptide/listen" end
  if rt.platform == "windows" then return (os.getenv("LOCALAPPDATA") or home) .. "/riptide/listen" end
  return (os.getenv("XDG_DATA_HOME") or (home .. "/.local/share")) .. "/riptide/listen"
end

function M.clips() return store.get("clips") or {} end

local function find(id)
  for i, clip in ipairs(M.clips()) do
    if clip.id == id then return clip, i end
  end
end

local function refresh()
  local payload = { clips = M.clips(), pending = M.pending }
  for _, page in ipairs(libraries) do pcall(page.send, page, "clips", payload) end
end

-- A program's path: the option if it's set, else on PATH, else in
-- ~/.local/bin, where uv and pipx put piper even when that isn't on riptide's PATH.
local function program(name)
  local given = opts[name]
  if given and given ~= "" then return rt.which(given) end
  local found = rt.which(name)
  if found then return found end
  local home = os.getenv("HOME")
  local local_bin = home and (home .. "/.local/bin/" .. name)
  local f = local_bin and io.open(local_bin, "rb")
  if f then
    f:close()
    return local_bin
  end
end

local function exists(path)
  local f = path and path ~= "" and io.open(path, "rb")
  if f then f:close() end
  return f and true or false
end

-- Voices the setup can download, from rhasspy/piper-voices.
M.VOICE_BASE = "https://huggingface.co/rhasspy/piper-voices/resolve/main/"
M.VOICES = {
  { name = "en_US-lessac-medium", path = "en/en_US/lessac/medium", label = "Lessac, US English" },
  { name = "en_US-amy-medium", path = "en/en_US/amy/medium", label = "Amy, US English" },
  { name = "en_US-ryan-high", path = "en/en_US/ryan/high", label = "Ryan, US English, clearer but slower" },
  { name = "en_GB-alba-medium", path = "en/en_GB/alba/medium", label = "Alba, British English" },
}

function M.options() return opts end

function M.voices_dir() return M.dir() .. "/voices" end

-- The voice to read with: the voice option, else the one the setup downloaded.
function M.voice()
  if opts.voice and opts.voice ~= "" then return opts.voice end
  local saved = store.get("voice")
  if exists(saved) then return saved end
end

local function model() return opts.model or "llama3.2" end

local function endpoint() return (opts.ollama or "http://localhost:11434"):gsub("/+$", "") end

-- The LLM's answer as plain sentences for Piper: no reasoning, no markdown.
function M.clean(text)
  text = (text or ""):gsub("<think>.-</think>", ""):gsub("[*_#`]", "")
  return trim(text)
end

function M.summarize(article, callback)
  local body = rt.json.encode({
    model = model(),
    prompt = PROMPT:format(tonumber(opts.words) or 150, article.title or "", article.text),
    stream = false,
    -- Ollama's default context would cut a long article short without saying so.
    options = { num_ctx = 8192 },
  })
  local base = endpoint()
  local argv = {
    M.curl, "-sS", "--fail-with-body", "--max-time", "600",
    "-H", "Content-Type: application/json", "--data-binary", "@-", base .. "/api/generate",
  }
  rt.spawn(argv, { stdin = body }, function(r)
    if r.error then return callback(nil, "couldn't run curl: " .. r.error) end
    local ok, answer = pcall(rt.json.decode, r.stdout or "")
    if ok and type(answer) == "table" and answer.error then
      return callback(nil, "Ollama: " .. tostring(answer.error))
    end
    if r.code ~= 0 or not ok or type(answer) ~= "table" then
      return callback(nil, "no answer from Ollama at " .. base .. " (:listen-library helps set it up): "
        .. trim(r.stderr ~= "" and r.stderr or r.stdout))
    end
    local text = M.clean(answer.response)
    if text == "" then return callback(nil, "Ollama's summary was empty") end
    callback(text)
  end)
end

-- Seconds of audio in a WAV file, from its header.
local function wav_seconds(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local header = f:read(44)
  local size = f:seek("end")
  f:close()
  if not header or #header < 44 or header:sub(1, 4) ~= "RIFF" then return nil end
  local rate = string.unpack("<I4", header, 29)
  if rate == 0 then return nil end
  return (size - 44) / rate
end

function M.speak(text, id, callback)
  local dir = M.dir()
  local wav = dir .. "/" .. id .. ".wav"
  rt.spawn({ "mkdir", "-p", dir }, function(made)
    if made.code ~= 0 then return callback(nil, nil, "couldn't make " .. dir .. ": " .. trim(made.stderr)) end
    rt.spawn({ program("piper") or "piper", "--model", M.voice(), "--output_file", wav }, { stdin = text }, function(r)
      local seconds = wav_seconds(wav)
      if r.error or r.code ~= 0 or not seconds then
        return callback(nil, nil, "piper failed: " .. trim(r.error or r.stderr))
      end
      local ffmpeg = program("ffmpeg")
      if not ffmpeg then return callback(id .. ".wav", seconds) end
      local ogg = dir .. "/" .. id .. ".ogg"
      local argv = { ffmpeg, "-y", "-loglevel", "error", "-i", wav, "-c:a", "libopus", "-b:a", "32k", ogg }
      rt.spawn(argv, function(c)
        if c.code ~= 0 then return callback(id .. ".wav", seconds) end
        os.remove(wav)
        callback(id .. ".ogg", seconds)
      end)
    end)
  end)
end

local function done(job)
  for i, j in ipairs(M.pending) do
    if j == job then table.remove(M.pending, i) end
  end
end

function M.make()
  if not program("piper") or not exists(M.voice()) then
    notify("piper and a voice aren't set up yet; see the setup on this page", "error")
    return M.library()
  end
  local url = rt.url()
  if not url:match("^https?://") and not url:match("^file://") then
    return notify("this page has no article to summarize", "warning")
  end
  rt.page.eval(EXTRACT_JS, function(article, err)
    if err then return notify(err, "error") end
    if not article then return notify("no article found on this page", "warning") end
    local id = os.date("%Y%m%d-%H%M%S") .. string.format("-%04d", math.random(0, 9999))
    local job = { id = id, title = article.title, url = article.url, stage = "summarizing" }
    table.insert(M.pending, job)
    refresh()
    notify("summarizing “" .. article.title .. "”…")
    local function fail(message)
      done(job)
      refresh()
      notify(message, "error")
    end
    M.summarize(article, function(summary, serr)
      if not summary then return fail(serr) end
      job.stage = "speaking"
      refresh()
      M.speak(summary, id, function(file, seconds, perr)
        if not file then return fail(perr) end
        local clips = M.clips()
        table.insert(clips, 1, {
          id = id,
          file = file,
          title = article.title,
          site = article.site,
          url = article.url,
          summary = summary,
          created = os.time(),
          seconds = seconds,
        })
        store.set("clips", clips)
        done(job)
        refresh()
        notify("ready: “" .. article.title .. "” (:listen-library)")
      end)
    end)
  end)
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local PAIRS = {}
for i = 0, 4095 do
  PAIRS[i] = B64:sub((i >> 6) + 1, (i >> 6) + 1) .. B64:sub((i & 63) + 1, (i & 63) + 1)
end

function M.base64(s)
  local out, n = {}, #s
  local whole = n - n % 3
  for i = 1, whole, 3 do
    local a, b, c = s:byte(i, i + 2)
    local v = (a << 16) | (b << 8) | c
    out[#out + 1] = PAIRS[v >> 12] .. PAIRS[v & 4095]
  end
  local rest = n - whole
  if rest > 0 then
    local a, b = s:byte(whole + 1, n)
    local v = (a << 16) | ((b or 0) << 8)
    local quad = PAIRS[v >> 12] .. PAIRS[v & 4095]
    out[#out + 1] = quad:sub(1, rest + 1) .. (rest == 1 and "==" or "=")
  end
  return table.concat(out)
end

function M.play(id, page)
  local clip = find(id)
  local f = clip and io.open(M.dir() .. "/" .. clip.file, "rb")
  if not f then return page:send("audio", { id = id, error = "this clip's file is gone" }) end
  local data = f:read("a")
  f:close()
  local mime = clip.file:match("%.ogg$") and "audio/ogg" or "audio/wav"
  page:send("audio", { id = id, mime = mime, data = M.base64(data) })
end

function M.delete(id)
  local clip, i = find(id)
  if not clip then return end
  os.remove(M.dir() .. "/" .. clip.file)
  local clips = M.clips()
  table.remove(clips, i)
  store.set("clips", clips)
  refresh()
end

function M.library()
  local page = rt.ui.page({
    path = "index.html",
    on_message = function(name, data, page)
      if name == "ready" then
        page:send("clips", { clips = M.clips(), pending = M.pending })
        M.check(function(status) pcall(page.send, page, "status", status) end)
      elseif name == "setup" then
        M.act(data.action, data)
      elseif name == "setup_shown" then
        M.setup_shown = data
      elseif name == "play" then
        M.play(data.id, page)
      elseif name == "delete" then
        M.delete(data.id)
      elseif name == "open" and type(data.url) == "string" and data.url:match("^https?://") then
        rt.open(data.url, "tab")
      elseif name == "shown" then
        M.shown = data
      elseif name == "loaded" then
        M.loaded = data
      end
    end,
  })
  table.insert(libraries, page)
  M.pages = libraries
  return page
end

-- Setup: what's ready, how to install what isn't, and the steps the page can
-- take itself (pull the model, download a voice, install piper with uv or pipx).

-- Steps running now, and the last failure of each: { pull = true }, { pull = "…" }.
M.busy = {}
M.failed = {}

-- The system's package manager family: debian, fedora, arch, suse, macos, windows or linux.
function M.system()
  if rt.platform ~= "linux" then return rt.platform end
  local f = io.open("/etc/os-release", "rb")
  if not f then return "linux" end
  local text = "\n" .. f:read("a")
  f:close()
  local ids = (text:match('\nID="?([^"\n]+)') or "") .. " " .. (text:match('\nID_LIKE="?([^"\n]+)') or "")
  for _, family in ipairs({ "debian", "ubuntu", "fedora", "rhel", "arch", "suse" }) do
    if ids:find(family, 1, true) then
      return ({ ubuntu = "debian", rhel = "fedora" })[family] or family
    end
  end
  return "linux"
end

local INSTALL = {
  debian = "sudo apt install %s",
  fedora = "sudo dnf install %s",
  arch = "sudo pacman -S %s",
  suse = "sudo zypper install %s",
  macos = "brew install %s",
  windows = "winget install %s",
}

-- Package names where they differ from the program's.
local PACKAGES = {
  pipx = { arch = "python-pipx", suse = "python3-pipx", windows = "pipx" },
  ffmpeg = { fedora = "ffmpeg-free", windows = "Gyan.FFmpeg" },
  curl = { windows = "cURL.cURL" },
}

local function install(name)
  local system = M.system()
  local command = INSTALL[system]
  if not command then return nil end
  return command:format((PACKAGES[name] or {})[system] or name)
end

-- The commands given, without the ones there's no install command for here.
local function commands(...)
  local list = {}
  for i = 1, select("#", ...) do
    local c = select(i, ...)
    if c then table.insert(list, c) end
  end
  return list
end

-- The tools that can install piper-tts, by name; the tests swap in fakes.
M.installers = {
  { name = "uv", program = "uv", args = { "tool", "install", "piper-tts" } },
  { name = "pipx", program = "pipx", args = { "install", "piper-tts" } },
}

local function uv_install()
  local system = M.system()
  if system == "macos" then return "brew install uv" end
  if system == "windows" then return "winget install astral-sh.uv" end
  if system == "arch" then return "sudo pacman -S uv" end
  return "curl -LsSf https://astral.sh/uv/install.sh | sh"
end

local function ollama_install()
  local system = M.system()
  if system == "macos" then return "brew install ollama" end
  if system == "windows" then return "winget install Ollama.Ollama" end
  if system == "arch" then return "sudo pacman -S ollama" end
  return "curl -fsSL https://ollama.com/install.sh | sh"
end

local function failed(id, item)
  if M.failed[id] then item.error = M.failed[id] end
  if M.busy[id] then item.busy = true end
  return item
end

-- The checks that don't need Ollama to answer, in the order the page lists them.
function M.local_checks()
  local items = {}
  local piper = program("piper")
  if piper then
    table.insert(items, { id = "piper", name = "Piper", ok = true, detail = piper })
  else
    local item = { id = "piper", name = "Piper", ok = false, detail = "reads the summary aloud; it isn't installed" }
    local found = {}
    for _, tool in ipairs(M.installers) do
      if rt.which(tool.program) then table.insert(found, { value = tool.name, label = tool.name }) end
    end
    if #found > 1 then
      item.action = { name = "piper", label = "Install", choices = found }
    elseif #found == 1 then
      item.action = { name = "piper", label = "Install with " .. found[1].value, choice = found[1].value }
    else
      item.detail = item.detail .. ". Install uv, then piper (or: pipx install piper-tts)"
      item.commands = commands(uv_install(), "uv tool install piper-tts")
    end
    item.busy_text = "Installing piper-tts…"
    table.insert(items, failed("piper", item))
  end

  local voice = M.voice()
  if voice and exists(voice) then
    table.insert(items, { id = "voice", name = "Voice", ok = true, detail = voice })
  elseif voice then
    table.insert(items, { id = "voice", name = "Voice", ok = false,
      detail = "the voice option names " .. voice .. ", which isn't there. Fix the path in your config, or remove the option and download one here" })
  else
    local choices = {}
    for _, v in ipairs(M.VOICES) do table.insert(choices, { value = v.name, label = v.label }) end
    table.insert(items, failed("voice", { id = "voice", name = "Voice", ok = false,
      detail = "the Piper voice to read with; about 60 MB",
      action = { name = "voice", label = "Download", choices = choices },
      busy_text = "Downloading the voice…",
      link = { url = "https://rhasspy.github.io/piper-samples/", text = "Hear samples of every voice" } }))
  end

  local ffmpeg = program("ffmpeg")
  if ffmpeg then
    table.insert(items, { id = "ffmpeg", name = "ffmpeg", ok = true, optional = true, detail = "clips are saved as Opus" })
  else
    table.insert(items, { id = "ffmpeg", name = "ffmpeg", ok = false, optional = true,
      detail = "optional: clips are saved as WAV, about 10 times larger", commands = commands(install("ffmpeg")),
      link = { url = "https://ffmpeg.org/download.html", text = "ffmpeg.org/download" } })
  end
  return items
end

-- Every check, Ollama's included, handed to callback as { items, ready }.
function M.check(callback)
  local items = M.local_checks()
  local function finish(ollama)
    for i = #ollama, 1, -1 do table.insert(items, 1, ollama[i]) end
    local ready = true
    for _, item in ipairs(items) do
      if not item.ok and not item.optional then ready = false end
    end
    M.status = { items = items, ready = ready }
    callback(M.status)
  end

  local curl = rt.which(M.curl)
  if not curl then
    return finish({ { id = "ollama", name = "Ollama", ok = false,
      detail = "curl, which reaches Ollama, isn't installed", commands = commands(install("curl")) } })
  end
  local base = endpoint()
  rt.spawn({ M.curl, "-sS", "--max-time", "3", base .. "/api/tags" }, function(r)
    local ok, tags = pcall(rt.json.decode, r.stdout or "")
    if r.code ~= 0 or not ok or type(tags) ~= "table" then
      local item = { id = "ollama", name = "Ollama", ok = false }
      if rt.which("ollama") then
        item.detail = "installed, but not answering at " .. base .. ". Start it"
        item.commands = rt.platform == "linux" and { "systemctl start ollama", "ollama serve" } or { "ollama serve" }
      elseif opts.ollama and opts.ollama ~= "" then
        item.detail = "nothing answers at " .. base .. ", the ollama option"
      else
        item.detail = "writes the summaries, on your computer; it isn't installed"
        item.commands = { ollama_install() }
        item.link = { url = "https://ollama.com/download", text = "ollama.com/download" }
      end
      return finish({ item, { id = "model", name = "Model " .. model(), ok = false, detail = "needs Ollama" } })
    end
    local name = model()
    local have = false
    for _, m in ipairs(tags.models or {}) do
      if m.name == name or m.name == name .. ":latest" or m.model == name then have = true end
    end
    local item = { id = "model", name = "Model " .. name, ok = have }
    if have then
      item.detail = "pulled"
    else
      item.detail = "not pulled yet; it's a few GB"
      item.action = { name = "pull", label = "Pull " .. name }
      item.busy_text = "Pulling " .. name .. "; this takes a while…"
    end
    finish({ { id = "ollama", name = "Ollama", ok = true, detail = base }, failed("pull", item) })
  end)
end

local function broadcast()
  M.check(function(status)
    for _, page in ipairs(libraries) do pcall(page.send, page, "status", status) end
  end)
end

-- Runs a step, then checks everything again.
local function step(id, work)
  if M.busy[id] then return end
  M.busy[id] = true
  M.failed[id] = nil
  broadcast()
  work(function(err)
    M.busy[id] = nil
    M.failed[id] = err
    if err then notify(err, "error") end
    broadcast()
  end)
end

local function pull(done)
  local body = rt.json.encode({ model = model(), stream = false })
  local argv = { M.curl, "-sS", "--fail-with-body", "-H", "Content-Type: application/json",
    "--data-binary", "@-", endpoint() .. "/api/pull" }
  rt.spawn(argv, { stdin = body }, function(r)
    local ok, answer = pcall(rt.json.decode, r.stdout or "")
    if ok and type(answer) == "table" and answer.error then return done("Ollama: " .. tostring(answer.error)) end
    if r.code ~= 0 then return done("couldn't pull " .. model() .. ": " .. trim(r.stderr ~= "" and r.stderr or r.stdout)) end
    notify("pulled " .. model())
    done()
  end)
end

local function download_voice(name, done)
  local voice
  for _, v in ipairs(M.VOICES) do
    if v.name == name then voice = v end
  end
  if not voice then return done("there's no voice " .. tostring(name)) end
  local dir = M.voices_dir()
  local onnx = dir .. "/" .. voice.name .. ".onnx"
  local function fetch(path, after)
    local url = M.VOICE_BASE .. voice.path .. "/" .. voice.name .. path:match("%.onnx.*$")
    rt.spawn({ M.curl, "-fsSL", "--retry", "2", "-o", path .. ".part", url }, function(r)
      if r.code ~= 0 then
        os.remove(path .. ".part")
        return done("couldn't download " .. voice.name .. ": " .. trim(r.error or r.stderr))
      end
      os.remove(path)
      os.rename(path .. ".part", path)
      after()
    end)
  end
  rt.spawn({ "mkdir", "-p", dir }, function(made)
    if made.code ~= 0 then return done("couldn't make " .. dir .. ": " .. trim(made.stderr)) end
    fetch(onnx .. ".json", function()
      fetch(onnx, function()
        store.set("voice", onnx)
        notify("downloaded the voice " .. voice.name)
        done()
      end)
    end)
  end)
end

local function install_piper(choice, done)
  local tool
  for _, t in ipairs(M.installers) do
    if t.name == choice then tool = t end
  end
  local path = tool and rt.which(tool.program)
  if not path then return done(tostring(choice) .. " isn't installed") end
  local argv = { path, table.unpack(tool.args) }
  rt.spawn(argv, function(r)
    if r.code ~= 0 then
      return done(tool.name .. " couldn't install piper-tts: " .. trim(r.error or (r.stderr ~= "" and r.stderr or r.stdout)))
    end
    notify("installed piper")
    done()
  end)
end

-- A step the page asked for: "pull", "voice" or "piper" (with data.choice).
function M.act(name, data)
  if name == "pull" then
    step("pull", pull)
  elseif name == "voice" then
    step("voice", function(done) download_voice(data and data.choice or M.VOICES[1].name, done) end)
  elseif name == "piper" then
    step("piper", function(done) install_piper(data and data.choice, done) end)
  elseif name == "check" then
    broadcast()
  end
end

function M.health(report)
  for _, item in ipairs(M.local_checks()) do
    if item.ok then
      report.ok(item.name .. ": " .. item.detail)
    elseif item.optional then
      report.warn(item.name .. ": " .. item.detail)
    else
      report.error(item.name .. ": " .. item.detail .. " (:listen-library helps set it up)")
    end
  end
end

function M.setup(user_opts)
  opts = user_opts or {}
  rt.command("listen", function() M.make() end, "Make a spoken summary of this page")
  rt.command("listen-library", function() M.library() end, "Browse and play your spoken summaries")
  for _, lhs in ipairs(bound) do rt.keymap.del("normal", lhs) end
  bound = {}
  local key = opts.key == nil and "gA" or opts.key
  if key and key ~= "" then
    rt.keymap.set("normal", key, function() M.make() end, { desc = "Spoken summary of this page" })
    table.insert(bound, key)
  end
end

return M
