-- Edits the focused text field in nvim, drawn over the field like firenvim:
-- a headless nvim talks to this plugin's page over a WebSocket on
-- 127.0.0.1, and every :w puts the text back in the field.
local bridge = require("firenvim.bridge")

local M = {}

local ORIGIN = "riptide://firenvim.plugin"
-- Room for nvim on a one-line field, in CSS pixels.
local MIN_WIDTH, MIN_HEIGHT = 480, 240

local opts = {}
local session
local bound = {}
local hooked = false
-- Fields auto mode leaves alone: rules[host][field] = "never", and
-- rules[host]["*"] = "never" for the whole site. filetypes[host][field] is
-- the filetype last set in nvim for the field, when it isn't nvim's own, and
-- places[host][field] where it was dragged to from the field, { x, y }, and
-- sizes[host][field] the size its grip left it at, { width, height }.
local store = rt.store("firenvim")

local function hex(bytes)
  local out = {}
  for i = 1, bytes do
    out[i] = string.format("%02x", math.random(0, 255))
  end
  return table.concat(out)
end

-- The page's elements this plugin edited, by token, kept from the page.
local ELEMENTS = 'window[Symbol.for("riptide.firenvim")] ??= new Map()'

-- The focused text field: its text, cursor and place, or null. With
-- `auto`, only fields of that kind not edited before.
local function field_js(token, auto)
  return string.format([[(() => {
  const token = %s, auto = %s;
  let el = document.activeElement;
  while (el && el.shadowRoot && el.shadowRoot.activeElement) el = el.shadowRoot.activeElement;
  if (!el || el.readOnly || el.disabled) return null;
  const kind = el instanceof HTMLTextAreaElement ? "textarea"
    : el instanceof HTMLInputElement && ["text", "search", "url", "email", "tel"].includes(el.type) ? "input"
    : el.isContentEditable ? "editable" : null;
  if (!kind) return null;
  if (auto && (el.dataset.rtFirenvimDone || (auto === "textarea" && kind === "input"))) return null;
  (%s).set(token, el);
  const text = kind === "editable" ? el.innerText : el.value;
  const at = kind === "editable" ? text.length : (el.selectionStart ?? text.length);
  const before = text.slice(0, at).split("\n");
  const r = el.getBoundingClientRect();
  return {
    text, line: before.length, col: new TextEncoder().encode(before[before.length - 1]).length,
    rect: { x: r.left, y: r.top, width: r.width, height: r.height },
    viewport: { width: innerWidth, height: innerHeight },
    top: window === window.top,
    name: location.hostname + "_" + (el.id || el.name || el.tagName.toLowerCase()),
    // In a frame, choices still belong to the tab's site, e.g. mail.google.com.
    host: location.ancestorOrigins?.length
      ? new URL(location.ancestorOrigins[location.ancestorOrigins.length - 1]).hostname
      : location.hostname,
    // The same field on every page of the site, e.g. each issue's comment box.
    field: kind + ":" + (el.name || el.getAttribute("aria-label") || el.placeholder || el.id || el.tagName.toLowerCase()),
    label: el.getAttribute("aria-label") || el.placeholder || el.name || el.id || "",
  };
})()]], rt.json.encode(token), rt.json.encode(auto or false), ELEMENTS)
end

-- Put `text` in the field, as typing would, so the page's scripts see it.
local function write_js(token, text)
  return string.format([[(() => {
  const el = (%s).get(%s);
  if (!el || !el.isConnected) return false;
  const text = %s;
  if (el instanceof HTMLTextAreaElement || el instanceof HTMLInputElement) {
    const set = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), "value")?.set;
    if (set) set.call(el, text); else el.value = text;
  } else {
    el.innerText = text;
  }
  el.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertReplacementText" }));
  el.dispatchEvent(new Event("change", { bubbles: true }));
  return true;
})()]], ELEMENTS, rt.json.encode(token), rt.json.encode(text))
end

-- Back to the field, which auto mode then leaves alone.
local function refocus_js(token)
  return string.format([[(() => {
  const els = %s, el = els.get(%s);
  els.delete(%s);
  if (el && el.isConnected) { el.dataset.rtFirenvimDone = "1"; el.focus(); }
})()]], ELEMENTS, rt.json.encode(token), rt.json.encode(token))
end

-- Auto mode leaves the field alone until the page loads again.
local function skip_js(token)
  return string.format([[(() => {
  const els = %s, el = els.get(%s);
  els.delete(%s);
  if (el) el.dataset.rtFirenvimDone = "1";
})()]], ELEMENTS, rt.json.encode(token), rt.json.encode(token))
end

local function rule(field)
  local site = (store.get("rules") or {})[field.host] or {}
  return site["*"] or site[field.field]
end

local function filetype_of(field)
  return ((store.get("filetypes") or {})[field.host] or {})[field.field]
end

local function keep_filetype(field, filetype)
  local all = store.get("filetypes") or {}
  all[field.host] = all[field.host] or {}
  all[field.host][field.field] = filetype
  if next(all[field.host]) == nil then all[field.host] = nil end
  store.set("filetypes", all)
end

local function place_of(field)
  return ((store.get("places") or {})[field.host] or {})[field.field]
end

local function keep_place(field, x, y)
  local all = store.get("places") or {}
  all[field.host] = all[field.host] or {}
  all[field.host][field.field] = (x ~= 0 or y ~= 0) and { x = x, y = y } or nil
  if next(all[field.host]) == nil then all[field.host] = nil end
  store.set("places", all)
end

local function size_of(field)
  return ((store.get("sizes") or {})[field.host] or {})[field.field]
end

local function keep_size(field, width, height)
  local all = store.get("sizes") or {}
  all[field.host] = all[field.host] or {}
  all[field.host][field.field] = { width = width, height = height }
  store.set("sizes", all)
end

local function remember(host, field, choice)
  local rules = store.get("rules") or {}
  rules[host] = rules[host] or {}
  rules[host][field] = choice
  store.set("rules", rules)
end

-- A file name nvim can use, so filetype autocmds can match on the site.
local function file_name(name)
  return (name:gsub("[^%w._-]", "_"):sub(1, 80)) .. "." .. (opts.extension or "txt")
end

-- Where the float goes: over the field, grown to fit nvim and kept on the page.
local function cover(field)
  local r, view = field.rect, field.viewport
  local width = math.max(r.width, MIN_WIDTH)
  local height = math.max(r.height, MIN_HEIGHT)
  if not field.top then
    -- In a frame: riptide places it in the page and keeps it there.
    return { x = r.x, y = r.y, width = width, height = height, frame = field.frame }
  end
  local x = math.max(0, math.min(r.x, view.width - width))
  local y = math.max(0, math.min(r.y, view.height - height))
  return { x = x, y = y, width = width, height = height }
end

-- Runs in the field's frame, which may be an iframe.
local function eval_in(field, code, fn)
  rt.page.eval(code, fn or function() end, { frame = field.frame })
end

local function finish(s)
  if session ~= s then return end
  session = nil
  s.page:close()
  eval_in(s.field, refocus_js(s.token))
end

local ask_to_ignore

local function start(field, token, auto)
  local s = { token = token, attempts = 0, field = field }
  session = s

  local function launch()
    s.attempts = s.attempts + 1
    s.port = math.random(20000, 60999)
    rt.spawn({ opts.command or "nvim", "--headless", "--cmd", "lua assert(loadstring(vim.env.RT_FIRENVIM_BRIDGE))()" }, {
      env = {
        RT_FIRENVIM_BRIDGE = bridge,
        RT_FIRENVIM_PORT = tostring(s.port),
        RT_FIRENVIM_TOKEN = token,
        RT_FIRENVIM_ORIGIN = ORIGIN,
      },
    }, function(r)
      if session ~= s then return end
      -- 75: the port was taken; try another.
      if r.code == 75 and s.attempts < 5 and not s.attached then
        launch()
        if s.ready then s.page:send("start", s.start()) end
        return
      end
      if r.error then
        rt.notify("firenvim: couldn't run " .. (opts.command or "nvim") .. ": " .. r.error, "error")
      elseif r.code ~= 0 then
        local first = (r.stderr or ""):match("[^\r\n]+")
        rt.notify("firenvim: nvim exited with status " .. tostring(r.code) .. (first and (": " .. first) or ""), "error")
      elseif s.attached then
        -- The page says when the connection closes, after the last write.
        return rt.defer(2000, function() finish(s) end)
      end
      finish(s)
    end)
  end

  function s.dismiss()
    finish(s)
    ask_to_ignore(field)
  end

  function s.start()
    return {
      port = s.port,
      token = token,
      text = field.text,
      line = field.line,
      col = field.col,
      name = file_name(field.name),
      font = opts.font,
      filetype = filetype_of(field),
      -- Auto mode opened it, so it offers to leave the field alone next time.
      dismiss = auto == true,
    }
  end

  launch()
  s.page = rt.ui.page({
    path = "index.html",
    where = "float",
    title = "nvim",
    over = cover(field),
    offset = place_of(field),
    keys = "all",
    -- Dragged somewhere else: it opens there, next to this field, next time.
    on_move = function(x, y) keep_place(field, x, y) end,
    on_message = function(name, data, page)
      if session ~= s then return end
      if name == "ready" then
        s.ready = true
        local size = size_of(field)
        -- page:resize is newer than riptide 0.5.0.
        if size and page.resize then page:resize(size.width, size.height) end
        page:send("start", s.start())
      elseif name == "resize" then
        if page.resize then page:resize(data.width, data.height) end
      elseif name == "resized" then
        keep_size(field, data.width, data.height)
      elseif name == "attached" then
        s.attached = true
      elseif name == "write" then
        eval_in(field, write_js(token, data.text or ""), function(ok, err)
          if not ok then
            rt.notify("firenvim: couldn't put the text back: " .. (err or "the field is gone"), "error")
          end
        end)
      elseif name == "error" then
        rt.notify("firenvim: " .. tostring(data.message), "error")
        finish(s)
      elseif name == "closed" then
        finish(s)
      elseif name == "filetype" then
        local ft = data.filetype ~= data.detected and data.filetype ~= "" and data.filetype or nil
        keep_filetype(field, ft)
      elseif name == "dismiss" then
        s.dismiss()
      end
    end,
  })
end

local CHOICES = {
  { label = "Never on this field" },
  { label = "Never on this site", site = true },
  { label = "Just this time" },
}

-- Its ignore button closed nvim, which auto mode opened: leave the field alone from now on?
function ask_to_ignore(field)
  local what = field.label ~= "" and (" (" .. field.label .. ")") or ""
  rt.ui.select(CHOICES, {
    prompt = "Open nvim by itself on this field again? " .. field.host .. what,
    format = function(choice) return choice.label end,
  }, function(choice)
    if choice and choice.label ~= "Just this time" then
      remember(field.host, choice.site and "*" or field.field, "never")
    end
  end)
end

-- Auto mode on a field, unless it was told to leave it alone.
local function auto_open(field, token)
  if rule(field) == "never" then
    return eval_in(field, skip_js(token))
  end
  start(field, token, true)
end

-- Edit the focused field in nvim. `auto` is set when focusing it did this.
function M.open(auto)
  if session then return end
  local token = hex(16)
  -- The focused frame: fields in iframes too, e.g. Gmail's chat box.
  rt.page.eval(field_js(token, auto), function(field, err, frame)
    if field then field.frame = frame end
    if session then return end
    if not field then
      if not auto then
        rt.notify("firenvim: " .. (err or "focus a text field first"), err and "error" or "warning")
      end
      return
    end
    if auto then return auto_open(field, token) end
    start(field, token)
  end, { frame = "focused" })
end

-- Forget what auto mode was told for the current site.
local function forget()
  local host = rt.url():match("^%a[%w+.-]*://([^/?#:]+)")
  local rules = store.get("rules") or {}
  local filetypes = store.get("filetypes") or {}
  local places = store.get("places") or {}
  local sizes = store.get("sizes") or {}
  if not host or not (rules[host] or filetypes[host] or places[host] or sizes[host]) then
    return rt.notify("firenvim: nothing remembered for " .. (host or "this page"))
  end
  rules[host], filetypes[host], places[host], sizes[host] = nil, nil, nil, nil
  store.set("rules", rules)
  store.set("filetypes", filetypes)
  store.set("places", places)
  store.set("sizes", sizes)
  rt.notify("firenvim: forgot the choices, filetypes, places and sizes for " .. host)
end

-- The open editor, for tests: whether nvim is attached, and keys for it.
function M.session()
  if not session then return nil end
  return {
    attached = session.attached == true,
    input = function(keys) session.page:send("input", { keys = keys }) end,
    dismiss = session.dismiss,
  }
end

function M.setup(user_opts)
  opts = user_opts or {}
  rt.command("firenvim", function() M.open(false) end, "Edit the focused text field in nvim, over the field")
  rt.command("firenvim-forget", forget, "Forget which fields auto mode leaves alone on this site, their filetypes, and where nvim was dragged and resized to")

  for _, b in ipairs(bound) do rt.keymap.del(b[1], b[2]) end
  bound = {}
  local key = opts.key
  if key == nil then key = "<Ctrl-Shift-e>" end
  if key then
    for _, mode in ipairs({ "insert", "normal" }) do
      rt.keymap.set(mode, key, function() M.open(false) end, { desc = "Edit this field in nvim" })
      table.insert(bound, { mode, key })
    end
  end

  if not hooked then
    hooked = true
    rt.on("insert_entered", function()
      local auto = opts.auto
      if auto == "textarea" or auto == "all" then M.open(auto) end
    end)
  end
end

function M.health(report)
  local cmd = opts.command or "nvim"
  if rt.which(cmd) then
    report.ok(cmd .. " found")
  else
    report.error(cmd .. " isn't installed or isn't on your PATH; set the command option")
  end
end

return M
