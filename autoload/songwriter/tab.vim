" autoload/songwriter/tab.vim - tablature operations (spec [Tablature]).
"
" Public functions are the buffer entry points: they read the block with
" songwriter#tab#model#Read(), call a pure helper that returns new lines and/or
" a cursor column, and apply the result. Parsing and column arithmetic live in
" the model (tab/model.vim); the linter in tab/lint.vim.

" === Editing ===

" Append `--` to every string of the block.
function! songwriter#tab#AddDashes() abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call songwriter#tab#model#Write(l:block, map(copy(l:block.lines), "v:val . '--'"))
endfunction

" Spec [Tablature][[Editing]] 2: insert a dash after the cursor column on
" every string of the block.
function! songwriter#tab#AddDash() abort
  call s:insert_after_cursor('-')
endfunction

" Insert a bar pipe after the cursor column on every string of the block.
function! songwriter#tab#AddBar() abort
  call s:insert_after_cursor('|')
endfunction

function! s:insert_after_cursor(char) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call songwriter#tab#model#Write(l:block,
        \ songwriter#tab#model#InsertColumns(l:block.lines, col('.'), 1, a:char))
endfunction

" Spec [Tablature][[Editing]] 1: lint the block around the cursor.
function! songwriter#tab#Lint() abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call songwriter#tab#model#Write(l:block, songwriter#tab#lint#Lint(l:block.lines).lines)
endfunction

" Insert `chord` on a new line above the block, aligned to the cursor column.
function! songwriter#tab#TabChord(chord) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call append(l:block.start - 1, repeat(' ', col('.') - 1) . a:chord)
endfunction

" Spec [Tablature][[Editing]] 3.4: put `digit` in the cell under the cursor. On
" a dash it replaces the dash; on a note it replaces the whole note. Straight
" after a digit was typed (cursor still on it, buffer unchanged since), the next
" digit is appended instead, so two-digit frets are typed one key at a time
" (3.4.1). Then lint the block, keeping the cursor on the digit (4.1); this
" fills any open slot. No-op off a tab line.
function! songwriter#tab#EnterNote(digit) abort
  let l:line = getline('.')
  if !songwriter#grammar#IsTabLine(l:line)
    return
  endif
  let l:digit = a:digit . ''
  let l:col = col('.')
  let l:ch = (l:col <= len(l:line)) ? l:line[l:col - 1] : ''
  let l:typing = songwriter#tab#state#Get('typing')
  let l:note = s:note_at(l:line, l:col)
  if !empty(l:typing) && l:typing.line == line('.') && l:typing.col == l:col
        \ && songwriter#grammar#IsNoteChar(l:ch)
    call setline('.', l:line[0 : l:col - 1] . l:digit . l:line[l:col :])
    call cursor(line('.'), l:col + 1)
  elseif !empty(l:note)
    call setline('.', strpart(l:line, 0, l:note.col - 1) . l:digit
          \ . strpart(l:line, l:note.col - 1 + l:note.len))
    call cursor(line('.'), l:note.col)
  else
    call setline('.', l:line[0 : l:col - 2] . l:digit . l:line[l:col :])
    call cursor(line('.'), l:col)
  endif
  call songwriter#tab#edit#LintAndFollow(songwriter#tab#model#Read())
  call songwriter#tab#slots#Forget()
  call songwriter#tab#state#Set('typing', {'line': line('.'), 'col': col('.')})
endfunction

" The note of `line` covering column `col`, or {}.
function! s:note_at(line, col) abort
  for l:n in songwriter#tab#model#Notes(a:line)
    if a:col >= l:n.col && a:col < l:n.col + l:n.len
      return l:n
    endif
  endfor
  return {}
endfunction

" Spec [Tablature][[Editing]] 3.1: open room for a new note on every string,
" to the right of the current note (side +1, `a`) or to its left (side -1,
" `i`), and land the cursor on the new slot. The block is linted first (4.2),
" and the slot is remembered until a note fills it or it is abandoned (4.3).
function! songwriter#tab#AddNote(side) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call songwriter#tab#slots#Forget()
  let l:block = songwriter#tab#edit#LintAndFollow(l:block)
  let l:line = getline('.')
  let l:result = a:side > 0
        \ ? songwriter#tab#slots#Append(l:block, l:line, col('.'))
        \ : songwriter#tab#slots#Prepend(l:block, l:line, col('.'))
  call songwriter#tab#edit#Apply(l:block, l:result)
  if !empty(l:result)
    call songwriter#tab#slots#Open()
  endif
endfunction

" Spec [Tablature][[Editing]] 5: append a new bar to the end of the tab with a
" slot in its middle, and land the cursor on it, ready for a note. Like `a`,
" the block is linted first (4.2) and the slot is remembered (4.3); abandoned,
" the empty bar is linted away (1.4).
function! songwriter#tab#AddBarSlot() abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call songwriter#tab#slots#Forget()
  let l:block = songwriter#tab#edit#LintAndFollow(l:block)
  call songwriter#tab#edit#Apply(l:block, songwriter#tab#slots#AppendBar(l:block))
  call songwriter#tab#slots#Open()
endfunction

" Spec [Tablature][[Editing]] 8: add an empty tab under (below 1, `o`) or
" over (below 0, `O`) the block around the cursor, with the same string names
" and a blank line between the two, and land on the slot in its middle, on the
" cursor's string. The slot is remembered as `a`'s is (4.3): a digit fills it,
" and abandoned, it is linted to an empty bar. An open slot is abandoned first.
function! songwriter#tab#NewTab(below) abort
  call songwriter#tab#slots#Abandon()
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:tab = songwriter#tab#slots#EmptyTab(l:block)
  let l:row = line('.') - l:block.start
  if a:below
    let l:last = l:block.start + len(l:block.lines) - 1
    call append(l:last, [''] + l:tab.lines)
    let l:first = l:last + 2
  else
    call append(l:block.start - 1, l:tab.lines + [''])
    let l:first = l:block.start
  endif
  call cursor(l:first + l:row, l:tab.col)
  call songwriter#tab#slots#Open()
endfunction

" === Linting after edits (spec [Tablature][[Editing]] 4) ===

" === Motions ===

" Spec [Tablature][[Editing]] 3.2: move to the next (dir +1) / previous (-1)
" note on the current line. No-op off a tab line or with no note that way.
" An open slot is abandoned first (4.3).
function! songwriter#tab#MoveNote(dir) abort
  call songwriter#tab#slots#Abandon()
  let l:line = getline('.')
  if !songwriter#grammar#IsTabLine(l:line)
    return
  endif
  let l:cols = map(songwriter#tab#model#Notes(l:line), 'v:val.col')
  let l:target = s:nearest(l:cols, col('.'), a:dir)
  if l:target > 0
    call cursor(line('.'), l:target)
  endif
endfunction

" Spec [Tablature][[Editing]] 3.3: `l` (dir +1) / `h` (dir -1) move to the
" next/previous column where any string of the block has a note, crossing bar
" pipes. Exception (3.3.2): `l` on the last note column of the cursor's bar
" opens a slot as `a` does (linting first, 4.2). `l` with no note further
" right appends a new bar when the cursor is in the tab's last bar (5, see
" AddBarSlot), and otherwise opens a slot as `a` does. `h` never opens a slot
" and is a no-op before the first note (3.3.3). An open slot is abandoned
" first (4.3).
function! songwriter#tab#MoveColumn(dir) abort
  call songwriter#tab#slots#Abandon()
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:line = getline('.')
  let l:col = col('.')
  let l:cols = songwriter#tab#model#NoteColumns(l:block)

  if a:dir < 0
    let l:target = s:nearest(l:cols, l:col, -1)
    if l:target > 0
      call cursor(line('.'), l:target)
    endif
    return
  endif

  let l:bar = songwriter#tab#model#BarAt(l:line, l:col)
  let l:in_bar = filter(copy(l:cols), 'songwriter#tab#model#InBar(v:val, l:bar)')
  let l:last_in_bar = empty(l:in_bar) ? 0 : max(l:in_bar)
  let l:target = s:nearest(l:cols, l:col, 1)
  if l:col == l:last_in_bar
    call songwriter#tab#AddNote(1)
  elseif l:target == 0
    if s:in_last_bar(l:line, l:col)
      call songwriter#tab#AddBarSlot()
    else
      call songwriter#tab#AddNote(1)
    endif
  else
    call cursor(line('.'), min([l:target, len(l:line)]))
  endif
endfunction

" True when `col` is in the last bar of a tab line that ends with a pipe:
" the line's final pipe is the first pipe at or after `col`.
function! s:in_last_bar(line, col) abort
  let l:pipes = songwriter#tab#model#Pipes(a:line)
  if empty(l:pipes) || l:pipes[-1] != len(a:line) || a:col > l:pipes[-1]
    return 0
  endif
  return empty(filter(copy(l:pipes), 'v:val >= a:col && v:val < l:pipes[-1]'))
endfunction

" The nearest value in `cols` strictly after (dir > 0) or before (dir < 0)
" `col`; 0 when none.
function! s:nearest(cols, col, dir) abort
  let l:cands = filter(copy(a:cols), a:dir > 0 ? 'v:val > a:col' : 'v:val < a:col')
  return empty(l:cands) ? 0 : (a:dir > 0 ? min(l:cands) : max(l:cands))
endfunction
