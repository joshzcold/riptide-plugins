-- The page you're on, read aloud: Readability finds the article, Piper reads
-- it (or a summary a local LLM in Ollama writes) into a clip, paragraph by
-- paragraph. :listen-library lists the clips and plays them with their text.
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

-- How much of an article goes to the LLM, and how much is read aloud (about
-- an hour).
local SUMMARY_CHARS = 20000
local ARTICLE_CHARS = 60000

-- In the page: the article's title, text and paragraphs, or null if there's none.
local EXTRACT_JS = "(() => {\n" .. readability .. [[

  const article = new Readability(document.cloneNode(true), { serializer: (el) => el }).parse();
  if (!article || !article.textContent || (article.length ?? 0) < 200) return null;
  const title = (article.title || document.title).trim();
  const blocks = "h1,h2,h3,h4,h5,h6,p,li,blockquote,dt,dd";
  const paragraphs = [];
  let total = 0;
  let truncated = false;
  for (const el of article.content.querySelectorAll(blocks)) {
    if (el.parentElement?.closest(blocks) || el.closest("pre, table, figure")) continue;
    const text = el.textContent.replace(/\s+/g, " ").trim();
    if (!/[\p{L}\p{N}]/u.test(text) || (!paragraphs.length && text === title)) continue;
    if (total + text.length > ]] .. ARTICLE_CHARS .. [[) {
      truncated = true;
      break;
    }
    total += text.length;
    paragraphs.push({ text, heading: /^H[1-6]$/.test(el.tagName) });
  }
  return {
    title,
    site: article.siteName || location.hostname,
    text: article.textContent.replace(/\s+/g, " ").trim().slice(0, ]] .. SUMMARY_CHARS .. [[),
    paragraphs,
    truncated,
    url: location.href,
  };
})()]]

local PROMPT = [[Summarize this article as a short script to be read aloud, about %d words.
Write plain spoken sentences in a few short paragraphs separated by blank lines:
no headings, lists, markdown, links or emoji, and no preamble.
Start with what it's about, not with "This article" or "Here's a summary".

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

-- What gA reads: "article" or "summary".
function M.mode() return opts.read == "summary" and "summary" or "article" end

local function find(id)
  for i, clip in ipairs(M.clips()) do
    if clip.id == id then return clip, i end
  end
end

local function refresh()
  local payload = { clips = M.clips(), pending = M.pending }
  for _, page in ipairs(libraries) do pcall(page.send, page, "clips", payload) end
end

-- Where a program is: on PATH, else where uv, pipx, cargo and Homebrew put
-- programs, which riptide started from a desktop may not have on PATH.
local function locate(name)
  local found = rt.which(name)
  if found or name:find("/", 1, true) then return found end
  local home = os.getenv("HOME")
  local dirs = { "/opt/homebrew/bin/", "/usr/local/bin/" }
  if home then
    table.insert(dirs, 1, home .. "/.cargo/bin/")
    table.insert(dirs, 1, home .. "/.local/bin/")
  end
  for _, dir in ipairs(dirs) do
    local f = io.open(dir .. name, "rb")
    if f then
      f:close()
      return dir .. name
    end
  end
end

-- A program's path: the option if it's set, else wherever locate finds it.
local function program(name)
  local given = opts[name]
  if given and given ~= "" then return rt.which(given) end
  return locate(name)
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
  text = trim(text):gsub("^[Hh]ere[’']?s [^\n]-:%s*", "")
  return text
end

-- Text as paragraphs, split at blank lines.
function M.paragraphs(text)
  local list = {}
  for block in ((text or "") .. "\n\n"):gmatch("(.-)\n%s*\n") do
    local para = trim(block:gsub("%s+", " "))
    if para:match("[%w\128-\255]") then table.insert(list, { text = para }) end
  end
  return list
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

-- A WAV file's format, and where its samples are: { fmt, byte_rate, offset, size }.
local function wav_info(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local head = f:read(12)
  if not head or #head < 12 or head:sub(1, 4) ~= "RIFF" or head:sub(9, 12) ~= "WAVE" then
    f:close()
    return nil
  end
  local info = {}
  while true do
    local chunk = f:read(8)
    if not chunk or #chunk < 8 then break end
    local kind, size = chunk:sub(1, 4), string.unpack("<I4", chunk, 5)
    if kind == "fmt " then
      local fmt = f:read(size)
      info.fmt = fmt:sub(1, 16)
      info.byte_rate = string.unpack("<I4", fmt, 9)
      info.block_align = string.unpack("<I2", fmt, 13)
      if size % 2 == 1 then f:read(1) end
    elseif kind == "data" then
      info.offset = f:seek()
      -- A WAV written as a stream gives its size as 0xFFFFFFFF.
      info.size = math.min(size, f:seek("end") - info.offset)
      break
    else
      f:seek("cur", size + size % 2)
    end
  end
  f:close()
  if info.fmt and info.offset and (info.byte_rate or 0) > 0 then return info end
end

-- Joins WAV files of one format into out, with gap seconds of silence between;
-- returns when each starts and the total, in seconds.
local function join(paths, out, gap)
  local first = wav_info(paths[1])
  if not first then return nil, "piper wrote no audio" end
  local w = io.open(out, "wb")
  if not w then return nil, "couldn't write " .. out end
  w:write(string.rep("\0", 44))
  local silence = string.rep("\0", math.floor(first.byte_rate * gap / first.block_align) * first.block_align)
  local starts, total = {}, 0
  for i, path in ipairs(paths) do
    local info = wav_info(path)
    if not info or info.fmt ~= first.fmt then
      w:close()
      return nil, "piper wrote parts in different formats"
    end
    if i > 1 then
      w:write(silence)
      total = total + #silence
    end
    starts[i] = total / first.byte_rate
    local f = io.open(path, "rb")
    f:seek("set", info.offset)
    local left = info.size
    while left > 0 do
      local data = f:read(math.min(left, 1 << 20))
      if not data then break end
      w:write(data)
      left = left - #data
    end
    f:close()
    total = total + info.size
  end
  w:seek("set", 0)
  w:write("RIFF", string.pack("<I4", 36 + total), "WAVE", "fmt ", string.pack("<I4", 16), first.fmt,
    "data", string.pack("<I4", total))
  w:close()
  return starts, total / first.byte_rate
end

-- The WAV files piper says it wrote, in order: piper1 logs "Wrote PATH", the
-- older piper prints each path.
local function written(r)
  local paths = {}
  for path in (r.stderr or ""):gmatch("Wrote ([^\n]-%.wav)") do table.insert(paths, path) end
  if #paths == 0 then
    for path in (r.stdout or ""):gmatch("([^\n]-%.wav)\n") do table.insert(paths, path) end
  end
  return paths
end

-- Reads paragraphs ({ text, heading }) into a clip, one piper part each, so
-- each paragraph's start is known. callback(file, seconds) or (nil, nil, err);
-- the paragraphs get their start times.
function M.speak(paragraphs, id, callback)
  local dir = M.dir()
  local parts = dir .. "/" .. id .. ".parts"
  local wav = dir .. "/" .. id .. ".wav"
  local lines = {}
  for i, p in ipairs(paragraphs) do lines[i] = p.text end
  rt.spawn({ "mkdir", "-p", parts }, function(made)
    if made.code ~= 0 then return callback(nil, nil, "couldn't make " .. parts .. ": " .. trim(made.stderr)) end
    local argv = { program("piper") or "piper", "--model", M.voice(), "--output_dir", parts }
    rt.spawn(argv, { stdin = table.concat(lines, "\n") .. "\n" }, function(r)
      local paths = written(r)
      local function cleanup()
        for _, path in ipairs(paths) do os.remove(path) end
        os.remove(parts)
      end
      if r.error or r.code ~= 0 or #paths == 0 then
        cleanup()
        local why = trim(r.error or r.stderr):match("[^\n]*$")
        return callback(nil, nil, "piper failed: " .. why)
      end
      local starts, seconds = join(paths, wav, 0.4)
      cleanup()
      if not starts then return callback(nil, nil, seconds) end
      if #starts == #paragraphs then
        for i, p in ipairs(paragraphs) do p.start = starts[i] end
      end
      local ffmpeg = program("ffmpeg")
      if not ffmpeg then return callback(id .. ".wav", seconds) end
      local ogg = dir .. "/" .. id .. ".ogg"
      rt.spawn({ ffmpeg, "-y", "-loglevel", "error", "-i", wav, "-c:a", "libopus", "-b:a", "32k", ogg }, function(c)
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

-- Makes a clip of the page: mode is "article" or "summary", else the read option's.
function M.make(mode)
  if mode ~= "article" and mode ~= "summary" then mode = M.mode() end
  if not program("piper") or not exists(M.voice()) then
    notify("piper and a voice aren't set up yet; see the setup on this page", "error")
    return M.library()
  end
  local url = rt.url()
  if not url:match("^https?://") and not url:match("^file://") then
    return notify("this page has no article to read", "warning")
  end
  rt.page.eval(EXTRACT_JS, function(article, err)
    if err then return notify(err, "error") end
    if not article then return notify("no article found on this page", "warning") end
    local id = os.date("%Y%m%d-%H%M%S") .. string.format("-%04d", math.random(0, 9999))
    local job = { id = id, title = article.title, url = article.url, stage = mode == "summary" and "summarizing" or "speaking" }
    table.insert(M.pending, job)
    refresh()
    notify((mode == "summary" and "summarizing “" or "reading “") .. article.title .. "”…")
    local function fail(message)
      done(job)
      refresh()
      notify(message, "error")
    end

    local function speak(paragraphs, summary)
      job.stage = "speaking"
      refresh()
      table.insert(paragraphs, 1, { text = article.title, heading = true })
      M.speak(paragraphs, id, function(file, seconds, perr)
        if not file then return fail(perr) end
        local text_file = id .. ".json"
        local f = io.open(M.dir() .. "/" .. text_file, "wb")
        if f then
          f:write(rt.json.encode({ paragraphs = paragraphs }))
          f:close()
        end
        local clips = M.clips()
        table.insert(clips, 1, {
          id = id,
          file = file,
          text_file = f and text_file or nil,
          mode = mode,
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
        local more = article.truncated and "; it's the first hour of a longer article" or ""
        notify("ready: “" .. article.title .. "”" .. more .. " (:listen-library)")
      end)
    end

    if mode == "article" then
      local paragraphs = {}
      for _, p in ipairs(article.paragraphs or {}) do
        table.insert(paragraphs, { text = p.text, heading = p.heading or nil })
      end
      if #paragraphs == 0 then paragraphs = M.paragraphs(article.text) end
      return speak(paragraphs)
    end
    M.summarize(article, function(summary, serr)
      if not summary then return fail(serr) end
      local paragraphs = M.paragraphs(summary)
      if #paragraphs == 0 then return fail("Ollama's summary was empty") end
      speak(paragraphs, summary)
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

-- A clip's paragraphs: from its text file, else its summary as one.
function M.text(clip)
  local f = clip.text_file and io.open(M.dir() .. "/" .. clip.text_file, "rb")
  if f then
    local ok, data = pcall(rt.json.decode, f:read("a"))
    f:close()
    if ok and type(data) == "table" and type(data.paragraphs) == "table" then return data.paragraphs end
  end
  if clip.summary then return { { text = clip.summary } } end
  return {}
end

-- Audio goes to the page in parts, a callback each, so a long clip doesn't
-- run into the 2-second limit; a multiple of 3 bytes base64-encodes alone.
local PART = 3 * 262144

function M.play(id, page)
  local clip = find(id)
  local path = clip and (M.dir() .. "/" .. clip.file)
  local f = path and io.open(path, "rb")
  if not f then return page:send("audio", { id = id, error = "this clip's file is gone" }) end
  local size = f:seek("end")
  f:close()
  local parts = math.max(1, math.ceil(size / PART))
  local mime = clip.file:match("%.ogg$") and "audio/ogg" or "audio/wav"
  page:send("audio", { id = id, mime = mime, parts = parts, paragraphs = M.text(clip) })
  local function send(i)
    local fh = io.open(path, "rb")
    if not fh then return end
    fh:seek("set", (i - 1) * PART)
    local data = fh:read(PART) or ""
    fh:close()
    if not pcall(page.send, page, "audio_part", { id = id, index = i, data = M.base64(data) }) then return end
    if i < parts then rt.defer(0, function() send(i + 1) end) end
  end
  rt.defer(0, function() send(1) end)
end

function M.delete(id)
  local clip, i = find(id)
  if not clip then return end
  os.remove(M.dir() .. "/" .. clip.file)
  if clip.text_file then os.remove(M.dir() .. "/" .. clip.text_file) end
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

-- The system's package manager family from /etc/os-release's text: debian,
-- fedora, arch or suse, else linux. RHEL and its clones list fedora in ID_LIKE
-- but lack Fedora's packages, so they're plain linux.
function M.system(os_release)
  if rt.platform ~= "linux" then return rt.platform end
  local text = os_release
  if not text then
    local f = io.open("/etc/os-release", "rb")
    if not f then return "linux" end
    text = f:read("a")
    f:close()
  end
  text = "\n" .. text
  local id = text:match('\nID="?([^"\n]+)') or ""
  local like = " " .. (text:match('\nID_LIKE="?([^"\n]+)') or "") .. " "
  local function is(name) return id == name or like:find(" " .. name .. " ", 1, true) end
  if id == "fedora" then return "fedora" end
  if is("debian") or is("ubuntu") then return "debian" end
  if is("arch") then return "arch" end
  if id:match("^opensuse") or is("suse") or is("opensuse") then return "suse" end
  return "linux"
end

-- The command that installs each program on each system; none where we
-- don't know one that works out of the box.
local SCRIPT_UV = "curl -LsSf https://astral.sh/uv/install.sh | sh"
local SCRIPT_OLLAMA = "curl -fsSL https://ollama.com/install.sh | sh"
local INSTALL = {
  curl = {
    debian = "sudo apt install curl",
    fedora = "sudo dnf install curl",
    arch = "sudo pacman -S curl",
    suse = "sudo zypper install curl",
  },
  ffmpeg = {
    debian = "sudo apt install ffmpeg",
    fedora = "sudo dnf install ffmpeg-free",
    arch = "sudo pacman -S ffmpeg",
    brew = "brew install ffmpeg",
    windows = "winget install Gyan.FFmpeg",
  },
  uv = {
    debian = SCRIPT_UV,
    fedora = SCRIPT_UV,
    arch = "sudo pacman -S uv",
    suse = SCRIPT_UV,
    linux = SCRIPT_UV,
    brew = "brew install uv",
    macos = SCRIPT_UV,
    windows = "winget install astral-sh.uv",
  },
  ollama = {
    debian = SCRIPT_OLLAMA,
    fedora = SCRIPT_OLLAMA,
    arch = "sudo pacman -S ollama",
    suse = SCRIPT_OLLAMA,
    linux = SCRIPT_OLLAMA,
    brew = "brew install ollama",
    windows = "winget install Ollama.Ollama",
  },
}

-- The command that installs name on system, or nil. On macOS, brew's when
-- Homebrew is installed.
function M.install_command(name, system, has_brew)
  local commands = INSTALL[name] or {}
  if system == "macos" and has_brew then return commands.brew or commands.macos end
  return commands[system]
end

local function install(name)
  local system = M.system()
  return M.install_command(name, system, system == "macos" and locate("brew") ~= nil)
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
      if locate(tool.program) then table.insert(found, { value = tool.name, label = tool.name }) end
    end
    if #found > 1 then
      item.action = { name = "piper", label = "Install", choices = found }
    elseif #found == 1 then
      item.action = { name = "piper", label = "Install with " .. found[1].value, choice = found[1].value }
    else
      item.detail = item.detail .. ". Install uv, then piper (or: pipx install piper-tts)"
      item.commands = commands(install("uv"), "uv tool install piper-tts")
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
    -- Reading articles needs no LLM; only summaries do.
    if M.mode() == "article" then
      for _, item in ipairs(ollama) do
        if not item.ok then
          item.optional = true
          item.detail = "only for summaries (:listen summary): " .. item.detail
        end
      end
    end
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
      if locate("ollama") then
        item.detail = "installed, but not answering at " .. base .. ". Start it"
        item.commands = rt.platform == "linux" and { "systemctl start ollama", "ollama serve" } or { "ollama serve" }
      elseif opts.ollama and opts.ollama ~= "" then
        item.detail = "nothing answers at " .. base .. ", the ollama option"
      else
        item.detail = "writes the summaries, on your computer; it isn't installed"
        item.commands = commands(install("ollama"))
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
  local path = tool and locate(tool.program)
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
  rt.command("listen", function(args) M.make(trim(args)) end, {
    desc = "Read this page's article aloud; :listen summary for a spoken summary",
    complete = function() return { "article", "summary" } end,
  })
  rt.command("listen-library", function() M.library() end, "Browse and play what you've listened to")
  for _, lhs in ipairs(bound) do rt.keymap.del("normal", lhs) end
  bound = {}
  local key = opts.key == nil and "gA" or opts.key
  if key and key ~= "" then
    rt.keymap.set("normal", key, function() M.make() end, { desc = "Read this page aloud" })
    table.insert(bound, key)
  end
end

return M
