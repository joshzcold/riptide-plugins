// The picker: a prompt, and the items that match it, best first. The float
// gets every key as a keydown event, so the prompt is edited here.
"use strict";

const send = (name, data) => rt.send(name, JSON.stringify(data ?? {}));
const promptEl = document.getElementById("prompt");
const countEl = document.getElementById("count");
const listEl = document.getElementById("list");

// Rows drawn: the best matches; the count says how many there are in all.
const MAX_SHOWN = 50;
const KINDS = { tab: "T", quickmark: "Q", bookmark: "B", history: "H" };
const RANK = { tab: 0, quickmark: 1, bookmark: 2, history: 3 };

let pool = [];
let withHistory = false;
let query = "";
let cursor = 0;
let shown = [];
// The last query and every item it matched: a longer query only narrows it.
let last = { query: null, matched: [] };
let selected = 0;
let searchTimer = null;

// Each of the query's words must match, as fzf does; a capital makes it
// match case.
function terms() {
  return query.split(/\s+/).filter(Boolean).map((t) => ({ text: t, exact: /[A-Z]/.test(t) }));
}

// Each item's title and URL lowercased once, not on every key.
function prepare(items) {
  for (const item of items) {
    item.titleLower = (item.title || "").toLowerCase();
    item.urlLower = (item.url || "").toLowerCase();
  }
  return items;
}

// Where `term` matches `text` (or its lowercase `lower`) in order, and how
// well: consecutive letters and starts of words count more. Null when it
// doesn't match.
function fuzzy(term, text, lower) {
  const hay = term.exact ? text : lower;
  const needle = term.exact ? term.text : term.text.toLowerCase();
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

function match(item, words) {
  let score = 0;
  const hits = { title: new Set(), url: new Set() };
  for (const term of words) {
    const inTitle = fuzzy(term, item.title || "", item.titleLower);
    const inUrl = fuzzy(term, item.url || "", item.urlLower);
    const best = inTitle && (!inUrl || inTitle.score + 5 >= inUrl.score) ? ["title", inTitle, 5] : ["url", inUrl, 0];
    if (!best[1]) return null;
    score += best[1].score + best[2];
    best[1].hits.forEach((i) => hits[best[0]].add(i));
  }
  return { item, score, hits };
}

function filter() {
  const words = terms();
  // Typing on narrows what the last query matched; anything else starts over.
  const narrowing = last.query !== null && query.startsWith(last.query) && !/\s$/.test(last.query);
  const candidates = narrowing ? last.matched : pool;
  const matched = [];
  for (const item of candidates) {
    const m = match(item, words);
    if (m) matched.push(m);
  }
  last = { query, matched: matched.map((m) => m.item) };
  matched.sort((a, b) =>
    b.score - a.score || RANK[a.item.kind] - RANK[b.item.kind] || (b.item.when ?? 0) - (a.item.when ?? 0));
  shown = matched.slice(0, MAX_SHOWN);
  selected = Math.min(selected, Math.max(0, shown.length - 1));
  countEl.textContent = `${matched.length}/${pool.length}`;
  render();
}

// `text` with the characters at `hits` in bold, one node per run.
function marked(text, hits) {
  const span = document.createElement("span");
  let run = "";
  let bold = false;
  const flush = () => {
    if (!run) return;
    span.append(bold ? Object.assign(document.createElement("b"), { textContent: run }) : run);
    run = "";
  };
  for (let i = 0; i < text.length; i++) {
    const hit = hits.has(i);
    if (hit !== bold) {
      flush();
      bold = hit;
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
  listEl.replaceChildren(
    ...shown.map((m, i) => {
      const row = document.createElement("li");
      row.className = i === selected ? "selected" : "";
      row.dataset.kind = m.item.kind;
      const kind = Object.assign(document.createElement("span"), {
        className: "kind",
        textContent: KINDS[m.item.kind],
      });
      const title = marked(m.item.title || m.item.url, m.hits.title);
      title.className = "title";
      const url = marked(m.item.url, m.hits.url);
      url.className = "url";
      row.append(kind, title, url);
      row.addEventListener("click", () => choose(i, "current"));
      return row;
    }),
  );
  listEl.children[selected]?.scrollIntoView({ block: "nearest" });
}

function choose(index, where) {
  const m = shown[index];
  if (m) send("choose", { item: m.item, where });
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
  // History holds more than the recent entries listed at first.
  if (withHistory) {
    clearTimeout(searchTimer);
    const word = terms()[0]?.text ?? "";
    if (word.length >= 2) searchTimer = setTimeout(() => send("search", { query: word }), 150);
  }
}

// A key, as nvim-style notation of what was pressed: "a", "C-n", "Enter".
function press(key, ctrl) {
  const k = ctrl ? `C-${key.toLowerCase()}` : key;
  switch (k) {
    case "Enter": return choose(selected, "current");
    case "C-t": return choose(selected, "tab");
    case "C-b": return choose(selected, "tab-bg");
    case "Escape": case "C-c": return send("close");
    case "ArrowDown": case "Tab": case "C-n": case "C-j": return move(1);
    case "ArrowUp": case "C-p": case "C-k": return move(-1);
    case "PageDown": return move(10);
    case "PageUp": return move(-10);
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
      if (!ctrl && [...key].length === 1) edit(query.slice(0, cursor) + key + query.slice(cursor), cursor + 1);
  }
}

addEventListener("keydown", (e) => {
  e.preventDefault();
  if (e.altKey || e.metaKey || ["Shift", "Control", "Alt", "Meta"].includes(e.key)) return;
  if (e.key === "Tab" && e.shiftKey) return move(-1);
  press(e.key, e.ctrlKey);
});

addEventListener("rtmessage", (e) => {
  const { name, data } = e.detail;
  if (name === "items") {
    withHistory = data.history;
    // A page saved several ways shows once: open tabs, then the first source.
    const seen = new Set();
    pool = prepare(data.items.filter((i) => i.kind === "tab" || (!seen.has(i.url) && seen.add(i.url))));
    last = { query: null, matched: [] };
    filter();
  } else if (name === "history") {
    if (data.query !== (terms()[0]?.text ?? "")) return;
    const known = new Set(pool.map((i) => i.url));
    const added = prepare(data.items.filter((i) => !known.has(i.url)));
    if (!added.length) return;
    pool = pool.concat(added);
    last = { query: null, matched: [] };
    filter();
  } else if (name === "type") {
    for (const ch of data.text) press(ch, false);
  } else if (name === "key") {
    const ctrl = data.key.startsWith("C-");
    press(ctrl ? data.key.slice(2) : data.key, ctrl);
  }
});

render();
send("ready");
