# noteLang Plugin — CLAUDE.md

## Project Overview
Neovim plugin for `.note` files: custom markup language with live HTML preview.

## Directory Structure
```
noteLang/
├── ftdetect/notelang.vim   # *.note → filetype=notelang
├── syntax/notelang.vim     # Vim syntax highlighting
├── lua/notelang/
│   ├── init.lua            # M.setup(opts), config defaults
│   ├── parser.lua          # text → AST node list
│   ├── renderer.lua        # AST → HTML + full page
│   └── preview.lua         # write HTML, open browser
└── plugin/notelang.lua     # commands + autocmds
```

## Key Design Decisions
- Parser is a simple line-by-line state machine (no external dependencies)
- Preview uses a temp `.html` file written to disk; browser polls via XHR HEAD requests
- Scroll position is preserved across reloads via `sessionStorage`
- Mermaid.js loaded from CDN (v10) for diagram support
- Catppuccin Mocha dark theme applied via embedded CSS
- Table cells are `contenteditable` in the browser; a "Save table" button POSTs edits to a local TCP server started by `preview.lua`, which writes the changes back to the buffer and saves the file

## Table Syntax
Four ways to write a table:

**Pipe syntax (existing):**
```
| Name | Age |
| --- | --- |
| Alice | 30 |
```

**Keyword syntax — `@table(rows, cols)`:**
```
@table(3, 2) {
// optional comment
Name, Age
Alice, 30
Bob, 25
}
```

**Named object-oriented tables:**
```
table(notes, 3, 2) { }                    -- Define table "notes" (3 cols, 2 rows)

table.notes(0, 1) {                       -- Fill cell at row 0, col 1
Multi-line
content here
}
```
- Define with `table(name, cols, rows) { }`
- Fill cells with `.name(row, col) { content }`
- Newlines inside cells automatically become `<br>` in the rendered HTML
- The first row is always the header
- All forms render with `contenteditable` cells; click **Save table** to write changes back to the `.note` file.
- The edit server runs on a random loopback port, started when `:NLPreview` is called.

## Config Defaults
```lua
require("notelang").setup({
  auto_preview = false,
  refresh_interval = 1500,  -- ms
})
```

## Adding New Node Types
1. Add parsing logic in `parser.lua` `M.parse()` state machine
2. Add rendering in `renderer.lua` `render_node()` dispatch
3. Optionally add a syntax match/region in `syntax/notelang.vim`

## Common Issues
- If preview does not auto-reload, check that `:NLPreview` was run first (creates the temp file)
- `@table` shorthand uses CSV; spaces around commas are trimmed
- Nested lists require consistent indentation (2+ spaces per level)
