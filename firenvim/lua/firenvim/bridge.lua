-- The code the headless nvim runs (`--cmd`), as text: a WebSocket server on
-- 127.0.0.1 that lets this plugin's page, and only it, speak nvim's own
-- msgpack-RPC. It takes one connection, and nvim quits when it closes or
-- if none comes.
return [==[
local uv = vim.uv or vim.loop
local bit = require("bit")
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift, rol, tobit = bit.lshift, bit.rshift, bit.rol, bit.tobit

local port = tonumber(vim.env.RT_FIRENVIM_PORT)
local token = vim.env.RT_FIRENVIM_TOKEN
local origin = vim.env.RT_FIRENVIM_ORIGIN
for _, name in ipairs({ "RT_FIRENVIM_BRIDGE", "RT_FIRENVIM_PORT", "RT_FIRENVIM_TOKEN", "RT_FIRENVIM_ORIGIN" }) do
  vim.env[name] = nil
end
vim.g.started_by_riptide = true

local function quit()
  vim.schedule(function() vim.cmd("qall!") end)
end

local function be32(n)
  return string.char(band(rshift(n, 24), 255), band(rshift(n, 16), 255), band(rshift(n, 8), 255), band(n, 255))
end

local function sha1(msg)
  local h = { tobit(0x67452301), tobit(0xEFCDAB89), tobit(0x98BADCFE), tobit(0x10325476), tobit(0xC3D2E1F0) }
  local bits = #msg * 8
  msg = msg .. "\128" .. string.rep("\0", (55 - #msg) % 64) .. be32(math.floor(bits / 2 ^ 32)) .. be32(bits % 2 ^ 32)
  local w = {}
  for i = 1, #msg, 64 do
    for j = 0, 15 do
      local a, b, c, d = msg:byte(i + j * 4, i + j * 4 + 3)
      w[j] = bor(lshift(a, 24), lshift(b, 16), lshift(c, 8), d)
    end
    for j = 16, 79 do
      w[j] = rol(bxor(w[j - 3], w[j - 8], w[j - 14], w[j - 16]), 1)
    end
    local a, b, c, d, e = h[1], h[2], h[3], h[4], h[5]
    for j = 0, 79 do
      local f, k
      if j < 20 then
        f, k = bor(band(b, c), band(bnot(b), d)), 0x5A827999
      elseif j < 40 then
        f, k = bxor(b, c, d), 0x6ED9EBA1
      elseif j < 60 then
        f, k = bor(band(b, c), band(b, d), band(c, d)), 0x8F1BBCDC
      else
        f, k = bxor(b, c, d), 0xCA62C1D6
      end
      e, d, c, b, a = d, c, rol(b, 30), a, tobit(rol(a, 5) + f + e + k + w[j])
    end
    h[1], h[2], h[3], h[4], h[5] = tobit(h[1] + a), tobit(h[2] + b), tobit(h[3] + c), tobit(h[4] + d), tobit(h[5] + e)
  end
  return be32(h[1]) .. be32(h[2]) .. be32(h[3]) .. be32(h[4]) .. be32(h[5])
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    for j = 3, 0, -1 do
      out[#out + 1] = B64:sub(math.floor(n / 64 ^ j) % 64 + 1, math.floor(n / 64 ^ j) % 64 + 1)
    end
    if not c then out[#out] = "=" end
    if not b then out[#out - 1] = "=" end
  end
  return table.concat(out)
end

-- A server frame: unmasked and final.
local function frame(opcode, payload)
  local n = #payload
  if n < 126 then
    return string.char(0x80 + opcode, n) .. payload
  elseif n < 65536 then
    return string.char(0x80 + opcode, 126, rshift(n, 8), band(n, 255)) .. payload
  end
  return string.char(0x80 + opcode, 127, 0, 0, 0, 0) .. be32(n) .. payload
end

-- The first whole frame in `buf`: opcode, payload and what's left, or nil.
local function parse(buf)
  if #buf < 2 then return nil end
  local b1, b2 = buf:byte(1, 2)
  local len, pos = band(b2, 0x7f), 3
  if len == 126 then
    if #buf < 4 then return nil end
    len, pos = buf:byte(3) * 256 + buf:byte(4), 5
  elseif len == 127 then
    if #buf < 10 then return nil end
    len = 0
    for i = 3, 10 do len = len * 256 + buf:byte(i) end
    pos = 11
  end
  local mask
  if band(b2, 0x80) ~= 0 then
    if #buf < pos + 3 then return nil end
    mask = { buf:byte(pos, pos + 3) }
    pos = pos + 4
  end
  if #buf < pos + len - 1 then return nil end
  local payload = buf:sub(pos, pos + len - 1)
  if mask then
    local bytes = { payload:byte(1, -1) }
    for i = 1, #bytes do
      bytes[i] = bxor(bytes[i], mask[(i - 1) % 4 + 1])
    end
    local parts = {}
    for i = 1, #bytes, 4096 do
      parts[#parts + 1] = string.char(unpack(bytes, i, math.min(i + 4095, #bytes)))
    end
    payload = table.concat(parts)
  end
  return band(b1, 0x0f), payload, buf:sub(pos + len)
end

-- The upgrade request's path and lowercased headers.
local function request(text)
  local path = text:match("^GET (%S+) HTTP/1%.1\r\n")
  local headers = {}
  for name, value in text:gmatch("\r\n([^:\r\n]+):%s*([^\r\n]*)") do
    headers[name:lower()] = value
  end
  return path, headers
end

local server = uv.new_tcp()
local waiting = uv.new_timer()

local function on_connection(listen_err)
  if listen_err then return end
  local client = uv.new_tcp()
  server:accept(client)
  -- What the page sent before nvim's socket was connected.
  local buf, upgraded, rpc, queued = "", false, nil, {}
  local function close()
    if not client:is_closing() then client:close() end
    quit()
  end
  client:read_start(function(read_err, data)
    if read_err or not data then return close() end
    buf = buf .. data
    if not upgraded then
      local head = buf:match("^(.-\r\n\r\n)")
      if not head then return end
      buf = buf:sub(#head + 1)
      local path, headers = request(head)
      local key = headers["sec-websocket-key"]
      local good = path == "/?token=" .. token and key
        and (headers["upgrade"] or ""):lower() == "websocket"
        and (not origin or headers["origin"] == origin)
      if not good then
        client:write("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        client:shutdown(function() client:close() end)
        return
      end
      server:close()
      waiting:stop()
      upgraded = true
      client:write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        .. "Sec-WebSocket-Accept: " .. base64(sha1(key .. "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")) .. "\r\n\r\n")
      rpc = uv.new_pipe(false)
      vim.schedule(function()
        rpc:connect(vim.fn.serverstart(), function(connect_err)
          if connect_err then return close() end
          for _, payload in ipairs(queued) do rpc:write(payload) end
          queued = nil
          rpc:read_start(function(rpc_err, out)
            if rpc_err or not out then return close() end
            client:write(frame(2, out))
          end)
        end)
      end)
    end
    while true do
      local opcode, payload, rest = parse(buf)
      if not opcode then return end
      buf = rest
      if opcode == 8 then
        return close()
      elseif opcode == 9 then
        client:write(frame(10, payload))
      elseif opcode <= 2 and #payload > 0 then
        if queued then table.insert(queued, payload) else rpc:write(payload) end
      end
    end
  end)
end

local ok, err = server:bind("127.0.0.1", port)
if ok then ok, err = server:listen(1, on_connection) end
if not ok then
  io.stderr:write("can't listen on port " .. tostring(port) .. ": " .. tostring(err) .. "\n")
  vim.cmd("cquit 75")
end
waiting:start(20000, 0, quit)

-- The page calls this once attached: edit `text` in a file named `name`,
-- in `filetype` if one was kept for the field, and send the text back over
-- `channel` on every write.
_G.RtFirenvim = {}
function RtFirenvim.start(text, name, line, col, channel, filetype)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/" .. name
  vim.fn.writefile(vim.split(text, "\n", { plain = true }), file)
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  pcall(vim.api.nvim_win_set_cursor, 0, { line, col })
  local buf = vim.api.nvim_get_current_buf()
  -- The filetype nvim found itself; changing it tells the page, so the
  -- plugin keeps the new one for the field (or forgets it, back at this).
  local detected = vim.bo[buf].filetype
  if filetype and filetype ~= "" then vim.bo[buf].filetype = filetype end
  vim.api.nvim_create_autocmd("FileType", {
    buffer = buf,
    callback = function(args)
      vim.rpcnotify(channel, "rt_firenvim_filetype", args.match, detected)
    end,
  })
  -- Writes sent, and the last one the page has (it sets g:rt_firenvim_got).
  local sent = 0
  vim.api.nvim_create_autocmd("BufWritePost", {
    buffer = buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      sent = sent + 1
      vim.rpcnotify(channel, "rt_firenvim_write", table.concat(lines, "\n"), sent)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      -- :wq quits right after writing; let the page get the text first.
      vim.wait(2000, function() return (vim.g.rt_firenvim_got or 0) >= sent end, 10)
      vim.fn.delete(dir, "rf")
    end,
  })
end
]==]
