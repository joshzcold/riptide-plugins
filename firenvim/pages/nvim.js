// The nvim the plugin started, drawn on a canvas: connects to its bridge,
// attaches as a UI with the line grid, sends keys and mouse, and tells the
// plugin when nvim writes the text.
"use strict";

const canvas = document.getElementById("grid");
const ctx = canvas.getContext("2d", { alpha: false });
const send = (name, data) => rt.send(name, JSON.stringify(data ?? {}));
addEventListener("error", (e) => send("error", { message: e.message }));
addEventListener("unhandledrejection", (e) => send("error", { message: String(e.reason?.message ?? e.reason) }));

let socket = null;
let nextId = 1;
const pending = new Map();
let attached = false;

let font = "13px monospace";
let cell = { width: 8, height: 16, ascent: 12 };
let cols = 80;
let rows = 24;
let grid = [];
let cursor = { row: 0, col: 0 };
let colors = { fg: 0xffffff, bg: 0x000000, sp: 0xff0000 };
const highlights = new Map();
let modes = [];
let mode = {};
let busy = false;

const hex = (n) => `#${n.toString(16).padStart(6, "0")}`;

function call(method, params) {
  const id = nextId++;
  socket.send(msgpack.encode([0, id, method, params]));
  return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
}

function measure() {
  ctx.font = font;
  const m = ctx.measureText("M");
  const ascent = Math.ceil(m.fontBoundingBoxAscent ?? m.actualBoundingBoxAscent);
  const descent = Math.ceil(m.fontBoundingBoxDescent ?? m.actualBoundingBoxDescent);
  cell = { width: m.width, height: ascent + descent, ascent };
  cols = Math.max(20, Math.floor(innerWidth / cell.width));
  rows = Math.max(4, Math.floor(innerHeight / cell.height));
}

function resizeCanvas() {
  const ratio = devicePixelRatio || 1;
  canvas.width = Math.ceil(cols * cell.width * ratio);
  canvas.height = Math.ceil(rows * cell.height * ratio);
  canvas.style.width = `${cols * cell.width}px`;
  canvas.style.height = `${rows * cell.height}px`;
  ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
}

function blankGrid(width, height) {
  grid = Array.from({ length: height }, () =>
    Array.from({ length: width }, () => ({ text: " ", hl: 0 })),
  );
}

function style(hl) {
  const attr = highlights.get(hl) ?? {};
  let fg = attr.foreground ?? colors.fg;
  let bg = attr.background ?? colors.bg;
  if (attr.reverse) [fg, bg] = [bg, fg];
  return { attr, fg: hex(fg), bg: hex(bg), sp: hex(attr.special ?? colors.sp) };
}

function drawCell(row, col, invert) {
  const c = grid[row]?.[col];
  if (!c) return;
  const s = style(c.hl);
  const x = col * cell.width;
  const y = row * cell.height;
  const wide = grid[row][col + 1]?.text === "" ? 2 : 1;
  ctx.fillStyle = invert ? s.fg : s.bg;
  ctx.fillRect(x, y, cell.width * wide, cell.height);
  if (c.text && c.text !== " ") {
    ctx.font = `${s.attr.italic ? "italic " : ""}${s.attr.bold ? "bold " : ""}${font}`;
    ctx.fillStyle = invert ? s.bg : s.fg;
    ctx.fillText(c.text, x, y + cell.ascent);
  }
  if (s.attr.underline || s.attr.undercurl || s.attr.strikethrough) {
    ctx.fillStyle = s.attr.underline || s.attr.undercurl ? s.sp : invert ? s.bg : s.fg;
    const line = s.attr.strikethrough ? y + cell.height / 2 : y + cell.ascent + 2;
    ctx.fillRect(x, line, cell.width * wide, 1);
  }
}

function draw() {
  for (let row = 0; row < grid.length; row++) {
    for (let col = 0; col < grid[row].length; col++) drawCell(row, col, false);
  }
  drawCursor();
}

function drawCursor() {
  if (busy) return;
  const { row, col } = cursor;
  const shape = mode.cursor_shape ?? "block";
  const percent = (mode.cell_percentage || 100) / 100;
  if (shape === "block" || !document.hasFocus()) {
    drawCell(row, col, true);
    return;
  }
  ctx.fillStyle = style(grid[row]?.[col]?.hl ?? 0).fg;
  const x = col * cell.width;
  const y = row * cell.height;
  if (shape === "vertical") ctx.fillRect(x, y, Math.max(1, cell.width * percent), cell.height);
  else ctx.fillRect(x, y + cell.height * (1 - percent), cell.width, Math.max(1, cell.height * percent));
}

const redraw = {
  grid_resize([, width, height]) {
    blankGrid(width, height);
  },
  default_colors_set([fg, bg, sp]) {
    colors = { fg: fg < 0 ? 0xffffff : fg, bg: bg < 0 ? 0 : bg, sp: sp < 0 ? 0xff0000 : sp };
    document.body.style.background = hex(colors.bg);
  },
  hl_attr_define([id, attr]) {
    highlights.set(id, attr);
  },
  grid_line([, row, start, cells]) {
    let col = start;
    let hl = 0;
    for (const [text, id, repeat] of cells) {
      if (id !== undefined) hl = id;
      for (let i = 0; i < (repeat ?? 1); i++) {
        if (grid[row]?.[col]) grid[row][col] = { text, hl };
        col++;
      }
    }
  },
  grid_clear() {
    blankGrid(grid[0]?.length ?? cols, grid.length);
  },
  grid_cursor_goto([, row, col]) {
    cursor = { row, col };
  },
  grid_scroll([, top, bottom, left, right, count]) {
    const step = count > 0 ? 1 : -1;
    const [from, to] = count > 0 ? [top, bottom - count] : [bottom - 1, top - count];
    for (let row = from; count > 0 ? row < to : row >= to; row += step) {
      for (let col = left; col < right; col++) grid[row][col] = grid[row + count][col];
    }
  },
  mode_info_set([, info]) {
    modes = info;
  },
  mode_change([, index]) {
    mode = modes[index] ?? {};
  },
  busy_start() {
    busy = true;
  },
  busy_stop() {
    busy = false;
  },
  flush() {
    draw();
  },
};

function onMessage([type, ...rest]) {
  if (type === 1) {
    const [id, error, result] = rest;
    const call = pending.get(id);
    pending.delete(id);
    if (error) call?.reject(new Error(Array.isArray(error) ? error[1] : String(error)));
    else call?.resolve(result);
  } else if (type === 2) {
    const [method, params] = rest;
    if (method === "redraw") {
      for (const [name, ...batches] of params) {
        const handle = redraw[name];
        if (handle) for (const args of batches) handle(args);
      }
    } else if (method === "rt_firenvim_filetype") {
      send("filetype", { filetype: params[0], detected: params[1] });
    } else if (method === "rt_firenvim_write") {
      send("write", { text: params[0] });
      call("nvim_set_var", ["rt_firenvim_got", params[1]]);
    }
  }
}

// Keys as nvim's notation, e.g. <C-w> or <lt>; nothing for a bare modifier.
const NAMES = {
  Backspace: "BS", Tab: "Tab", Enter: "CR", Escape: "Esc", " ": "Space", Delete: "Del",
  ArrowUp: "Up", ArrowDown: "Down", ArrowLeft: "Left", ArrowRight: "Right", Home: "Home",
  End: "End", PageUp: "PageUp", PageDown: "PageDown", Insert: "Insert",
  "<": "lt", "\\": "Bslash", "|": "Bar",
};

function nvimKey(e) {
  const named = NAMES[e.key] ?? (/^F\d{1,2}$/.test(e.key) ? e.key : null);
  if (!named && [...e.key].length !== 1) return null;
  const mods = [];
  if (e.ctrlKey) mods.push("C");
  if (e.altKey) mods.push("A");
  if (e.metaKey) mods.push("D");
  // A character already has shift applied; a named key needs it spelled out.
  if (e.shiftKey && named && [...e.key].length !== 1) mods.push("S");
  if (!mods.length && !named) return e.key;
  return `<${[...mods, named ?? e.key].join("-")}>`;
}

addEventListener("keydown", (e) => {
  if (!attached) return;
  e.preventDefault();
  if (e.isComposing) return;
  const key = nvimKey(e);
  if (key) call("nvim_input", [key]);
});

addEventListener("paste", (e) => {
  if (!attached) return;
  e.preventDefault();
  call("nvim_paste", [e.clipboardData.getData("text/plain"), true, -1]);
});

const BUTTONS = ["left", "middle", "right"];
function mouse(button, action, e) {
  if (!attached) return;
  const mods = `${e.ctrlKey ? "C" : ""}${e.altKey ? "A" : ""}${e.shiftKey ? "S" : ""}`;
  const row = Math.floor(e.offsetY / cell.height);
  const col = Math.floor(e.offsetX / cell.width);
  call("nvim_input_mouse", [button, action, mods, 0, row, col]);
}
canvas.addEventListener("mousedown", (e) => {
  canvas.focus();
  mouse(BUTTONS[e.button] ?? "left", "press", e);
});
canvas.addEventListener("mouseup", (e) => mouse(BUTTONS[e.button] ?? "left", "release", e));
canvas.addEventListener("mousemove", (e) => {
  if (e.buttons & 1) mouse("left", "drag", e);
});
canvas.addEventListener("wheel", (e) => {
  e.preventDefault();
  mouse("wheel", e.deltaY < 0 ? "up" : "down", e);
}, { passive: false });
canvas.addEventListener("contextmenu", (e) => e.preventDefault());

addEventListener("resize", () => {
  if (!attached) return;
  measure();
  resizeCanvas();
  call("nvim_ui_try_resize", [cols, rows]);
});
addEventListener("focus", draw);
addEventListener("blur", draw);

// Connect to the bridge, retrying while nvim starts; a newer start (nvim
// again, on another port) replaces an older one.
let starts = 0;
function connect(start, deadline, mine) {
  if (mine !== starts || socket) return;
  const ws = new WebSocket(`ws://127.0.0.1:${start.port}/?token=${start.token}`);
  ws.binaryType = "arraybuffer";
  let opened = false;
  ws.onopen = async () => {
    opened = true;
    socket = ws;
    const decoder = new msgpack.Decoder(onMessage);
    ws.onmessage = (e) => decoder.push(new Uint8Array(e.data));
    try {
      await attach(start);
    } catch (e) {
      send("error", { message: String(e.message ?? e) });
      ws.close();
    }
  };
  ws.onclose = () => {
    if (opened) return send("closed");
    if (Date.now() < deadline) setTimeout(() => connect(start, deadline, mine), 100);
    else if (mine !== starts) return;
    else send("error", { message: "nvim didn't start listening" });
  };
}

// Dragging the grip resizes the float; the plugin keeps the size it ends at.
const grip = document.getElementById("grip");
let resizing = null;
grip.addEventListener("pointerdown", (e) => {
  e.preventDefault();
  e.stopPropagation();
  grip.setPointerCapture(e.pointerId);
  resizing = { x: e.clientX, y: e.clientY, width: innerWidth, height: innerHeight, frame: 0 };
});
grip.addEventListener("pointermove", (e) => {
  if (!resizing || resizing.frame) return;
  resizing.frame = requestAnimationFrame(() => {
    resizing.frame = 0;
    send("resize", {
      width: Math.round(resizing.width + e.clientX - resizing.x),
      height: Math.round(resizing.height + e.clientY - resizing.y),
    });
  });
});
grip.addEventListener("pointerup", () => {
  resizing = null;
  setTimeout(() => send("resized", { width: innerWidth, height: innerHeight }), 100);
});

const dismiss = document.getElementById("dismiss");
dismiss.addEventListener("mousedown", (e) => e.stopPropagation());
dismiss.addEventListener("click", () => send("dismiss"));

async function attach(start) {
  font = start.font || font;
  dismiss.hidden = !start.dismiss;
  measure();
  resizeCanvas();
  blankGrid(cols, rows);
  const [channel] = await call("nvim_get_api_info", []);
  await call("nvim_ui_attach", [cols, rows, { ext_linegrid: true, rgb: true }]);
  await call("nvim_exec_lua", [
    "RtFirenvim.start(...)",
    [start.text, start.name, start.line, start.col, channel, start.filetype ?? ""],
  ]);
  attached = true;
  canvas.focus();
  send("attached");
}

addEventListener("rtmessage", (e) => {
  const { name, data } = e.detail;
  if (name === "start") connect(data, Date.now() + 5000, ++starts);
  if (name === "input" && attached) call("nvim_input", [data.keys]);
});

send("ready");
