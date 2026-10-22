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

-- In a frame: every visible place `wanted` shows, remembered for the labels
-- to come; its number of places. Each frame of the page does this.
local FIND_JS = [[(wanted) => {
  const key = Symbol.for("riptide.flash");
  window[key]?.overlay?.remove();
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
  if (innerWidth > 0 && innerHeight > 0) walk(document.body || document.documentElement);
  found.sort((a, b) => a.rect.top - b.rect.top || a.rect.left - b.rect.left);
  window[key] = { found, labels: [] };
  return found.length;
}]]

-- In a frame: label its places, in order, with `labels`.
local DRAW_JS = [[(labels) => {
  const state = window[Symbol.for("riptide.flash")];
  if (!state) return false;
  state.labels = labels;
  const overlay = document.createElement("div");
  overlay.setAttribute("aria-hidden", "true");
  Object.assign(overlay.style, { position: "fixed", inset: "0", pointerEvents: "none", zIndex: "2147483647" });
  state.found.forEach((f, i) => {
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
  state.overlay = overlay;
  return true;
}]]

-- In a frame: act on its place labelled `label`, and take the labels away.
local ACT_JS = [[(label, follow) => {
  const key = Symbol.for("riptide.flash");
  const state = window[key];
  if (!state) return null;
  state.overlay?.remove();
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
  window[key]?.overlay?.remove();
  delete window[key];
  return true;
})()]]

-- Every frame of the page, the main one first: `fn(list)` with each frame's
-- `{ frame, value }`. A riptide without frame = "all" answers for the main
-- frame alone, which this turns into a list of one.
local function in_every_frame(code, fn)
  rt.page.eval(code, function(result, err)
    if err then return fn(nil, err) end
    if type(result) == "table" and type(result[1]) == "table" and result[1].frame then
      return fn(result)
    end
    if type(result) == "table" and #result == 0 and next(result) == nil then return fn({}) end
    fn({ { value = result } })
  end, { frame = "all" })
end

local function clear()
  in_every_frame(CLEAR_JS, function() end)
end

-- Labels for `count` places: one letter each while they last, then pairs.
local function make_labels(count)
  local chars = {}
  for ch in LABELS:gmatch(".") do table.insert(chars, ch) end
  local out = {}
  for i = 1, count do
    if count <= #chars then
      out[i] = chars[i]
    else
      local n = i - 1
      out[i] = chars[(n // #chars) % #chars + 1] .. chars[n % #chars + 1]
    end
  end
  return out
end

local function close(state)
  if active ~= state then return end
  active = nil
  if state.float:is_open() then state.float:close() end
end

local function act(state, label)
  close(state)
  local frame = state.owner[label]
  rt.page.eval(call(ACT_JS, label, state.follow), function(result, err)
    if result == "jumped" then
      rt.enter_mode("caret", { frame = frame })
    elseif result == "no link" then
      rt.notify("flash: there's no link there", "warning")
    elseif not result then
      rt.notify("flash: " .. (err or "that place is gone"), "error")
    end
    clear()
  end, { frame = frame })
end

local function search(state)
  state.phase = "waiting"
  in_every_frame(call(FIND_JS, state.typed), function(frames, err)
    if active ~= state then return clear() end
    if not frames then
      close(state)
      return rt.notify("flash: " .. tostring(err), "error")
    end
    local total = 0
    for _, f in ipairs(frames) do
      if type(f.value) == "number" then total = total + f.value end
    end
    if total == 0 then
      close(state)
      return rt.notify("flash: " .. state.typed .. " isn't on screen", "warning")
    end
    -- Labels go to the frames in order, each its share.
    local labels = make_labels(total)
    state.labels, state.owner = labels, {}
    local next_label = 1
    for _, f in ipairs(frames) do
      local count = type(f.value) == "number" and f.value or 0
      if count > 0 then
        local mine = {}
        for i = next_label, next_label + count - 1 do
          table.insert(mine, labels[i])
          state.owner[labels[i]] = f.frame
        end
        next_label = next_label + count
        rt.page.eval(call(DRAW_JS, mine), function() end, { frame = f.frame })
      end
    end
    if total == 1 then return act(state, labels[1]) end
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
      clear()
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
        clear()
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
