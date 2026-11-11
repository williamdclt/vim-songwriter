" autoload/songwriter/tab/typing.vim - typing notes and separators in
" tablature mode (spec [Tablature][[Editing]] 3.4): digits, `x` on a dash, and
" separators straight after a note.

"" Spec [Tablature][[Editing]] 3.4: put `digit` in the cell under the cursor. On
" a dash it replaces the dash; on a note it replaces the whole note, every note
" keeping its time column (columns#SetNote). Straight
" after a digit was typed (cursor still on it, buffer unchanged since), the next
" digit is appended instead, so two-digit frets are typed one key at a time
" (3.4.1), but only when that makes a fret (see s:extends); otherwise, and
" after a muted note, it opens a slot after the note (as `l`) and is entered
" there (3.4.1.1), as it does straight after a chord (spec 10.5). Straight
" after a separator was typed (EnterSeparator), the digit goes right after it
" (3.4.1.3). Then lint the block, keeping the cursor on the digit (4.1); this
" fills any open slot, in the same undo step as the slot, as is a digit
" appended to a fret or separator (4.3.1). The state (normal or insert) is
" kept. No-op off a tab line and on a separator (3.4.2).
function! songwriter#tab#typing#EnterNote(digit) abort
  let l:line = getline('.')
  if !songwriter#grammar#IsTabLine(l:line)
    return
  endif
  let l:digit = a:digit . ''
  let l:col = col('.')
  let l:ch = (l:col <= len(l:line)) ? l:line[l:col - 1] : ''
  let l:typing = songwriter#tab#state#Get('typing')
  let l:here = !empty(l:typing) && l:typing.line == line('.') && l:typing.col == l:col
  let l:insert = songwriter#tab#insert#Active()
  let l:note = songwriter#tab#model#NoteAt(l:line, l:col)
  let l:after_separator = l:here && l:insert && get(l:typing, 'separator', 0)
  if !l:after_separator && l:here && (get(l:typing, 'chord', 0) || !empty(l:note)
        \ && !s:extends(strpart(l:line, l:note.col - 1, l:note.len), l:digit))
    call songwriter#tab#slots#AddNote(1)
    call songwriter#tab#typing#EnterNote(a:digit)
    if !l:insert
      call songwriter#tab#insert#Leave()
    endif
    return
  elseif !l:after_separator && songwriter#grammar#IsSeparatorChar(l:ch)
    return
  endif
  call songwriter#tab#edit#Do(function('s:enter_note', [l:digit, l:here, l:after_separator]),
        \ {'slot': 'fill', 'join': !empty(l:typing), 'prelint': 0, 'insert': 1})
endfunction

" Pure. The digit of EnterNote written at the cursor of `ctx`: right after the
" separator just typed, in a new column (`after_separator`); appended to the
" fret just typed (`here`, on a digit); over the note there; else over the
" cell.
function! s:enter_note(digit, here, after_separator, ctx) abort
  let l:lines = copy(a:ctx.block.lines)
  let l:line = a:ctx.line
  let l:col = a:ctx.col
  let l:note = songwriter#tab#model#NoteAt(l:line, l:col)
  if a:after_separator
    let l:lines = songwriter#tab#model#InsertColumns(l:lines, l:col, 1, '-')
    let l:lines[a:ctx.lin] = songwriter#tab#model#Splice(l:lines[a:ctx.lin], l:col + 1, 1, a:digit)
    let l:col += 1
  elseif !empty(l:note)
    let l:append = a:here && songwriter#grammar#IsFretChar(l:line[l:col - 1])
    let l:text = l:append ? l:note.text . a:digit : a:digit
    let l:res = songwriter#tab#columns#SetNote(l:lines, a:ctx.lin, l:note.col, l:text)
    if has_key(l:res, 'error')
      return {'error': 'songwriter: ' . l:res.error}
    endif
    let l:lines = l:res.lines
    let l:col = l:note.col + (l:append ? len(l:text) - 1 : 0)
  else
    let l:lines[a:ctx.lin] = l:line[0 : l:col - 2] . a:digit . l:line[l:col :]
  endif
  return {'lines': l:lines, 'col': l:col, 'state': {'typing': {}}}
endfunction

" Spec 3.4.1.1: true when appending `digit` to the note `text` makes a fret:
" `text` is a fret without a leading zero and the result is at most
" g:songwriter_max_fret (24 by default).
function! s:extends(text, digit) abort
  return a:text =~# '^[1-9]' && songwriter#grammar#IsFretChar(a:digit)
        \ && str2nr(a:text . a:digit) <= get(g:, 'songwriter_max_fret', 24)
endfunction

" Spec 3.4.1.3: true in the insert state straight after a note was typed
" (cursor still on it, buffer unchanged since; not a chord, spec 10), when a
" separator key writes a separator.
function! songwriter#tab#typing#JustTyped() abort
  let l:typing = songwriter#tab#state#Get('typing')
  return songwriter#tab#insert#Active() && !empty(l:typing)
        \ && !get(l:typing, 'separator', 0) && !get(l:typing, 'chord', 0)
        \ && l:typing.line == line('.') && l:typing.col == col('.')
endfunction

" Spec 3.4.1.3: write the separator `char` right after the note under the
" cursor, inserting a column on every string so that what follows keeps its
" gap, in the same undo step as the note. The cursor lands on it, and the next
" digit goes right after it (EnterNote).
function! songwriter#tab#typing#EnterSeparator(char) abort
  call songwriter#tab#edit#Do(function('s:enter_separator', [a:char]),
        \ {'join': 1, 'prelint': 0, 'lint': 0, 'insert': 1})
endfunction

function! s:enter_separator(char, ctx) abort
  let l:note = songwriter#tab#model#NoteAt(a:ctx.line, a:ctx.col)
  if empty(l:note)
    return {}
  endif
  let l:end = songwriter#tab#model#NoteEnd(l:note)
  let l:lines = songwriter#tab#model#InsertColumns(a:ctx.block.lines, l:end, 1, '-')
  let l:lines[a:ctx.lin] = songwriter#tab#model#Splice(l:lines[a:ctx.lin], l:end + 1, 1, a:char)
  return {'lines': l:lines, 'col': l:end + 1, 'state': {'typing': {'separator': 1}}}
endfunction
