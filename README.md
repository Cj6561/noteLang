# noteLang — Neovim Plugin

A custom markup language for note-taking (`*.note` files) with live HTML preview in the browser.

## Features

- Syntax highlighting for `.note` files in Neovim
- Live browser preview with auto-reload while typing (500 ms debounce)
- Catppuccin Mocha dark theme in the preview
- Mermaid.js diagrams (flowcharts, sequence, mindmaps)
- Rich inline formatting, tables, code blocks, definition lists
- Math superscripts, symbol shortcuts, and Unicode arrows

## Installation

### lazy.nvim

```lua
{
  dir = "~/Desktop/code stuff/noteLang",
  config = function()
    require("notelang").setup({
      auto_preview = false,    -- open preview automatically on BufEnter
      refresh_interval = 1500, -- browser poll interval in ms
    })
  end,
}
```

## Commands

| Command | Description |
|---------|-------------|
| `:NLPreview` | Open live preview in browser |
| `:NLUpdate` | Manually push buffer to preview |
| `:NLStop` | Stop preview and clean up temp file |

The preview auto-updates as you type (no save required).

---

## Language Syntax

### Headings

```
# H1
## H2
### H3
#### H4
##### H5
###### H6
```

### Inline Formatting

| Write | Result |
|-------|--------|
| `**bold**` | Bold |
| `*italic*` | Italic |
| `` `code` `` | Inline code |
| `~~strike~~` | Strikethrough |
| `[text](url)` | Link |
| `![alt](url)` | Image |

### Lists

```
- unordered item
  - nested item
    - doubly nested

1. ordered item
2. second item
```

### Blockquote

```
> This is a blockquote.
> It can span multiple lines.
```

### Horizontal Rule

```
---
```

### Fenced Code Block

````
```python
def hello():
    print("Hello, world!")
```
````

### Definition List

```
:: term :: definition text here
```

---

## Math & Superscripts

| Write | Renders as |
|-------|-----------|
| `a^n` | a with superscript n |
| `a^(n+1)` | a with superscript (n+1) |
| `(a+b)^n` | (a+b) with superscript n |
| `(a+b)^(n+1)` | (a+b) with superscript (n+1) |
| `\^` | literal `^` |

---

## Symbol Shortcuts

### Arrows

| Write | Renders as | Escape to suppress |
|-------|-----------|-------------------|
| `-->` | → | `\-->` |
| `<--` | ← | `\<--` |
| `<->` | ↔ | `\<->` |
| `==>` | ⇒ | `\==>` |
| `<==` | ⇐ | `\<==` |
| `<=>` | ⇔ | `\<=>` |

### Math Symbols

| Write | Renders as | Escape to suppress |
|-------|-----------|-------------------|
| `>=` | ≥ | `\>=` |
| `<=` | ≤ | `\<=` |
| `\(e` | ∈ | — |
| `\d^` | ⌄ | — |

---

## Tables

### Pipe Syntax

```
| Name  | Age |
| ----- | --- |
| Alice | 30  |
| Bob   | 25  |
```

A separator row (`| --- |`) makes the first row a bold header. Omit it for a plain table.

### Keyword Syntax — `@table(rows, cols)`

```
@table(3, 2) {
// optional comment
Name, Age
Alice, 30
Bob, 25
}
```

### Named / Object-Oriented Tables

Define a table and fill cells separately:

```
table(notes, 3, 2) { }

.notes(0, 0) {
Header A
}

.notes(0, 1) {
Header B
}

.notes(1, 0) {
Cell content
supports multiple lines
}
```

- `table(name, cols, rows)` — define the table
- `.name(row, col) { content }` — fill individual cells
- Newlines inside cells become `<br>` in HTML
- First row is always the header
- All table forms render with `contenteditable` cells; click **Save table** to write changes back to the `.note` file

---

## Diagrams (Mermaid.js)

All diagram blocks use `@keyword {` … `}` syntax.

### Flowchart

```
@flow {
  Login -> Dashboard -> Profile
  Dashboard -> Settings
}
```

### Sequence Diagram

```
@seq {
  User -> Server: POST /login
  Server -> User: 200 OK
}
```

### Mindmap

```
@mindmap {
  My Notes
    Topic A
      Detail 1
    Topic B
}
```

### Raw Mermaid

```
@graph {
  graph TD
  A[Start] --> B{Decision}
  B -->|Yes| C[Done]
  B -->|No| A
}
```
