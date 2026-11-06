// The clips the plugin saved. Playing one asks the plugin for its bytes and
// plays them from a blob: URL.
"use strict";

const send = (name, data) => rt.send(name, JSON.stringify(data ?? {}));
const $ = (id) => document.getElementById(id);
const audio = $("audio");

let clips = [];
let pending = [];
let playing = null;
let url = null;

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
  const summary = el("details", {}, el("summary", { textContent: "Summary" }), el("p", { textContent: clip.summary }));
  return el(
    "li",
    { className: clip.id === playing ? "clip current" : "clip" },
    el("div", { className: "actions" }, play, remove),
    el("h2", { textContent: clip.title }),
    el("p", { className: "meta" }, source, ` · ${when(clip.created)} · ${duration(clip.seconds)}`),
    summary,
  );
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
    ...pending.map((j) => el("li", { className: "muted", textContent: `${j.stage === "speaking" ? "Speaking" : "Summarizing"} “${j.title}”…` })),
  );
  $("clips").replaceChildren(
    ...(shown.length
      ? shown.map(row)
      : [el("li", { className: "muted", textContent: clips.length ? "No clips match." : "No clips yet. Press gA on a page to make one." })]),
  );
  send("shown", { clips: shown.length, pending: pending.length });
}

function play(data) {
  if (data.id !== playing) return;
  if (data.error) {
    $("now").textContent = data.error;
    return send("loaded", { id: data.id, error: data.error });
  }
  const bytes = Uint8Array.from(atob(data.data), (c) => c.charCodeAt(0));
  if (url) URL.revokeObjectURL(url);
  url = URL.createObjectURL(new Blob([bytes], { type: data.mime }));
  audio.src = url;
  audio.playbackRate = Number($("speed").value);
  audio.play().catch(() => {});
}

audio.addEventListener("loadedmetadata", () => send("loaded", { id: playing, duration: audio.duration }));
audio.addEventListener("error", () => send("loaded", { id: playing, error: audio.error?.message || "can't play this clip" }));
$("speed").addEventListener("change", () => { audio.playbackRate = Number($("speed").value); });
$("filter").addEventListener("input", render);

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
  } else if (name === "audio") {
    play(data);
  }
});

send("ready");
