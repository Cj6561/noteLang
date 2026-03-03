local parser = require("notelang.parser")
local M = {}

-- ── Per-node renderers ────────────────────────────────────────────────────────

local function render_node(node)
  if node.type == "heading" then
    local tag = "h" .. node.level
    return "<" .. tag .. ">" .. parser.inline(node.text) .. "</" .. tag .. ">\n"

  elseif node.type == "hr" then
    return "<hr>\n"

  elseif node.type == "paragraph" then
    local html = parser.inline(node.text):gsub("\n", "<br>\n")
    return "<p>" .. html .. "</p>\n"

  elseif node.type == "blockquote" then
    local inner = M.render(node.children)
    return "<blockquote>\n" .. inner .. "</blockquote>\n"

  elseif node.type == "code_block" then
    local lang_attr = node.lang ~= "" and (' class="language-' .. node.lang .. '"') or ""
    -- HTML-escape the code content
    local escaped = node.code:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    return "<pre><code" .. lang_attr .. ">" .. escaped .. "</code></pre>\n"

  elseif node.type == "graph" then
    local kw = node.keyword
    local mermaid_src

    if kw == "graph" then
      -- Raw Mermaid pass-through
      mermaid_src = node.content

    elseif kw == "flow" then
      -- Auto-prefix with graph LR
      mermaid_src = "graph LR\n" .. node.content

    elseif kw == "mindmap" then
      mermaid_src = "mindmap\n" .. node.content

    elseif kw == "seq" then
      mermaid_src = "sequenceDiagram\n" .. node.content

    elseif kw == "table" then
      -- CSV → HTML table (first row = header)
      local rows = {}
      for row_line in (node.content .. "\n"):gmatch("([^\n]*)\n") do
        if row_line:match("%S") then
          local cells = {}
          for cell in (row_line .. ","):gmatch("([^,]*),") do
            table.insert(cells, cell:match("^%s*(.-)%s*$"))
          end
          table.insert(rows, cells)
        end
      end
      if #rows == 0 then return "" end
      local out = "<table>\n<thead><tr>"
      for _, cell in ipairs(rows[1]) do
        out = out .. "<th>" .. parser.inline(cell) .. "</th>"
      end
      out = out .. "</tr></thead>\n<tbody>\n"
      for j = 2, #rows do
        out = out .. "<tr>"
        for _, cell in ipairs(rows[j]) do
          out = out .. "<td>" .. parser.inline(cell) .. "</td>"
        end
        out = out .. "</tr>\n"
      end
      return out .. "</tbody>\n</table>\n"
    else
      mermaid_src = node.content
    end

    if mermaid_src then
      -- HTML-escape so the browser doesn't mangle '<', '>', '&' before mermaid reads textContent
      local escaped = mermaid_src:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
      return '<div class="mermaid">\n' .. escaped .. "\n</div>\n"
    end
    return ""

  elseif node.type == "table" then
    -- Pipe-syntax table
    local tlines = node.lines
    if #tlines == 0 then return "" end

    -- Detect separator row (| --- | --- |); its presence determines whether
    -- the preceding row is a bold header or just another data row.
    local header_row = nil
    local body_rows  = {}
    local sep_idx    = nil
    for idx, tl in ipairs(tlines) do
      if tl:match("^|%s*[-:]+[-| :]*|") then
        sep_idx    = idx
        header_row = tlines[idx - 1]
        break
      end
    end
    for idx, tl in ipairs(tlines) do
      if sep_idx then
        if idx > sep_idx then table.insert(body_rows, tl) end
      else
        table.insert(body_rows, tl)   -- no separator: every row is a body row
      end
    end

    local function parse_cells(row)
      local cells = {}
      for cell in row:gmatch("|([^|]+)") do
        table.insert(cells, cell:match("^%s*(.-)%s*$"))
      end
      return cells
    end

    local all_rows = {}
    if header_row then table.insert(all_rows, parse_cells(header_row)) end
    for _, row in ipairs(body_rows) do
      table.insert(all_rows, parse_cells(row))
    end
    if #all_rows == 0 then return "" end

    local cols_n     = #all_rows[1]
    local has_header = header_row ~= nil
    local cell_parts = {}
    for _, row in ipairs(all_rows) do
      for _, c in ipairs(row) do
        local escaped = c:gsub("\\", "\\\\"):gsub('"', '\\"')
        table.insert(cell_parts, '"' .. escaped .. '"')
      end
    end
    local cells_json = "[" .. table.concat(cell_parts, ",") .. "]"

    local tbl_id = "tbl_" .. (node.start_line or "0")
    local out = string.format(
      '<table id="%s" class="nl-editable" data-start="%s" data-end="%s" data-type="pipe" data-cols="%d" data-hasheader="%s" data-cells=\'%s\'>\n',
      tbl_id, tostring(node.start_line or 0), tostring(node.end_line or 0),
      cols_n, has_header and "true" or "false", cells_json
    )
    if has_header then
      out = out .. "<thead><tr>"
      for ci, cell in ipairs(all_rows[1]) do
        out = out .. string.format(
          '<th contenteditable="true" data-row="0" data-col="%d">%s</th>',
          ci - 1, parser.inline(cell)
        )
      end
      out = out .. "</tr></thead>\n<tbody>\n"
      for ri = 2, #all_rows do
        out = out .. "<tr>"
        for ci, cell in ipairs(all_rows[ri]) do
          out = out .. string.format(
            '<td contenteditable="true" data-row="%d" data-col="%d">%s</td>',
            ri - 1, ci - 1, parser.inline(cell)
          )
        end
        out = out .. "</tr>\n"
      end
    else
      out = out .. "<tbody>\n"
      for ri = 1, #all_rows do
        out = out .. "<tr>"
        for ci, cell in ipairs(all_rows[ri]) do
          out = out .. string.format(
            '<td contenteditable="true" data-row="%d" data-col="%d">%s</td>',
            ri - 1, ci - 1, parser.inline(cell)
          )
        end
        out = out .. "</tr>\n"
      end
    end
    return out .. "</tbody>\n</table>\n"

  elseif node.type == "table_kw" then
    -- @table(rows,cols){...} keyword table
    local rows_n = node.rows
    local cols_n = node.cols
    local cells  = node.cells

    -- Encode cell data as JSON
    local cell_parts = {}
    for _, c in ipairs(cells) do
      local escaped = c:gsub("\\", "\\\\"):gsub('"', '\\"')
      table.insert(cell_parts, '"' .. escaped .. '"')
    end
    local cells_json = "[" .. table.concat(cell_parts, ",") .. "]"

    local tbl_id = "tbl_" .. (node.start_line or "0")
    local out = string.format(
      '<table id="%s" class="nl-editable" data-start="%s" data-end="%s" data-type="kw" data-rows="%d" data-cols="%d" data-cells=\'%s\'>\n',
      tbl_id, tostring(node.start_line or 0), tostring(node.end_line or 0),
      rows_n, cols_n, cells_json
    )
    -- First row is header
    out = out .. "<thead><tr>"
    for ci = 1, cols_n do
      local cell = cells[ci] or ""
      out = out .. string.format(
        '<th contenteditable="true" data-row="0" data-col="%d">%s</th>',
        ci - 1, parser.inline(cell)
      )
    end
    out = out .. "</tr></thead>\n<tbody>\n"
    for ri = 2, rows_n do
      out = out .. "<tr>"
      for ci = 1, cols_n do
        local idx = (ri - 1) * cols_n + ci
        local cell = cells[idx] or ""
        out = out .. string.format(
          '<td contenteditable="true" data-row="%d" data-col="%d">%s</td>',
          ri - 1, ci - 1, parser.inline(cell)
        )
      end
      out = out .. "</tr>\n"
    end
    return out .. "</tbody>\n</table>\n"

  elseif node.type == "table_def" then
    -- table(name, cols, rows[, true]) { ... } — named object-oriented table
    -- Cells can have newlines which become <br>
    local rows_n     = node.rows
    local cols_n     = node.cols
    local cells      = node.cells
    local tbl_name   = node.name or "table"
    local has_header = node.has_header == true

    -- Helper: process cell content — inline markup, then newlines → <br>
    local function process_cell(content)
      if not content or content == "" then return "" end
      local processed = parser.inline(content)
      processed = processed:gsub("\n", "<br>")
      return processed
    end

    -- Encode cell data as JSON (raw content, not HTML)
    local cell_parts = {}
    for _, c in ipairs(cells) do
      local escaped = (c or ""):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
      table.insert(cell_parts, '"' .. escaped .. '"')
    end
    local cells_json = "[" .. table.concat(cell_parts, ",") .. "]"

    local tbl_id = "tbl_" .. tbl_name
    local out = string.format(
      '<table id="%s" class="nl-editable" data-start="%s" data-end="%s" data-type="def" data-name="%s" data-rows="%d" data-cols="%d" data-hasheader="%s" data-cells=\'%s\'>\n',
      tbl_id, tostring(node.start_line or 0), tostring(node.end_line or 0),
      tbl_name, rows_n, cols_n, has_header and "true" or "false", cells_json
    )
    if has_header then
      out = out .. "<thead><tr>"
      for ci = 1, cols_n do
        local cell = cells[ci] or ""
        out = out .. string.format(
          '<th contenteditable="true" data-row="0" data-col="%d">%s</th>',
          ci - 1, process_cell(cell)
        )
      end
      out = out .. "</tr></thead>\n<tbody>\n"
      for ri = 2, rows_n do
        out = out .. "<tr>"
        for ci = 1, cols_n do
          local idx = (ri - 1) * cols_n + ci
          local cell = cells[idx] or ""
          out = out .. string.format(
            '<td contenteditable="true" data-row="%d" data-col="%d">%s</td>',
            ri - 1, ci - 1, process_cell(cell)
          )
        end
        out = out .. "</tr>\n"
      end
    else
      out = out .. "<tbody>\n"
      for ri = 1, rows_n do
        out = out .. "<tr>"
        for ci = 1, cols_n do
          local idx = (ri - 1) * cols_n + ci
          local cell = cells[idx] or ""
          out = out .. string.format(
            '<td contenteditable="true" data-row="%d" data-col="%d">%s</td>',
            ri - 1, ci - 1, process_cell(cell)
          )
        end
        out = out .. "</tr>\n"
      end
    end
    return out .. "</tbody>\n</table>\n"

  elseif node.type == "cell_fill" then
    -- cell_fill doesn't render directly; it's merged into table_def during preprocess
    return ""

  elseif node.type == "definition" then
    return "<dl><dt>" .. parser.inline(node.term) .. "</dt><dd>" .. parser.inline(node.def) .. "</dd></dl>\n"

  elseif node.type == "list" then
    return M.render_items(node.items, node.ordered)
  end

  return ""
end

-- ── List rendering ────────────────────────────────────────────────────────────

function M.render_items(items, ordered)
  local tag = ordered and "ol" or "ul"
  local out = "<" .. tag .. ">\n"
  for _, item in ipairs(items) do
    out = out .. "<li>" .. parser.inline(item.text)
    if item.children then
      out = out .. "\n" .. M.render_items(item.children.items, item.children.ordered)
    end
    out = out .. "</li>\n"
  end
  return out .. "</" .. tag .. ">\n"
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Pre-process: merge cell_fill nodes into their corresponding table_def
local function preprocess_tables(nodes)
  local table_map = {}  -- name -> table_def node

  -- First pass: collect all table_def nodes
  for _, node in ipairs(nodes) do
    if node.type == "table_def" and node.name then
      table_map[node.name] = node
    end
  end

  -- Second pass: for dynamic tables, scan cell_fills to determine required dims
  for _, node in ipairs(nodes) do
    if node.type == "cell_fill" and node.table_name then
      local tbl = table_map[node.table_name]
      if tbl then
        if tbl.cols == 0 or tbl.rows == 0 then
          tbl._max_col = math.max(tbl._max_col or 0, node.col + 1)
          tbl._max_row = math.max(tbl._max_row or 0, node.row + 1)
        end
      end
    end
  end

  -- Apply dynamic dimensions and pad cells arrays
  for _, node in ipairs(nodes) do
    if node.type == "table_def" then
      if node.cols == 0 then node.cols = node._max_col or 1 end
      if node.rows == 0 then node.rows = node._max_row or 1 end
      node.cols = math.max(node.cols, 1)
      node.rows = math.max(node.rows, 1)
      local total = node.rows * node.cols
      while #node.cells < total do table.insert(node.cells, "") end
    end
  end

  -- Third pass: merge cell_fill content into table cells
  for _, node in ipairs(nodes) do
    if node.type == "cell_fill" and node.table_name then
      local tbl = table_map[node.table_name]
      if tbl then
        local idx = node.row * tbl.cols + node.col + 1
        tbl.cells[idx] = node.content
      end
    end
  end

  return nodes
end

function M.render(nodes)
  nodes = preprocess_tables(nodes)
  local parts = {}
  for _, node in ipairs(nodes) do
    table.insert(parts, render_node(node))
  end
  return table.concat(parts, "")
end

function M.render_page(title, body, refresh_interval, edit_port)
  local interval = refresh_interval or 1500
  local port     = edit_port or 0
  return string.format(
    [[<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>%s</title>
  <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
  <style>
    /* Catppuccin Mocha */
    :root {
      --base:    #1e1e2e;
      --mantle:  #181825;
      --crust:   #11111b;
      --surface0: #313244;
      --surface1: #45475a;
      --surface2: #585b70;
      --overlay0: #6c7086;
      --overlay1: #7f849c;
      --overlay2: #9399b2;
      --subtext0: #a6adc8;
      --subtext1: #bac2de;
      --text:    #cdd6f4;
      --lavender: #b4befe;
      --blue:    #89b4fa;
      --sapphire: #74c7ec;
      --sky:     #89dceb;
      --teal:    #94e2d5;
      --green:   #a6e3a1;
      --yellow:  #f9e2af;
      --peach:   #fab387;
      --maroon:  #eba0ac;
      --red:     #f38ba8;
      --mauve:   #cba6f7;
      --pink:    #f5c2e7;
      --flamingo: #f2cdcd;
      --rosewater: #f5e0dc;
    }
    * { box-sizing: border-box; }
    body {
      background: var(--base);
      color: var(--text);
      font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
      font-size: 16px;
      line-height: 1.7;
      max-width: 860px;
      margin: 0 auto;
      padding: 2rem 1.5rem;
    }
    h1, h2, h3, h4, h5, h6 {
      color: var(--lavender);
      margin-top: 1.5em;
      margin-bottom: 0.4em;
      line-height: 1.25;
    }
    h1 { color: var(--mauve); font-size: 2rem; border-bottom: 1px solid var(--surface1); padding-bottom: .3em; }
    h2 { color: var(--blue);  font-size: 1.5rem; border-bottom: 1px solid var(--surface0); padding-bottom: .2em; }
    h3 { color: var(--sapphire); }
    h4 { color: var(--sky); }
    h5 { color: var(--teal); }
    h6 { color: var(--green); }
    p { margin: .6em 0; }
    a { color: var(--blue); text-decoration: none; }
    a:hover { text-decoration: underline; }
    strong { color: var(--peach); font-weight: 700; }
    em { color: var(--flamingo); font-style: italic; }
    del { color: var(--overlay1); text-decoration: line-through; }
    code {
      background: var(--surface0);
      color: var(--green);
      font-family: 'JetBrains Mono', 'Fira Code', monospace;
      font-size: .88em;
      padding: .15em .4em;
      border-radius: 4px;
    }
    pre {
      background: var(--mantle);
      border: 1px solid var(--surface0);
      border-radius: 8px;
      padding: 1rem 1.2rem;
      overflow-x: auto;
    }
    pre code {
      background: transparent;
      padding: 0;
      font-size: .9em;
      color: var(--text);
    }
    blockquote {
      border-left: 4px solid var(--mauve);
      margin: 1em 0;
      padding: .5em 1em;
      background: var(--mantle);
      border-radius: 0 6px 6px 0;
      color: var(--subtext1);
    }
    hr {
      border: none;
      border-top: 1px solid var(--surface1);
      margin: 1.5em 0;
    }
    ul, ol { padding-left: 1.6em; margin: .5em 0; }
    li { margin: .2em 0; }
    table {
      border-collapse: collapse;
      width: 100%%;
      margin: 1em 0;
    }
    th {
      background: var(--surface0);
      color: var(--lavender);
      text-align: left;
      padding: .5em .8em;
      border: 1px solid var(--surface1);
    }
    td {
      padding: .45em .8em;
      border: 1px solid var(--surface0);
    }
    tr:nth-child(even) td { background: var(--mantle); }
    dl { margin: 1em 0; }
    dt { color: var(--yellow); font-weight: 700; }
    dd { margin-left: 1.5em; color: var(--subtext1); }
    img { max-width: 100%%; border-radius: 6px; }
    .mermaid {
      background: var(--mantle);
      border: 1px solid var(--surface0);
      border-radius: 8px;
      padding: 1rem;
      margin: 1em 0;
      text-align: center;
    }
    .mermaid svg { max-width: 100%%; height: auto; }
    /* Editable table cell focus ring */
    table.nl-editable [contenteditable]:focus {
      outline: 2px solid var(--blue);
      outline-offset: -2px;
      background: var(--surface0);
    }
    table.nl-editable [contenteditable]:hover {
      background: var(--surface0);
      cursor: text;
    }
    .nl-save-btn {
      display: inline-block;
      margin-top: .4em;
      padding: .25em .8em;
      background: var(--blue);
      color: var(--base);
      border: none;
      border-radius: 4px;
      cursor: pointer;
      font-size: .85em;
      font-weight: 700;
    }
    .nl-save-btn:hover { background: var(--sapphire); }
    .nl-save-status {
      margin-left: .5em;
      font-size: .8em;
      color: var(--green);
    }
    .nl-table-wrap { margin: 1em 0; }
    .nl-sym { font-size: 1.4em; line-height: 1; }
    .nl-sym2 { font-size: 1.9em; line-height: 1; }
  </style>
</head>
<body>
%s
  <script>
    // securityLevel:'loose' renders SVGs directly in the div (not in a sandboxed iframe),
    // so our dark-theme CSS applies. startOnLoad:false + explicit run() is more reliable
    // with mermaid v10 than relying on the DOMContentLoaded startOnLoad mechanism.
    mermaid.initialize({ startOnLoad: false, theme: 'dark', securityLevel: 'loose' });
    mermaid.run({ querySelector: '.mermaid' });
  </script>
  <script>
    // ── Editable table save-back ──────────────────────────────────────────────
    (function() {
      var EDIT_PORT = %d;
      if (EDIT_PORT === 0) return;  // no server running

      // Wrap each editable table with a save button
      document.querySelectorAll('table.nl-editable').forEach(function(tbl) {
        var wrap = document.createElement('div');
        wrap.className = 'nl-table-wrap';
        tbl.parentNode.insertBefore(wrap, tbl);
        wrap.appendChild(tbl);

        var btn = document.createElement('button');
        btn.className = 'nl-save-btn';
        btn.textContent = 'Save table';
        var status = document.createElement('span');
        status.className = 'nl-save-status';
        wrap.appendChild(btn);
        wrap.appendChild(status);

        btn.addEventListener('click', function() {
          var cells = [];
          tbl.querySelectorAll('[contenteditable]').forEach(function(el) {
            cells.push(el.innerText.replace(/\n/g, ' ').trim());
          });
          var payload = JSON.stringify({
            start_line:  parseInt(tbl.dataset.start, 10),
            end_line:    parseInt(tbl.dataset.end,   10),
            table_type:  tbl.dataset.type,
            name:        tbl.dataset.name || '',
            rows:        parseInt(tbl.dataset.rows  || '0', 10),
            cols:        parseInt(tbl.dataset.cols  || '0', 10),
            has_header:  tbl.dataset.hasheader || 'false',
            cells:       cells
          });
          var xhr = new XMLHttpRequest();
          xhr.open('POST', 'http://127.0.0.1:' + EDIT_PORT + '/save-table', true);
          xhr.setRequestHeader('Content-Type', 'application/json');
          xhr.onload = function() {
            if (xhr.status === 200) {
              status.textContent = 'Saved!';
              setTimeout(function() { status.textContent = ''; }, 2000);
            } else {
              status.textContent = 'Error: ' + xhr.responseText;
            }
          };
          xhr.onerror = function() { status.textContent = 'Connection error'; };
          xhr.send(payload);
        });
      });
    })();
  </script>
  <script>
    (function() {
      var INTERVAL = %d;
      var SK = 'notelang_scroll';
      // Restore scroll position
      var saved = sessionStorage.getItem(SK);
      if (saved !== null) {
        window.scrollTo(0, parseInt(saved, 10));
      }
      // Save scroll position before reload
      window.addEventListener('beforeunload', function() {
        sessionStorage.setItem(SK, window.scrollY);
      });
      // Poll for file changes via HEAD request timestamp trick
      var lastMod = null;
      function checkReload() {
        var xhr = new XMLHttpRequest();
        xhr.open('HEAD', window.location.href + '?nc=' + Date.now(), true);
        xhr.onload = function() {
          var mod = xhr.getResponseHeader('Last-Modified');
          if (lastMod === null) {
            lastMod = mod;
          } else if (mod !== lastMod) {
            lastMod = mod;
            sessionStorage.setItem(SK, window.scrollY);
            window.location.reload();
          }
        };
        xhr.onerror = function() {};
        xhr.send();
      }
      setInterval(checkReload, INTERVAL);
    })();
  </script>
</body>
</html>
]],
    title,
    body,
    port,
    interval
  )
end

return M
