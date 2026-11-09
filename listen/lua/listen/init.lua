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

local function program(name)
  local given = opts[name]
  if given and given ~= "" then return given end
  return name
end

-- The LLM's answer as plain sentences for Piper: no reasoning, no markdown.
function M.clean(text)
  text = (text or ""):gsub("<think>.-</think>", ""):gsub("[*_#`]", "")
  return trim(text)
end

function M.summarize(article, callback)
  local body = rt.json.encode({
    model = opts.model or "llama3.2",
    prompt = PROMPT:format(tonumber(opts.words) or 150, article.title or "", article.text),
    stream = false,
    -- Ollama's default context would cut a long article short without saying so.
    options = { num_ctx = 8192 },
  })
  local endpoint = (opts.ollama or "http://localhost:11434"):gsub("/+$", "")
  local argv = {
    M.curl, "-sS", "--fail-with-body", "--max-time", "600",
    "-H", "Content-Type: application/json", "--data-binary", "@-", endpoint .. "/api/generate",
  }
  rt.spawn(argv, { stdin = body }, function(r)
    if r.error then return callback(nil, "couldn't run curl: " .. r.error) end
    local ok, answer = pcall(rt.json.decode, r.stdout or "")
    if ok and type(answer) == "table" and answer.error then
      return callback(nil, "Ollama: " .. tostring(answer.error))
    end
    if r.code ~= 0 or not ok or type(answer) ~= "table" then
      return callback(nil, "no answer from Ollama at " .. endpoint .. ": " .. trim(r.stderr ~= "" and r.stderr or r.stdout))
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
    rt.spawn({ program("piper"), "--model", opts.voice, "--output_file", wav }, { stdin = text }, function(r)
      local seconds = wav_seconds(wav)
      if r.error or r.code ~= 0 or not seconds then
        return callback(nil, nil, "piper failed: " .. trim(r.error or r.stderr))
      end
      local ffmpeg = rt.which(program("ffmpeg"))
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
  if not opts.voice or opts.voice == "" then
    return notify("set the voice option to a Piper voice (.onnx) first", "error")
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

function M.health(report)
  if rt.which(M.curl) then report.ok("curl found") else report.error("curl isn't installed; it reaches Ollama") end
  if rt.which(program("piper")) then
    report.ok("piper found")
  else
    report.error("piper isn't installed (pipx install piper-tts), or set the piper option")
  end
  local voice = opts.voice and opts.voice ~= "" and io.open(opts.voice, "rb")
  if voice then voice:close() elseif opts.voice then report.warn("no voice file at " .. opts.voice) end
  if rt.which(program("ffmpeg")) then
    report.ok("ffmpeg found; clips are saved as Opus")
  else
    report.warn("ffmpeg isn't installed; clips are saved as WAV, about 10 times larger")
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
