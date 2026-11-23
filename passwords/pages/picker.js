// The login picker: a prompt, and this site's logins that match it, best
// first. It only ever sees labels; the passwords stay with the plugin.
"use strict";

const send = (name, data) => rt.send(name, JSON.stringify(data ?? {}));
const promptEl = document.getElementById("prompt");
const countEl = document.getElementById("count");
const listEl = document.getElementById("list");

let pool = [];
let query = "";
let cursor = 0;
let shown = [];
let selected = 0;
let what = "login";

// Where `needle` matches `hay` in order, and how well: consecutive letters
// and starts of words count more. Null when it doesn't match.
function fuzzy(needle, hay) {
  const at = hay.indexOf(needle);
  if (at >= 0) {
    const start = at === 0 || /\W/.test(hay[at - 1]);
    return { score: 100 + needle.length * 10 + (start ? 50 : 0), hits: [...needle].map((_, i) => at + i) };
  }
  const hits = [];
  let score = 0;
  let from = 0;
  for (const ch of needle) {
    const i = hay.indexOf(ch, from);
    if (i < 0) return null;
    score += hits.length && i === hits[hits.length - 1] + 1 ? 8 : 1;
    if (i === 0 || /\W/.test(hay[i - 1])) score += 5;
    hits.push(i);
    from = i + 1;
  }
  return { score, hits };
}

// Each word of the query must match the manager or the label.
function match(item, words) {
  let score = 0;
  const hits = { label: new Set(), manager: new Set() };
  for (const word of words) {
    const inLabel = fuzzy(word, item.labelLower);
    const inManager = fuzzy(word, item.managerLower);
    const best = inLabel && (!inManager || inLabel.score >= inManager.score) ? ["label", inLabel] : ["manager", inManager];
    if (!best[1]) return null;
    score += best[1].score;
    best[1].hits.forEach((i) => hits[best[0]].add(i));
  }
  return { item, score, hits };
}

function filter() {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  const matched = [];
  for (const item of pool) {
    const m = match(item, words);
    if (m) matched.push(m);
  }
  matched.sort((a, b) => b.score - a.score || a.item.order - b.item.order);
  shown = matched;
  selected = Math.min(selected, Math.max(0, shown.length - 1));
  countEl.textContent = `${matched.length}/${pool.length}`;
  render();
}

// `text` with the characters at `hits` in bold.
function marked(text, hits, className) {
  const span = document.createElement("span");
  span.className = className;
  let run = "";
  let bold = false;
  const flush = () => {
    if (!run) return;
    span.append(bold ? Object.assign(document.createElement("b"), { textContent: run }) : run);
    run = "";
  };
  for (let i = 0; i < text.length; i++) {
    if (hits.has(i) !== bold) {
      flush();
      bold = !bold;
    }
    run += text[i];
  }
  flush();
  return span;
}

function render() {
  promptEl.replaceChildren(
    query.slice(0, cursor),
    Object.assign(document.createElement("span"), { className: "cursor", textContent: query[cursor] ?? " " }),
    query.slice(cursor + 1),
  );
  if (!pool.length) {
    listEl.replaceChildren(Object.assign(document.createElement("li"), { className: "empty", textContent: "Loading…" }));
    return;
  }
  listEl.replaceChildren(
    ...shown.map((m, i) => {
      const row = document.createElement("li");
      row.className = i === selected ? "selected" : "";
      row.append(marked(m.item.manager, m.hits.manager, "manager"), marked(m.item.label, m.hits.label, "label"));
      row.addEventListener("click", () => choose(i, what));
      return row;
    }),
  );
  listEl.children[selected]?.scrollIntoView({ block: "nearest" });
}

function choose(index, how) {
  const m = shown[index];
  if (m) send("choose", { id: m.item.id, what: how });
}

function move(by) {
  if (!shown.length) return;
  selected = (selected + by + shown.length) % shown.length;
  render();
}

function edit(text, at) {
  query = text;
  cursor = Math.max(0, Math.min(at, query.length));
  selected = 0;
  filter();
}

// A key in nvim-style notation: "a", "C-n", "A-u", "Enter".
function press(k) {
  switch (k) {
    case "Enter": return choose(selected, what);
    case "A-u": return choose(selected, "username");
    case "A-p": return choose(selected, "password");
    case "Escape": case "C-c": return send("close");
    case "ArrowDown": case "Tab": case "C-n": case "C-j": return move(1);
    case "ArrowUp": case "C-p": case "C-k": return move(-1);
    case "ArrowLeft": cursor = Math.max(0, cursor - 1); return render();
    case "ArrowRight": cursor = Math.min(query.length, cursor + 1); return render();
    case "Home": case "C-a": cursor = 0; return render();
    case "End": case "C-e": cursor = query.length; return render();
    case "Backspace": case "C-h":
      if (cursor > 0) edit(query.slice(0, cursor - 1) + query.slice(cursor), cursor - 1);
      return;
    case "Delete":
      return edit(query.slice(0, cursor) + query.slice(cursor + 1), cursor);
    case "C-w": {
      const start = query.slice(0, cursor).replace(/\S*\s*$/, "").length;
      return edit(query.slice(0, start) + query.slice(cursor), start);
    }
    case "C-u": return edit(query.slice(cursor), 0);
    default:
      if ([...k].length === 1) edit(query.slice(0, cursor) + k + query.slice(cursor), cursor + 1);
  }
}

addEventListener("keydown", (e) => {
  e.preventDefault();
  if (e.metaKey || ["Shift", "Control", "Alt", "Meta"].includes(e.key)) return;
  if (e.key === "Tab" && e.shiftKey) return move(-1);
  const key = e.key.length === 1 ? e.key.toLowerCase() : e.key;
  if (e.altKey) return press(`A-${key}`);
  press(e.ctrlKey ? `C-${key}` : e.key);
});

addEventListener("rtmessage", (e) => {
  const { name, data } = e.detail;
  if (name === "items") {
    what = data.what || "login";
    pool = data.items.map((item, order) => ({
      ...item,
      order,
      labelLower: item.label.toLowerCase(),
      managerLower: item.manager.toLowerCase(),
    }));
    filter();
  } else if (name === "type") {
    for (const ch of data.text) press(ch);
  } else if (name === "key") {
    press(data.key);
  }
});

render();
send("ready");
