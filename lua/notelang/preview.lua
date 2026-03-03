local M = {}

local parser   = require("notelang.parser")
local renderer = require("notelang.renderer")
local config   = require("notelang").config

local preview_path    = nil
local edit_server     = nil   -- uv TCP server handle
local edit_port       = 0     -- actual bound port (0 = not running)
local edit_bufnr      = nil   -- buffer being edited
local last_write_time = 0     -- epoch seconds of last HTML write

-- ── Helpers ───────────────────────────────────────────────────────────────────

function M.get_preview_path()
  if not preview_path then
    preview_path = vim.fn.tempname() .. ".html"
  end
  return preview_path
end

-- ── JSON helpers (minimal, only what we need) ────────────────────────────────

-- Parse a flat JSON array of strings: ["a","b","c"]
local function parse_json_string_array(s)
  local result = {}
  -- Strip surrounding [ ]
  local inner = s:match("^%s*%[(.*)%]%s*$")
  if not inner then return result end
  -- Iterate quoted strings
  local pos = 1
  while pos <= #inner do
    local qs, qe = inner:find('"', pos, true)
    if not qs then break end
    -- Find closing quote, respecting \" escapes
    local val = ""
    local i = qs + 1
    while i <= #inner do
      local ch = inner:sub(i, i)
      if ch == "\\" then
        local nc = inner:sub(i + 1, i + 1)
        if nc == '"' then val = val .. '"'; i = i + 2
        elseif nc == "\\" then val = val .. "\\"; i = i + 2
        elseif nc == "n"  then val = val .. "\n"; i = i + 2
        elseif nc == "t"  then val = val .. "\t"; i = i + 2
        else val = val .. nc; i = i + 2
        end
      elseif ch == '"' then
        qe = i; break
      else
        val = val .. ch; i = i + 1
      end
    end
    table.insert(result, val)
    pos = (qe or i) + 1
  end
  return result
end

-- Extract a number field from a flat JSON object string: "key": 123
local function json_num(s, key)
  local v = s:match('"' .. key .. '"%s*:%s*(-?%d+)')
  return tonumber(v)
end

-- Extract a string field from a flat JSON object: "key": "value"
local function json_str(s, key)
  local v = s:match('"' .. key .. '"%s*:%s*"([^"]*)"')
  return v
end

-- Extract the cells array from the JSON body (last field, may span rest of string)
local function json_cells(s)
  local arr_start = s:find('"cells"%s*:%s*%[')
  if not arr_start then return {} end
  local bracket_pos = s:find("%[", arr_start)
  -- Find matching ]
  local depth = 0
  local i = bracket_pos
  while i <= #s do
    local ch = s:sub(i, i)
    if ch == "[" then depth = depth + 1
    elseif ch == "]" then
      depth = depth - 1
      if depth == 0 then
        return parse_json_string_array(s:sub(bracket_pos, i))
      end
    end
    i = i + 1
  end
  return {}
end

-- ── Table serialisation back to .note source ─────────────────────────────────

-- Rebuild the lines for a pipe-syntax table given cells and col count.
-- has_header=true  → first row becomes header with | --- | separator
-- has_header=false → all rows are plain data rows (no separator)
local function build_pipe_lines(cells, cols, has_header)
  local lines = {}
  local total = #cells
  local rows  = math.ceil(total / cols)

  if has_header then
    -- Header row
    local hdr = "|"
    for ci = 1, cols do
      local cell = cells[ci] or ""
      hdr = hdr .. " " .. cell .. " |"
    end
    table.insert(lines, hdr)
    -- Separator
    local sep = "|"
    for _ = 1, cols do sep = sep .. " --- |" end
    table.insert(lines, sep)
    -- Body rows
    for ri = 2, rows do
      local row = "|"
      for ci = 1, cols do
        local idx = (ri - 1) * cols + ci
        local cell = cells[idx] or ""
        row = row .. " " .. cell .. " |"
      end
      table.insert(lines, row)
    end
  else
    -- All rows are plain data (no separator)
    for ri = 1, rows do
      local row = "|"
      for ci = 1, cols do
        local idx = (ri - 1) * cols + ci
        local cell = cells[idx] or ""
        row = row .. " " .. cell .. " |"
      end
      table.insert(lines, row)
    end
  end
  return lines
end

-- Rebuild the lines for a @table(R,C){...} block given cells.
local function build_kw_lines(cells, rows, cols)
  local lines = {}
  table.insert(lines, "@table(" .. rows .. ", " .. cols .. ") {")
  for ri = 1, rows do
    local row_parts = {}
    for ci = 1, cols do
      local idx = (ri - 1) * cols + ci
      table.insert(row_parts, cells[idx] or "")
    end
    table.insert(lines, table.concat(row_parts, ", "))
  end
  table.insert(lines, "}")
  return lines
end

-- Rebuild the lines for a table(name,C,R[,true]){...} block given cells.
-- Note: newlines in cells are replaced with spaces (multi-line content not preserved in CSV format)
local function build_def_lines(cells, name, cols, rows, has_header)
  local lines = {}
  local hdr_suffix = has_header and ", true" or ""
  table.insert(lines, "table(" .. name .. ", " .. cols .. ", " .. rows .. hdr_suffix .. ") {")
  for ri = 1, rows do
    local row_parts = {}
    for ci = 1, cols do
      local idx = (ri - 1) * cols + ci
      local cell = (cells[idx] or ""):gsub("\n", " "):gsub("\r", "")
      table.insert(row_parts, cell)
    end
    table.insert(lines, table.concat(row_parts, ", "))
  end
  table.insert(lines, "}")
  return lines
end

-- Rebuild a .name(row,col){...} cell fill block.
local function build_cell_fill_lines(table_name, row, col, content)
  local lines = {}
  table.insert(lines, "." .. table_name .. "(" .. row .. ", " .. col .. ") {")
  -- Split content by \n for each line in the block
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  table.insert(lines, "}")
  return lines
end

-- ── HTTP micro-server ─────────────────────────────────────────────────────────

-- handle_save: called from libuv callback; all vim.api calls go through vim.schedule.
-- Returns immediately (true/"ok") and does the actual write asynchronously.
local function handle_save(body_json)
  local start_line = json_num(body_json, "start_line")
  local end_line   = json_num(body_json, "end_line")
  local ttype      = json_str(body_json, "table_type")
  local rows       = json_num(body_json, "rows") or 0
  local cols       = json_num(body_json, "cols") or 0
  local cells      = json_cells(body_json)
  local name       = json_str(body_json, "table_name") or json_str(body_json, "name") or ""
  local row        = json_num(body_json, "row") or 0
  local col        = json_num(body_json, "col") or 0
  local has_header = json_str(body_json, "has_header") == "true"

  if not start_line or not end_line or not ttype then
    return false, "missing fields"
  end

  local new_lines
  if ttype == "pipe" then
    if cols <= 0 then cols = 1 end
    new_lines = build_pipe_lines(cells, cols, has_header)
  elseif ttype == "kw" then
    new_lines = build_kw_lines(cells, rows, cols)
  elseif ttype == "def" then
    new_lines = build_def_lines(cells, name, cols, rows, has_header)
  elseif ttype == "cell_fill" then
    new_lines = build_cell_fill_lines(name, row, col, cells[1] or "")
  else
    return false, "unknown table type: " .. tostring(ttype)
  end

  local buf = edit_bufnr
  -- Schedule all vim.api calls on the main thread
  vim.schedule(function()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      vim.notify("[noteLang] Could not save table: buffer no longer valid", vim.log.levels.WARN)
      return
    end
    -- Replace lines in buffer (0-indexed API: start inclusive, end exclusive)
    vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line, false, new_lines)
    -- Save the buffer
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent! write")
    end)
  end)
  return true, "ok"
end

-- Minimal HTTP/1.1 request parser; returns method, path, body string or nil.
local function parse_http(data)
  local header_end = data:find("\r\n\r\n", 1, true)
  if not header_end then return nil end
  local headers = data:sub(1, header_end - 1)
  local body    = data:sub(header_end + 4)
  local method, path = headers:match("^(%u+) (/[^ ]*) HTTP")
  local content_len  = tonumber(headers:match("[Cc]ontent%-[Ll]ength: (%d+)"))
  if content_len and #body < content_len then
    return nil  -- wait for more data
  end
  return method, path, body
end

local CORS_HEADERS = table.concat({
  "Access-Control-Allow-Origin: *",
  "Access-Control-Allow-Methods: POST, OPTIONS",
  "Access-Control-Allow-Headers: Content-Type",
}, "\r\n")

local function http_response(status, body)
  return string.format(
    "HTTP/1.1 %s\r\nContent-Type: text/plain\r\nContent-Length: %d\r\n%s\r\n\r\n%s",
    status, #body, CORS_HEADERS, body
  )
end

local function start_edit_server(buf)
  if edit_server then return end
  edit_bufnr = buf

  local uv = vim.loop
  local server = uv.new_tcp()
  -- Bind to loopback on a random port
  server:bind("127.0.0.1", 0)
  server:listen(128, function(err)
    if err then return end
    local client = uv.new_tcp()
    server:accept(client)
    local buffer = ""
    client:read_start(function(read_err, chunk)
      if read_err or not chunk then
        client:close()
        return
      end
      buffer = buffer .. chunk
      local method, path, body = parse_http(buffer)
      if not method then return end  -- wait for more data
      buffer = ""

      local response
      local clean_path = path and path:match("^([^?#]*)") or "/"
      if method == "OPTIONS" then
        response = http_response("204 No Content", "")
      elseif method == "POST" and clean_path == "/save-table" then
        local ok, msg = handle_save(body)
        if ok then
          response = http_response("200 OK", "saved")
        else
          response = http_response("400 Bad Request", msg or "error")
        end
      elseif (method == "GET" or method == "HEAD") and clean_path == "/" then
        local last_mod = os.date("!%a, %d %b %Y %H:%M:%S GMT", last_write_time)
        local common_hdrs = "Content-Type: text/html; charset=utf-8\r\nLast-Modified: " .. last_mod .. "\r\nCache-Control: no-cache\r\n" .. CORS_HEADERS
        if method == "HEAD" then
          response = "HTTP/1.1 200 OK\r\n" .. common_hdrs .. "\r\n\r\n"
        else
          local pp = preview_path
          local fh = pp and io.open(pp, "r")
          local content = fh and fh:read("*a") or "<html><body>Loading&hellip;</body></html>"
          if fh then fh:close() end
          response = "HTTP/1.1 200 OK\r\n" .. common_hdrs .. "\r\nContent-Length: " .. #content .. "\r\n\r\n" .. content
        end
      else
        response = http_response("404 Not Found", "not found")
      end

      client:write(response, function()
        client:shutdown()
        client:close()
      end)
    end)
  end)

  -- Get the actual bound port
  local addr = server:getsockname()
  edit_port   = addr and addr.port or 0
  edit_server = server
end

local function stop_edit_server()
  if edit_server then
    edit_server:close()
    edit_server = nil
    edit_port   = 0
    edit_bufnr  = nil
  end
end

-- ── Core operations ───────────────────────────────────────────────────────────

--- Read buffer, parse, render, and write the HTML preview file.
function M.update(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text  = table.concat(lines, "\n")

  local nodes = parser.parse(text)
  local body  = renderer.render(nodes)

  -- Use the buffer name as the page title
  local title = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t:r")
  if title == "" then title = "noteLang Preview" end

  local cfg = require("notelang").config
  local html = renderer.render_page(title, body, cfg.refresh_interval, edit_port)

  local path = M.get_preview_path()
  local f = io.open(path, "w")
  if not f then
    vim.notify("[noteLang] Could not write preview file: " .. path, vim.log.levels.ERROR)
    return
  end
  f:write(html)
  f:close()
  last_write_time = os.time()
end

--- Open the preview in the system browser (HTTP if server is running, file:// fallback).
function M.open()
  local url = (edit_port > 0)
    and ("http://127.0.0.1:" .. edit_port .. "/")
    or  M.get_preview_path()
  local cmd
  if vim.fn.has("mac") == 1 then
    cmd = "open"
  elseif vim.fn.has("win32") == 1 then
    cmd = "start"
  else
    cmd = "xdg-open"
  end
  vim.fn.jobstart({ cmd, url }, { detach = true })
end

--- Update preview and open browser; notify user.
function M.start(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  start_edit_server(buf)
  M.update(buf)
  M.open()
  local url = (edit_port > 0)
    and ("http://127.0.0.1:" .. edit_port .. "/")
    or  M.get_preview_path()
  vim.notify("[noteLang] Preview opened: " .. url, vim.log.levels.INFO)
end

--- Delete temp file and reset path.
function M.stop()
  stop_edit_server()
  if preview_path and vim.fn.filereadable(preview_path) == 1 then
    vim.fn.delete(preview_path)
    vim.notify("[noteLang] Preview stopped.", vim.log.levels.INFO)
  else
    vim.notify("[noteLang] No active preview.", vim.log.levels.WARN)
  end
  preview_path = nil
end

return M
