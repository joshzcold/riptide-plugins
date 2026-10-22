// Shows the article the plugin sends. Its HTML comes from the site, so only
// plain text markup and links are kept: no scripts, styles, forms or frames,
// and no images, which plugin pages can't load from other sites.
"use strict";

const send = (name, data) => rt.send(name, JSON.stringify(data ?? {}));

const KEEP = new Set([
  "A", "ABBR", "ARTICLE", "B", "BLOCKQUOTE", "BR", "CAPTION", "CITE", "CODE", "DD", "DEL", "DETAILS",
  "DFN", "DIV", "DL", "DT", "EM", "FIGCAPTION", "FIGURE", "H1", "H2", "H3", "H4", "H5", "H6", "HR",
  "I", "INS", "KBD", "LI", "MAIN", "MARK", "OL", "P", "PRE", "Q", "S", "SAMP", "SECTION", "SMALL",
  "SPAN", "STRONG", "SUB", "SUMMARY", "SUP", "TABLE", "TBODY", "TD", "TFOOT", "TH", "THEAD", "TIME",
  "TR", "U", "UL", "VAR",
]);
const DROP = new Set([
  "SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "IFRAME", "FRAME", "OBJECT", "EMBED", "FORM", "INPUT",
  "BUTTON", "SELECT", "TEXTAREA", "SVG", "MATH", "VIDEO", "AUDIO", "SOURCE", "TRACK", "CANVAS",
  "LINK", "META", "BASE", "PICTURE",
]);
const ATTRIBUTES = { A: ["href", "title"], TD: ["colspan", "rowspan"], TH: ["colspan", "rowspan"], ABBR: ["title"] };

function clean(node) {
  for (const child of [...node.children]) {
    const tag = child.tagName.toUpperCase();
    if (tag === "IMG") {
      const alt = child.getAttribute("alt")?.trim();
      const note = document.createElement("span");
      note.className = "image";
      note.textContent = alt ? `[image: ${alt}]` : "[image]";
      child.replaceWith(note);
      continue;
    }
    if (DROP.has(tag)) {
      child.remove();
      continue;
    }
    clean(child);
    if (!KEEP.has(tag)) {
      child.replaceWith(...child.childNodes);
      continue;
    }
    const allowed = ATTRIBUTES[tag] ?? [];
    for (const { name } of [...child.attributes]) {
      if (!allowed.includes(name)) child.removeAttribute(name);
    }
    if (tag === "A") {
      const href = child.getAttribute("href") ?? "";
      if (!/^https?:\/\//i.test(href)) child.removeAttribute("href");
    }
  }
}

function minutes(chars) {
  return Math.max(1, Math.round(chars / 1200));
}

function show(article) {
  const content = document.getElementById("content");
  if (!article) {
    content.innerHTML = '<p class="muted">This reader view has closed. Open the page again and use :reader.</p>';
    return;
  }
  document.title = article.title || "Reader";
  if (article.lang) document.documentElement.lang = article.lang;
  document.getElementById("title").textContent = article.title || "";
  const site = document.getElementById("site");
  const original = Object.assign(document.createElement("a"), {
    href: article.url,
    textContent: article.siteName || new URL(article.url).hostname,
  });
  site.replaceChildren(original);
  const meta = [article.byline, article.length ? `${minutes(article.length)} min read` : null].filter(Boolean);
  document.getElementById("meta").textContent = meta.join(" · ");

  const doc = new DOMParser().parseFromString(article.content, "text/html");
  clean(doc.body);
  content.replaceChildren(...doc.body.childNodes);

  // What's shown, for the plugin's tests.
  const unsafe = content.querySelectorAll("script, style, iframe, img, form, [style], [class]:not(.image), [onclick], [onerror]");
  send("shown", {
    title: document.title,
    paragraphs: content.querySelectorAll("p").length,
    images: content.querySelectorAll(".image").length,
    links: content.querySelectorAll("a[href]").length,
    unsafe: unsafe.length,
  });
}

// Links leave through the plugin: here, or a new tab with Ctrl or the middle button.
addEventListener("click", (e) => {
  const link = e.target.closest("a[href]");
  if (!link) return;
  e.preventDefault();
  send("open", { url: link.href, tab: e.ctrlKey || e.metaKey });
});
addEventListener("auxclick", (e) => {
  const link = e.target.closest("a[href]");
  if (!link || e.button !== 1) return;
  e.preventDefault();
  send("open", { url: link.href, tab: true });
});

addEventListener("rtmessage", (e) => {
  if (e.detail.name === "article") show(e.detail.data);
});

send("ready");
