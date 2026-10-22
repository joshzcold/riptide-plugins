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
-- rules[host]["*"] = "never" for the whole site.
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
    name: location.hostname + "_" + (el.id || el.name || el.tagName.toLowerCase()),
    host: location.hostname,
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
  local x = math.max(0, math.min(r.x, view.width - width))
  local y = math.max(0, math.min(r.y, view.height - height))
  return { x = x, y = y, width = width, height = height }
end

local function finish(s)
  if session ~= s then return end
  session = nil
  s.page:close()
  rt.page.eval(refocus_js(s.token), function() end)
end

local ask_to_ignore

local function start(field, token, auto)
  local s = { token = token, attempts = 0 }
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
    keys = "all",
    on_message = function(name, data, page)
      if session ~= s then return end
      if name == "ready" then
        s.ready = true
        page:send("start", s.start())
      elseif name == "attached" then
        s.attached = true
      elseif name == "write" then
        rt.page.eval(write_js(token, data.text or ""), function(ok, err)
          if not ok then
            rt.notify("firenvim: couldn't put the text back: " .. (err or "the field is gone"), "error")
          end
        end)
      elseif name == "error" then
        rt.notify("firenvim: " .. tostring(data.message), "error")
        finish(s)
      elseif name == "closed" then
        finish(s)
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

-- Its ✕ closed nvim, which auto mode opened: leave the field alone from now on?
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
    return rt.page.eval(skip_js(token), function() end)
  end
  start(field, token, true)
end

-- Edit the focused field in nvim. `auto` is set when focusing it did this.
function M.open(auto)
  if session then return end
  local token = hex(16)
  rt.page.eval(field_js(token, auto), function(field, err)
    if session then return end
    if not field then
      if not auto then
        rt.notify("firenvim: " .. (err or "focus a text field first"), err and "error" or "warning")
      end
      return
    end
    if auto then return auto_open(field, token) end
    start(field, token)
  end)
end

-- Forget what auto mode was told for the current site.
local function forget()
  local host = rt.url():match("^%a[%w+.-]*://([^/?#:]+)")
  local rules = store.get("rules") or {}
  if not host or not rules[host] then
    return rt.notify("firenvim: nothing remembered for " .. (host or "this page"))
  end
  rules[host] = nil
  store.set("rules", rules)
  rt.notify("firenvim: forgot the choices for " .. host .. "; auto mode asks again")
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
  rt.command("firenvim-forget", forget, "Forget which fields auto mode opens on this site, or leaves alone")

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
