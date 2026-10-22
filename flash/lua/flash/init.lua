-- Jump to text on the page, like flash.nvim and leap.nvim: type two
-- characters, every place they show on screen gets a label, and typing the
-- label puts the caret there (caret mode), or follows the link it's in.
local M = {}

local LABELS = "asdfghjklqwertyuiopzxcvbnm"
-- Keys the float takes: what can be searched for, and labels.
local CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  .. "!\"#$%&'()*+,-./:;=>?@[\\]^_`{|}~"

local opts = {}
local bound = {}
local active

-- In the page: label every visible place `wanted` shows, and remember them.
local FIND_JS = [[(wanted, labelChars) => {
  const key = Symbol.for("riptide.flash");
  window[key]?.overlay.remove();
  const exact = /[A-Z]/.test(wanted);
  const needle = exact ? wanted : wanted.toLowerCase();
  const found = [];
  const skip = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "TEXTAREA", "INPUT"]);
  const walk = (root) => {
    const it = document.createTreeWalker(root, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
    for (let node = it.nextNode(); node; node = it.nextNode()) {
      if (node.nodeType === Node.ELEMENT_NODE) {
        if (node.shadowRoot) walk(node.shadowRoot);
        continue;
      }
      const parent = node.parentElement;
      if (!parent || skip.has(parent.tagName)) continue;
      const text = exact ? node.data : node.data.toLowerCase();
      for (let at = text.indexOf(needle); at >= 0; at = text.indexOf(needle, at + 1)) {
        const range = document.createRange();
        range.setStart(node, at);
        range.setEnd(node, at + needle.length);
        const r = range.getClientRects()[0];
        if (!r || r.bottom < 0 || r.top > innerHeight || r.right < 0 || r.left > innerWidth) continue;
        if (parent.checkVisibility && !parent.checkVisibility({ visibilityProperty: true })) continue;
        found.push({ range, rect: r });
      }
    }
  };
  walk(document.body || document.documentElement);
  found.sort((a, b) => a.rect.top - b.rect.top || a.rect.left - b.rect.left);
  const chars = [...labelChars];
  const labels = found.length <= chars.length
    ? chars.slice(0, found.length)
    : found.map((_, i) => chars[Math.floor(i / chars.length) % chars.length] + chars[i % chars.length]);
  const overlay = document.createElement("div");
  overlay.setAttribute("aria-hidden", "true");
  Object.assign(overlay.style, { position: "fixed", inset: "0", pointerEvents: "none", zIndex: "2147483647" });
  found.forEach((f, i) => {
    const tag = document.createElement("span");
    tag.textContent = labels[i];
    Object.assign(tag.style, {
      position: "fixed", left: `${f.rect.left}px`, top: `${f.rect.top}px`,
      font: "bold 12px/1.2 monospace", padding: "0 2px", borderRadius: "3px",
      background: "#ff007c", color: "#fff", boxShadow: "0 0 0 1px #000",
    });
    overlay.appendChild(tag);
  });
  document.documentElement.appendChild(overlay);
  window[key] = { overlay, found, labels };
  return labels;
}]]

-- In the page: act on the place labelled `label`, and take the labels away.
local ACT_JS = [[(label, follow) => {
  const key = Symbol.for("riptide.flash");
  const state = window[key];
  if (!state) return null;
  state.overlay.remove();
  delete window[key];
  const i = state.labels.indexOf(label);
  if (i < 0) return null;
  const range = state.found[i].range;
  if (follow) {
    let el = range.startContainer.parentElement;
    const link = el && el.closest("a[href], button, [role=link], [role=button]");
    if (!link) return "no link";
    link.click();
    return "followed";
  }
  getSelection().collapse(range.startContainer, range.startOffset);
  return "jumped";
}]]

-- `fn`, a JavaScript function's text, called with `args` (Lua values).
local function call(fn, ...)
  local args = {}
  for i, v in ipairs({ ... }) do args[i] = rt.json.encode(v) end
  return "(" .. fn .. ")(" .. table.concat(args, ", ") .. ")"
end

local CLEAR_JS = [[(() => {
  const key = Symbol.for("riptide.flash");
  window[key]?.overlay.remove();
  delete window[key];
  return true;
})()]]

local function close(state)
  if active ~= state then return end
  active = nil
  if state.float:is_open() then state.float:close() end
end

local function act(state, label)
  close(state)
  rt.page.eval(call(ACT_JS, label, state.follow), function(result, err)
    if result == "jumped" then
      rt.enter_mode("caret")
    elseif result == "no link" then
      rt.notify("flash: there's no link there", "warning")
    elseif not result then
      rt.notify("flash: " .. (err or "that place is gone"), "error")
    end
  end)
end

local function search(state)
  state.phase = "waiting"
  rt.page.eval(call(FIND_JS, state.typed, LABELS), function(labels, err)
    if active ~= state then return rt.page.eval(CLEAR_JS, function() end) end
    if not labels then
      close(state)
      return rt.notify("flash: " .. tostring(err), "error")
    end
    if #labels == 0 then
      close(state)
      return rt.notify("flash: " .. state.typed .. " isn't on screen", "warning")
    end
    if #labels == 1 then return act(state, labels[1]) end
    state.labels = labels
    state.phase = "label"
    state.float:update({ lines = { { { "flash ", "muted" }, { state.typed, "match" }, { "  label?", "muted" } } } })
  end)
end

local function press(state, ch)
  if active ~= state then return end
  if state.phase == "search" then
    state.typed = state.typed .. ch
    state.float:update({ lines = { { { "flash ", "muted" }, { state.typed, "match" } } } })
    if #state.typed == 2 then search(state) end
  elseif state.phase == "label" then
    state.label = state.label .. ch
    local prefix = false
    for _, label in ipairs(state.labels) do
      if label == state.label then return act(state, label) end
      if label:sub(1, #state.label) == state.label then prefix = true end
    end
    if not prefix then
      close(state)
      rt.page.eval(CLEAR_JS, function() end)
    end
  end
end

-- Start a jump: `follow` follows the link at the place instead.
function M.start(follow)
  if active then close(active) end
  local state = { typed = "", label = "", phase = "search", follow = follow == true }
  active = state
  local keys = {}
  for ch in CHARS:gmatch(".") do
    keys[ch] = function() press(state, ch) end
  end
  keys["<Space>"] = function() press(state, " ") end
  keys["<Less>"] = function() press(state, "<") end
  state.float = rt.ui.float({
    title = follow and "flash: follow" or "flash",
    lines = { { { "flash ", "muted" }, { "type two characters", "muted" } } },
    position = "bottom",
    keys = keys,
    on_close = function()
      if active == state then
        active = nil
        rt.page.eval(CLEAR_JS, function() end)
      end
    end,
  })
end

-- The jump in progress, for tests: type into it as its float's keys would.
function M.typing(text)
  local state = active
  if not state then return false end
  for ch in text:gmatch(".") do press(state, ch) end
  return true
end

function M.setup(user_opts)
  opts = user_opts or {}
  rt.command("flash", function(args) M.start(args == "follow") end, {
    desc = "Jump to text on screen by two of its characters; :flash follow follows its link",
    complete = function() return { "follow" } end,
  })
  for _, lhs in ipairs(bound) do rt.keymap.del("normal", lhs) end
  bound = {}
  local key = opts.key == nil and "<Space>s" or opts.key
  local follow_key = opts.follow_key == nil and "<Space>S" or opts.follow_key
  if key and key ~= "" then
    rt.keymap.set("normal", key, function() M.start(false) end, { desc = "Flash: jump to text" })
    table.insert(bound, key)
  end
  if follow_key and follow_key ~= "" then
    rt.keymap.set("normal", follow_key, function() M.start(true) end, { desc = "Flash: follow the link at text" })
    table.insert(bound, follow_key)
  end
end

return M
