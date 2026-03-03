" noteLang syntax highlighting
if exists("b:current_syntax")
  finish
endif

" ── Block regions ─────────────────────────────────────────────────────────────

" Fenced code block: ```lang … ```
syntax region nlCodeBlock
  \ start=/^\s*```/
  \ end=/^\s*```\s*$/
  \ contains=NONE
  \ keepend

" Graph/diagram block: @keyword { … }
syntax region nlGraphBlock
  \ start=/^@\(graph\|flow\|mindmap\|seq\|table\)\s*{/
  \ end=/^}/
  \ contains=NONE
  \ keepend

" Table keyword block: @table(rows, cols) { … }
syntax region nlTableKwBlock
  \ start=/^@table\s*(/
  \ end=/^}/
  \ contains=NONE
  \ keepend

" Named table definition: table(name, cols, rows) { … }
syntax region nlTableDefBlock
  \ start=/^table\s*(\w+,/
  \ end=/^}/
  \ contains=NONE
  \ keepend

" Cell fill: .name(row, col) { … }
syntax region nlCellFillBlock
  \ start=/^\.\w\+\s*(\d\+,\s*\d\+)\s*{/
  \ end=/^}/
  \ contains=NONE
  \ keepend

" ── Block matches ─────────────────────────────────────────────────────────────

syntax match nlH1      /^#\s.*/
syntax match nlH2      /^##\s.*/
syntax match nlH3      /^###\s.*/
syntax match nlH4      /^####\s.*/
syntax match nlH5      /^#####\s.*/
syntax match nlH6      /^######\s.*/

syntax match nlBlockquote /^>\s.*/

syntax match nlTableRow /^|.*|/
syntax match nlTableSep /^|\s*[-:]\+[-| :]*|/

syntax match nlDefinition /^::\s.*\s::/

syntax match nlListBullet  /^\s*[-*]\s/
syntax match nlListNumber  /^\s*\d\+\.\s/

syntax match nlHRule /^---\+\s*$/

" ── Inline matches ────────────────────────────────────────────────────────────

syntax match nlBold       /\\\@<!\*\*[^*]\+\\\@<!\*\*/
syntax match nlItalic     /\\\@<!\*[^*]\+\\\@<!\*\*/
syntax match nlInlineCode /`[^`]\+`/
syntax match nlStrike     /\~\~[^~]\+\~\~/
syntax match nlLink       /\[.\{-}\](.\{-})/
syntax match nlImage      /!\[.\{-}\](.\{-})/

" ── Highlight links ───────────────────────────────────────────────────────────

highlight default link nlH1         Title
highlight default link nlH2         Title
highlight default link nlH3         Title
highlight default link nlH4         Statement
highlight default link nlH5         Statement
highlight default link nlH6         Statement

highlight default link nlBlockquote Comment
highlight default link nlTableRow   Normal
highlight default link nlTableSep   Comment
highlight default link nlDefinition Identifier
highlight default link nlListBullet Operator
highlight default link nlListNumber Operator
highlight default link nlHRule      Comment

highlight default link nlBold       Bold
highlight default link nlItalic     Italic
highlight default link nlInlineCode String
highlight default link nlStrike     Comment
highlight default link nlLink       Underlined
highlight default link nlImage      Underlined

highlight default link nlCodeBlock      String
highlight default link nlGraphBlock    PreProc
highlight default link nlTableKwBlock  PreProc
highlight default link nlTableDefBlock PreProc
highlight default link nlCellFillBlock PreProc

let b:current_syntax = "notelang"
