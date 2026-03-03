# noteLang — Neovim Plugin

A custom markup language for note-taking (`*.note` files) with live HTML preview in the browser.

## Features

- Syntax highlighting for `.note` files in Neovim
- Live browser preview with auto-reload on save (~1.5 s)
- Catppuccin Mocha dark theme in the preview
- Mermaid.js diagrams (flowcharts, sequence, mindmaps)
- Rich inline formatting, tables, code blocks, definition lists

## Installation

### lazy.nvim

```lua
{
  dir = "~/Desktop/code stuff/noteLang",
  config = function()
    require("notelang").setup({
      auto_preview = false,   -- open preview automatically on BufEnter
      refresh_interval = 1500, -- browser poll interval in ms
    })
  end,
}
```

## Language Syntax

| Syntax | Element |
|--------|---------|
| `# H1` … `###### H6` | Headings |
| `**bold**` | Bold |
| `*italic*` | Italic |
| `` `code` `` | Inline code |
| `~~strike~~` | Strikethrough |
| `[text](url)` | Link |
| `![alt](url)` | Image |
| `- item` / `* item` | Unordered list (indent to nest) |
| `1. item` | Ordered list |
| `\| col \| col \|` + `\| --- \| --- \|` | Pipe table |
| `> text` | Blockquote |
| ` ```lang ` … ` ``` ` | Fenced code block |
| `---` | Horizontal rule |
| `:: term :: definition` | Definition list |
| `@graph { … }` | Raw Mermaid.js |
| `@flow { A -> B }` | Flowchart (`graph LR`) |
| `@mindmap { … }` | Mindmap |
| `@seq { A -> B: msg }` | Sequence diagram |
| `@table { CSV rows }` | CSV table (first row = header) |

### Template Block Format

All `@keyword` blocks open with `@keyword {` and close with `}` on its own line:

```
@flow {
  Login -> Dashboard -> Profile
  Dashboard -> Settings
}

@seq {
  User -> Server: POST /login
  Server -> User: 200 OK
}

@mindmap {
  My Notes
    Topic A
      Detail 1
    Topic B
}

@table {
  Name, Age, City
  Alice, 30, NYC
  Bob, 25, LA
}
```

## Commands

| Command | Description |
|---------|-------------|
| `:NLPreview` | Open live preview in browser |
| `:NLUpdate` | Manually push buffer to preview |
| `:NLStop` | Stop preview and clean up temp file |

## Verification

1. Open a `*.note` file — filetype should be `notelang`, syntax colors visible
2. `:NLPreview` — browser opens an HTML preview
3. Edit and save — browser auto-reloads after ~1.5 s
4. `:NLStop` — temp file cleaned up
