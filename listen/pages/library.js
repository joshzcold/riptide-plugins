// The clips the plugin saved. Playing one asks the plugin for its bytes, which
// come in parts, and plays them from a blob: URL beside their text, following
// along paragraph by paragraph.
"use strict";

const send = (name, data) => rt.send(name, JSON.stringify(data ?? {}));
const $ = (id) => document.getElementById(id);
const audio = $("audio");

let clips = [];
let pending = [];
let playing = null;
let url = null;
let ready = true;
// The clip arriving: { id, mime, parts, chunks }.
let incoming = null;
// The transcript's paragraphs with start times, and the one being read.
let timed = [];
let current = -1;
// Following along pauses for a while after you scroll the text yourself.
let followAfter = 0;

function el(tag, props = {}, ...children) {
  const node = Object.assign(document.createElement(tag), props);
  node.append(...children);
  return node;
}

function duration(seconds) {
  if (!seconds) return "";
  const s = Math.round(seconds);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

function when(created) {
  return new Date(created * 1000).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

function row(clip) {
  const play = el("button", { className: "play", textContent: clip.id === playing ? "Playing" : "Play" });
  play.addEventListener("click", () => start(clip));
  const remove = el("button", { className: "delete", textContent: "Delete" });
  // A second click deletes, rather than a confirm() dialog.
  remove.addEventListener("click", () => {
    if (remove.dataset.armed) return send("delete", { id: clip.id });
    remove.dataset.armed = "1";
    remove.textContent = "Delete?";
    setTimeout(() => {
      delete remove.dataset.armed;
      remove.textContent = "Delete";
    }, 3000);
  });
  const source = el("a", { href: clip.url, textContent: clip.site || clip.url });
  source.addEventListener("click", (e) => {
    e.preventDefault();
    send("open", { url: clip.url });
  });
  const summary = clip.summary
    ? el("details", {}, el("summary", { textContent: "Summary" }), el("p", { textContent: clip.summary }))
    : "";
  return el(
    "li",
    { className: clip.id === playing ? "clip current" : "clip" },
    el("div", { className: "actions" }, play, remove),
    el("h2", { textContent: clip.title }),
    el("p", { className: "meta" }, source, ` · ${clip.mode === "summary" ? "summary · " : ""}${when(clip.created)} · ${duration(clip.seconds)}`),
    summary,
  );
}

function empty() {
  return ready ? "No clips yet. Press gA on a page to make one." : "No clips yet. Finish the setup above, then press gA on a page.";
}

function link(target) {
  const a = el("a", { href: target.url, textContent: target.text });
  a.addEventListener("click", (e) => {
    e.preventDefault();
    send("open", { url: target.url });
  });
  return a;
}

// An action's button, after a choice when it has some; choices with a group
// (a voice's language) get a second list to pick the group first.
function action(item) {
  const row = el("div", { className: "do" });
  const choices = item.action.choices || [];
  const button = el("button");
  let choice = null;
  const update = () => {
    const picked = choices.find((c) => c.value === choice?.value);
    button.textContent = picked?.button || item.action.label;
    button.disabled = Boolean(item.ok && picked && picked.value === item.action.selected);
  };
  if (choices.length) {
    choice = el("select", { title: item.name });
    const fill = (group) => {
      const shown = group === undefined ? choices : choices.filter((c) => c.group === group);
      choice.replaceChildren(...shown.map((c) =>
        el("option", { value: c.value, textContent: c.label, selected: c.value === item.action.selected })));
      update();
    };
    const groups = [...new Set(choices.map((c) => c.group).filter(Boolean))];
    if (groups.length) {
      const first = choices.find((c) => c.value === item.action.selected)?.group || item.action.group || groups[0];
      const group = el("select", { title: "Language" },
        ...groups.map((g) => el("option", { value: g, textContent: g, selected: g === first })));
      group.addEventListener("change", () => fill(group.value));
      row.append(group);
      fill(group.value);
    } else {
      fill(undefined);
    }
    choice.addEventListener("change", update);
    row.append(choice);
  }
  update();
  button.addEventListener("click", () => {
    button.disabled = true;
    send("setup", { action: item.action.name, choice: choice?.value ?? item.action.choice });
  });
  row.append(button);
  return row;
}

function check(item) {
  const mark = item.busy ? "…" : item.ok ? "✓" : item.optional ? "–" : "✗";
  const state = item.busy ? "busy" : item.ok ? "ok" : item.optional ? "optional" : "missing";
  const body = el("div", { className: "body" },
    el("p", {}, el("strong", { textContent: item.name }), ` ${item.busy ? item.busy_text || "Working…" : item.detail}`));
  if (item.error && !item.busy) body.append(el("p", { className: "error", textContent: item.error }));
  if (!item.ok && !item.busy) {
    for (const command of item.commands || []) body.append(el("pre", {}, el("code", { textContent: command })));
  }
  // An action that stays once it's done, e.g. picking another voice.
  if (item.action && !item.busy && (!item.ok || item.action.keep)) body.append(action(item));
  if (item.link && !item.busy && (!item.ok || item.action?.keep)) body.append(el("p", { className: "meta" }, link(item.link)));
  return el("li", { className: `check ${state}` }, el("span", { className: "mark", textContent: mark }), body);
}

function status(data) {
  const items = Array.isArray(data.items) ? data.items : [];
  const left = items.filter((i) => !i.ok && !i.optional).length;
  ready = Boolean(data.ready);
  $("setup").hidden = false;
  const voice = items.find((i) => i.id === "voice" && i.ok && i.action?.selected);
  $("setup-title").textContent = left
    ? `Setup: ${left} ${left === 1 ? "step" : "steps"} left`
    : `Setup: ready${voice ? ` · voice: ${voice.detail}` : ""}`;
  if (left) $("setup").open = true;
  $("checks").replaceChildren(...items.map(check));
  render();
  send("setup_shown", { left, busy: items.filter((i) => i.busy).length });
}

function start(clip) {
  playing = clip.id;
  $("now").textContent = clip.title;
  $("player").hidden = false;
  send("play", { id: clip.id });
  render();
}

function render() {
  const words = $("filter").value.toLowerCase().split(/\s+/).filter(Boolean);
  const shown = clips.filter((c) => {
    const text = `${c.title} ${c.site} ${c.summary}`.toLowerCase();
    return words.every((w) => text.includes(w));
  });
  $("pending").replaceChildren(
    ...pending.map((j) => el("li", { className: "muted", textContent: `${j.stage === "speaking" ? "Reading" : "Summarizing"} “${j.title}”…` })),
  );
  $("clips").replaceChildren(
    ...(shown.length
      ? shown.map(row)
      : [el("li", { className: "muted", textContent: clips.length ? "No clips match." : empty() })]),
  );
  send("shown", { clips: shown.length, pending: pending.length });
}

function transcript(paragraphs) {
  timed = [];
  current = -1;
  const nodes = (Array.isArray(paragraphs) ? paragraphs : []).map((p) => {
    const node = el("p", { className: p.heading ? "heading" : "", textContent: p.text });
    if (typeof p.start === "number") {
      node.classList.add("timed");
      node.title = "Play from here";
      node.addEventListener("click", () => {
        audio.currentTime = p.start;
        followAfter = 0;
        audio.play().catch(() => {});
      });
      timed.push({ start: p.start, node });
    }
    return node;
  });
  $("transcript").replaceChildren(...nodes);
  $("transcript").hidden = nodes.length === 0;
  $("transcript").scrollTop = 0;
}

// Marks the paragraph being read and scrolls it into view.
function follow() {
  let i = timed.length - 1;
  while (i >= 0 && timed[i].start > audio.currentTime + 0.05) i--;
  if (i === current) return;
  if (current >= 0) timed[current].node.classList.remove("now");
  current = i;
  if (i < 0) return;
  const node = timed[i].node;
  node.classList.add("now");
  if (Date.now() < followAfter) return;
  const box = $("transcript");
  box.scrollTo({ top: node.offsetTop - box.clientHeight / 3, behavior: "smooth" });
}

function play(data) {
  if (data.id !== playing) return;
  if (data.error) {
    $("now").textContent = data.error;
    return send("loaded", { id: data.id, error: data.error });
  }
  transcript(data.paragraphs);
  incoming = { id: data.id, mime: data.mime, parts: data.parts, chunks: [] };
}

function part(data) {
  if (!incoming || data.id !== incoming.id || data.id !== playing) return;
  incoming.chunks[data.index - 1] = Uint8Array.from(atob(data.data), (c) => c.charCodeAt(0));
  if (incoming.chunks.filter(Boolean).length < incoming.parts) return;
  const blob = new Blob(incoming.chunks, { type: incoming.mime });
  incoming = null;
  if (url) URL.revokeObjectURL(url);
  url = URL.createObjectURL(blob);
  audio.src = url;
  audio.playbackRate = Number($("speed").value);
  audio.play().catch(() => {});
}

audio.addEventListener("loadedmetadata", () => send("loaded", { id: playing, duration: audio.duration, timed: timed.length }));
audio.addEventListener("error", () => send("loaded", { id: playing, error: audio.error?.message || "can't play this clip" }));
$("speed").addEventListener("change", () => { audio.playbackRate = Number($("speed").value); });
audio.addEventListener("timeupdate", follow);
audio.addEventListener("seeked", follow);
for (const event of ["wheel", "touchmove"]) {
  $("transcript").addEventListener(event, () => { followAfter = Date.now() + 5000; }, { passive: true });
}
$("filter").addEventListener("input", render);
$("recheck").addEventListener("click", (e) => {
  e.preventDefault();
  send("setup", { action: "check" });
});

addEventListener("rtmessage", (e) => {
  const { name, data } = e.detail;
  if (name === "clips") {
    // An empty Lua table arrives as {}, not [].
    clips = Array.isArray(data.clips) ? data.clips : [];
    pending = Array.isArray(data.pending) ? data.pending : [];
    render();
  } else if (name === "play") {
    const clip = clips.find((c) => c.id === data.id);
    if (clip) start(clip);
  } else if (name === "status") {
    status(data);
  } else if (name === "audio") {
    play(data);
  } else if (name === "audio_part") {
    part(data);
  }
});

send("ready");
