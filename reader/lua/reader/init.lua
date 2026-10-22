-- Reader view: the article on the current page, alone and cleanly typeset,
-- in a tab of its own. Mozilla's Readability finds it in a copy of the page;
-- the tab shows its text, without the page's scripts, styles or images.
local readability = require("reader.readability")

local M = {}

local opts = {}
local bound = {}
-- Articles waiting for their tab, by the tab's page id.
local articles = {}

-- In the page: the article, or null if Readability finds none.
local EXTRACT_JS = "(() => {\n" .. readability .. [[

  const article = new Readability(document.cloneNode(true)).parse();
  // A few words aren't an article.
  if (!article || !article.content || (article.length ?? 0) < 200) return null;
  return {
    title: article.title || document.title,
    byline: article.byline,
    siteName: article.siteName,
    lang: article.lang,
    content: article.content,
    length: article.length,
    url: location.href,
  };
})()]]

function M.open()
  local url = rt.url()
  if not url:match("^https?://") and not url:match("^file://") then
    return rt.notify("reader: this page has no article to read", "warning")
  end
  rt.page.eval(EXTRACT_JS, function(article, err)
    if err then return rt.notify("reader: " .. err, "error") end
    if not article then return rt.notify("reader: no article found on this page", "warning") end
    local page
    page = rt.ui.page({
      path = "index.html",
      on_message = function(name, data)
        if name == "ready" then
          page:send("article", articles[page.id] or false)
        elseif name == "shown" then
          M.shown = data
        elseif name == "open" and type(data.url) == "string" and data.url:match("^https?://") then
          rt.open(data.url, data.tab and "tab" or "current")
        end
      end,
    })
    articles[page.id] = article
  end)
end

function M.setup(user_opts)
  opts = user_opts or {}
  rt.command("reader", function() M.open() end, "Read this page's article alone, in a tab of its own")
  for _, lhs in ipairs(bound) do rt.keymap.del("normal", lhs) end
  bound = {}
  local key = opts.key == nil and "gR" or opts.key
  if key and key ~= "" then
    rt.keymap.set("normal", key, function() M.open() end, { desc = "Reader view of this page" })
    table.insert(bound, key)
  end
end

return M
