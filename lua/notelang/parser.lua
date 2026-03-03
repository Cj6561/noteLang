local M = {}

-- ── Inline processing ─────────────────────────────────────────────────────────

local function html_escape(s)
  s = s:gsub("&", "&amp;")
  s = s:gsub("<", "&lt;")
  s = s:gsub(">", "&gt;")
  return s
end

-- Process inline markup: bold, italic, code, strike, link, image
function M.inline(s)
  -- Stash backtick spans to protect them from other substitutions
  local stash = {}
  local idx = 0
  s = s:gsub("`([^`]+)`", function(code)
    idx = idx + 1
    stash[idx] = "<code>" .. html_escape(code) .. "</code>"
    return "\x00" .. idx .. "\x00"
  end)

  -- Stash raw HTML tags so they survive html_escape (uses \x02/\x03 sentinels)
  local html_stash = {}
  local html_idx = 0
  s = s:gsub("</?%w[^>]*>", function(tag)
    html_idx = html_idx + 1
    html_stash[html_idx] = tag
    return "\x02" .. html_idx .. "\x03"
  end)

  -- Symbol replacements (must happen before html_escape so raw < and > are present).
  -- IMPORTANT: `-` is a magic quantifier in Lua patterns; use `%-` to match a literal dash.
  --
  -- Step 1: stash escape sequences so they survive the auto-replacements below.
  s = s:gsub("\\<%->",   "\x10")  -- \<->  → literal <->
  s = s:gsub("\\<=>",    "\x11")  -- \<=>  → literal <=>
  s = s:gsub("\\==>",    "\x12")  -- \==>  → literal ==>
  s = s:gsub("\\<==",    "\x13")  -- \<==  → literal <==
  s = s:gsub("\\%-%->",  "\x14")  -- \-->  → literal -->
  s = s:gsub("\\<%-%-",  "\x15")  -- \<--  → literal <--
  s = s:gsub("\\>=",     "\x16")  -- \>=   → literal >=
  s = s:gsub("\\<=",     "\x17")  -- \<=   → literal <=

  -- Step 2: auto-replacements — sentinels survive html_escape, expanded to spans in step 4.
  local sym_stash = {}
  local sym_idx   = 0
  local function sym(c)   -- nl-sym (1.25em): single-stroke arrows and misc symbols
    sym_idx = sym_idx + 1
    sym_stash[sym_idx] = c
    return "\x19" .. sym_idx .. "\x19"
  end

  local sym2_stash = {}
  local sym2_idx   = 0
  local function sym2(c)  -- nl-sym2 (2.0em): double-stroke = arrows
    sym2_idx = sym2_idx + 1
    sym2_stash[sym2_idx] = c
    return "\x1a" .. sym2_idx .. "\x1a"
  end

  s = s:gsub("<%->",   sym("↔"))
  s = s:gsub("<=>",    sym2("⇔"))
  s = s:gsub("==>",    sym2("⇒"))
  s = s:gsub("<==",    sym2("⇐"))
  s = s:gsub("%-%->",  sym("→"))
  s = s:gsub("<%-%-",  sym("←"))
  s = s:gsub(">=",     "≥")
  s = s:gsub("<=",     "≤")
  s = s:gsub("\\d%^",  sym("⌄"))
  s = s:gsub("\\%(e",  "∈")

  -- Step 3: HTML-escape (\x10–\x19 sentinels are not HTML-special and survive intact)
  s = html_escape(s)

  -- Step 4: restore escaped sequences as their HTML-safe literal forms
  s = s:gsub("\x10", "&lt;->")
  s = s:gsub("\x11", "&lt;=>")
  s = s:gsub("\x12", "==>")
  s = s:gsub("\x13", "&lt;==")
  s = s:gsub("\x14", "-->")
  s = s:gsub("\x15", "&lt;--")
  s = s:gsub("\x16", "&gt;=")
  s = s:gsub("\x17", "&lt;=")
  -- Restore symbols as sized spans
  s = s:gsub("\x19(%d+)\x19", function(n)
    return '<span class="nl-sym">' .. sym_stash[tonumber(n)] .. '</span>'
  end)
  s = s:gsub("\x1a(%d+)\x1a", function(n)
    return '<span class="nl-sym2">' .. sym2_stash[tonumber(n)] .. '</span>'
  end)

  -- Stash escaped carets so they don't trigger superscript matching
  local caret_stash = {}
  local caret_idx = 0
  s = s:gsub("\\%^", function()
    caret_idx = caret_idx + 1
    caret_stash[caret_idx] = "^"
    return "\x04" .. caret_idx .. "\x04"
  end)

  -- Superscripts: all four combinations of (paren|word)^(paren|word)
  -- (...)^(...) — parens on both sides
  s = s:gsub("(%b())%^(%b())", function(base, exp)
    return base .. "<sup>" .. exp:sub(2, -2) .. "</sup>"
  end)
  -- (...)^word — parens on base only
  s = s:gsub("(%b())%^([%w_%+%-%.]+)", function(base, exp)
    return base .. "<sup>" .. exp .. "</sup>"
  end)
  -- word^(...) — parens on exponent only
  s = s:gsub("([%w_%.]+)%^(%b())", function(base, exp)
    return base .. "<sup>" .. exp:sub(2, -2) .. "</sup>"
  end)
  -- word^word — no parens
  s = s:gsub("([%w_%.]+)%^([%w_%+%-%.]+)", "%1<sup>%2</sup>")

  -- Restore escaped carets as literal ^
  s = s:gsub("\x04(%d+)\x04", function(n)
    return caret_stash[tonumber(n)]
  end)

  -- Images before links (both share [...](...) syntax)
  s = s:gsub("!%[(.-)%]%((.-)%)", function(alt, url)
    return '<img src="' .. url .. '" alt="' .. alt .. '">'
  end)

  -- Links
  s = s:gsub("%[(.-)%]%((.-)%)", function(text, url)
    return '<a href="' .. url .. '">' .. text .. "</a>"
  end)

  -- Stash escaped asterisks so they don't trigger bold/italic matching
  local esc_stash = {}
  local esc_idx = 0
  s = s:gsub("\\%*", function()
    esc_idx = esc_idx + 1
    esc_stash[esc_idx] = "*"
    return "\x01" .. esc_idx .. "\x01"
  end)

  -- Bold (** … **)
  s = s:gsub("%*%*(.-)%*%*", "<strong>%1</strong>")

  -- Italic (* … *) — must come after bold
  s = s:gsub("%*(.-)%*", "<em>%1</em>")

  -- Strikethrough (~~ … ~~)
  s = s:gsub("~~(.-)~~", "<del>%1</del>")

  -- Restore escaped asterisks as literal *
  s = s:gsub("\x01(%d+)\x01", function(n)
    return esc_stash[tonumber(n)]
  end)

  -- Restore stashed code spans
  s = s:gsub("\x00(%d+)\x00", function(n)
    return stash[tonumber(n)]
  end)

  -- Restore stashed HTML tags
  s = s:gsub("\x02(%d+)\x03", function(n)
    return html_stash[tonumber(n)]
  end)

  return s
end

-- ── List helpers ──────────────────────────────────────────────────────────────

local function get_indent(line)
  local spaces = line:match("^(%s*)")
  local count = 0
  for ch in spaces:gmatch(".") do
    if ch == "\t" then
      count = count + 2
    else
      count = count + 1
    end
  end
  return count
end

-- Returns true if line is a list item (bullet or ordered)
local function is_list_item(line)
  return line:match("^%s*[-*]%s") or line:match("^%s*%d+%.%s")
end

local function is_ordered(line)
  return line:match("^%s*%d+%.%s") ~= nil
end

-- Parse a run of list item lines (and their indented continuations) starting
-- at lines[i] into a nested list node.
-- Returns the node and the next index to process.
local function parse_list_items(lines, i, min_indent, ordered)
  local items = {}
  while i <= #lines do
    local line = lines[i]
    local indent = get_indent(line)
    if indent < min_indent then
      break
    end
    if not is_list_item(line) then
      break
    end
    -- Strip the bullet/number
    local text = line:match("^%s*[-*]%s+(.*)") or line:match("^%s*%d+%.%s+(.*)")
    local item = { text = text, children = nil }
    i = i + 1
    -- Collect child lines that are more indented
    if i <= #lines then
      local next_indent = get_indent(lines[i])
      if next_indent > indent and is_list_item(lines[i]) then
        local child_ordered = is_ordered(lines[i])
        local child_node, next_i = parse_list_items(lines, i, next_indent, child_ordered)
        item.children = child_node
        i = next_i
      end
    end
    table.insert(items, item)
  end
  return { type = "list", ordered = ordered, items = items }, i
end

-- ── Main parser ───────────────────────────────────────────────────────────────

function M.parse(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end

  local nodes = {}
  local i = 1

  while i <= #lines do
    local line = lines[i]

    -- Blank line
    if line:match("^%s*$") then
      i = i + 1

    -- Horizontal rule
    elseif line:match("^---+%s*$") then
      table.insert(nodes, { type = "hr" })
      i = i + 1

    -- Heading
    elseif line:match("^######%s") then
      table.insert(nodes, { type = "heading", level = 6, text = line:match("^######%s+(.*)") })
      i = i + 1
    elseif line:match("^#####%s") then
      table.insert(nodes, { type = "heading", level = 5, text = line:match("^#####%s+(.*)") })
      i = i + 1
    elseif line:match("^####%s") then
      table.insert(nodes, { type = "heading", level = 4, text = line:match("^####%s+(.*)") })
      i = i + 1
    elseif line:match("^###%s") then
      table.insert(nodes, { type = "heading", level = 3, text = line:match("^###%s+(.*)") })
      i = i + 1
    elseif line:match("^##%s") then
      table.insert(nodes, { type = "heading", level = 2, text = line:match("^##%s+(.*)") })
      i = i + 1
    elseif line:match("^#%s") then
      table.insert(nodes, { type = "heading", level = 1, text = line:match("^#%s+(.*)") })
      i = i + 1

    -- Blockquote
    elseif line:match("^>%s") then
      local bq_lines = {}
      while i <= #lines and lines[i]:match("^>%s?") do
        table.insert(bq_lines, lines[i]:match("^>%s?(.*)"))
        i = i + 1
      end
      local inner = M.parse(table.concat(bq_lines, "\n"))
      table.insert(nodes, { type = "blockquote", children = inner })

    -- Fenced code block
    elseif line:match("^```") then
      local lang = line:match("^```(%w*)") or ""
      i = i + 1
      local code_lines = {}
      while i <= #lines and not lines[i]:match("^```%s*$") do
        table.insert(code_lines, lines[i])
        i = i + 1
      end
      i = i + 1 -- consume closing ```
      table.insert(nodes, { type = "code_block", lang = lang, code = table.concat(code_lines, "\n") })

    -- table.name(col, row) { ... } — fill a cell using table.name prefix syntax
    elseif line:match("^table%.%w+%s*%(") then
      local name, col_s, row_s = line:match("^table%.(%w+)%s*%(%s*(%d+)%s*,%s*(%d+)%s*%)")
      local col_n = tonumber(col_s) or 0
      local row_n = tonumber(row_s) or 0
      local start_line = i
      i = i + 1
      local content_lines = {}
      while i <= #lines and not lines[i]:match("^}%s*$") do
        table.insert(content_lines, lines[i])
        i = i + 1
      end
      local end_line = i
      i = i + 1 -- consume closing }
      table.insert(nodes, {
        type       = "cell_fill",
        table_name = name,
        row        = row_n,
        col        = col_n,
        content    = table.concat(content_lines, "\n"),
        start_line = start_line,
        end_line   = end_line,
      })

    -- table(name[, cols[, rows]][, true]) { ... } — named object-oriented table definition
    -- cols and rows are optional; omitting them enables dynamic sizing from cell_fill indices
    elseif line:match("^table%s*%(") then
      -- Try matching: table(name, cols, rows[, ...])
      local name, cols_s, rows_s = line:match("^table%s*%(%s*(%w+)%s*,%s*(%d+)%s*,%s*(%d+)%s*[,)]")
      if not name then
        -- Try: table(name, cols[, ...])
        name, cols_s = line:match("^table%s*%(%s*(%w+)%s*,%s*(%d+)%s*[,)]")
      end
      if not name then
        -- Try: table(name)
        name = line:match("^table%s*%(%s*(%w+)%s*%)")
      end
      local cols_n = tonumber(cols_s) or 0  -- 0 = dynamic
      local rows_n = tonumber(rows_s) or 0  -- 0 = dynamic
      -- Optional 4th arg: true = first row is a bold header
      local has_header_s = line:match("^table%s*%(%s*%w+%s*,%s*%d+%s*,%s*%d+%s*,%s*(%a+)%s*%)")
      local has_header = (has_header_s == "true")
      local start_line = i
      local end_line = i
      local cells = {}
      i = i + 1
      if line:match("{") then
        local block_lines = {}
        while i <= #lines and not lines[i]:match("^}%s*$") do
          table.insert(block_lines, lines[i])
          i = i + 1
        end
        end_line = i
        i = i + 1 -- consume closing }
        -- Parse CSV cell data from block (skip comment lines)
        for _, bl in ipairs(block_lines) do
          if not bl:match("^%s*//") then
            for cell in (bl .. ","):gmatch("([^,]*),") do
              table.insert(cells, cell:match("^%s*(.-)%s*$"))
            end
          end
        end
      end
      -- Only pre-fill cells when both dims are known; dynamic tables expand in renderer
      if cols_n > 0 and rows_n > 0 then
        local total = rows_n * cols_n
        while #cells < total do table.insert(cells, "") end
      end
      table.insert(nodes, {
        type       = "table_def",
        name       = name,
        cols       = cols_n,
        rows       = rows_n,
        cells      = cells,
        has_header = has_header,
        start_line = start_line,
        end_line   = end_line,
      })

    -- .name(col, row) { ... } — fill a specific cell in a named table
    elseif line:match("^%.%w+%s*%(") then
      local name, col_s, row_s = line:match("^%.(%w+)%s*%(%s*(%d+)%s*,%s*(%d+)%s*%)")
      local col_n = tonumber(col_s) or 0
      local row_n = tonumber(row_s) or 0
      local start_line = i
      i = i + 1
      local content_lines = {}
      while i <= #lines and not lines[i]:match("^}%s*$") do
        table.insert(content_lines, lines[i])
        i = i + 1
      end
      local end_line = i
      i = i + 1 -- consume closing }
      local content = table.concat(content_lines, "\n")
      table.insert(nodes, {
        type       = "cell_fill",
        table_name = name,
        row        = row_n,
        col        = col_n,
        content    = content,
        start_line = start_line,
        end_line   = end_line,
      })

    -- @table([cols[, rows]]) { ... } keyword table
    elseif line:match("^@table%s*%(") then
      local cols_s, rows_s = line:match("^@table%s*%(%s*(%d+)%s*,%s*(%d+)%s*%)")
      local cols_n = tonumber(cols_s) or 0
      local rows_n = tonumber(rows_s) or 0
      local start_line = i  -- 1-based line number of opening line
      i = i + 1
      local block_lines = {}
      while i <= #lines and not lines[i]:match("^}%s*$") do
        table.insert(block_lines, lines[i])
        i = i + 1
      end
      local end_line = i  -- 1-based line number of closing }
      i = i + 1 -- consume closing }
      -- Parse CSV cell data from block (skip comment lines starting with //)
      local cells = {}
      for _, bl in ipairs(block_lines) do
        if not bl:match("^%s*//") then
          for cell in (bl .. ","):gmatch("([^,]*),") do
            table.insert(cells, cell:match("^%s*(.-)%s*$"))
          end
        end
      end
      -- Resolve dynamic dimensions from cell count when not specified
      if cols_n == 0 and rows_n == 0 then
        cols_n = #cells
        rows_n = 1
      elseif cols_n == 0 then
        cols_n = math.ceil(#cells / math.max(rows_n, 1))
      elseif rows_n == 0 then
        rows_n = math.ceil(#cells / math.max(cols_n, 1))
      end
      cols_n = math.max(cols_n, 1)
      rows_n = math.max(rows_n, 1)
      local total = rows_n * cols_n
      while #cells < total do table.insert(cells, "") end
      table.insert(nodes, {
        type       = "table_kw",
        rows       = rows_n,
        cols       = cols_n,
        cells      = cells,
        start_line = start_line,
        end_line   = end_line,
      })

    -- @graph / @flow / @mindmap / @seq (diagram blocks)
    elseif line:match("^@(%w+)%s*{") then
      local keyword = line:match("^@(%w+)")
      i = i + 1
      local block_lines = {}
      while i <= #lines and not lines[i]:match("^}%s*$") do
        table.insert(block_lines, lines[i])
        i = i + 1
      end
      i = i + 1 -- consume closing }
      table.insert(nodes, {
        type = "graph",
        keyword = keyword,
        content = table.concat(block_lines, "\n"),
      })

    -- Table (pipe syntax)
    elseif line:match("^|") then
      local tbl_lines = {}
      local start_line = i
      while i <= #lines and lines[i]:match("^|") do
        table.insert(tbl_lines, lines[i])
        i = i + 1
      end
      table.insert(nodes, { type = "table", lines = tbl_lines, start_line = start_line, end_line = i - 1 })

    -- Definition list  :: term :: definition
    elseif line:match("^::%s") then
      local term, def = line:match("^::%s+(.-)%s+::%s+(.*)")
      if term then
        table.insert(nodes, { type = "definition", term = term, def = def })
      end
      i = i + 1

    -- List
    elseif is_list_item(line) then
      local ordered = is_ordered(line)
      local indent = get_indent(line)
      local node, next_i = parse_list_items(lines, i, indent, ordered)
      table.insert(nodes, node)
      i = next_i

    -- Paragraph (fallback)
    else
      local para_lines = {}
      while i <= #lines and not lines[i]:match("^%s*$") do
        local l = lines[i]
        -- Stop if a block-level element starts
        if l:match("^#") or l:match("^>") or l:match("^```") or
           l:match("^@%w+%s*{") or l:match("^@table%s*%(") or
           l:match("^table%.%w+%s*%(") or l:match("^table%s*%(") or l:match("^%.%w+%s*%(") or
           l:match("^|") or l:match("^::%s") or
           l:match("^---+%s*$") or is_list_item(l) then
          break
        end
        table.insert(para_lines, l)
        i = i + 1
      end
      if #para_lines > 0 then
        table.insert(nodes, { type = "paragraph", text = table.concat(para_lines, "\n") })
      else
        i = i + 1  -- skip unrecognized line to avoid infinite loop
      end
    end
  end

  return nodes
end

return M
