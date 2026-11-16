" autoload/songwriter/tab/actions.vim - the tablature-mode edits at the cursor
" that are not operators (spec [Tablature][[Editing]] 6.5, 6.7, 6.13, 6.14):
" `x`, `p`/`P`, `>>`/`<<` and `gp`, each an edit (edit#Do) around the pure
" column model (tab/columns.vim, tab/paste.vim). Operators are
" tab/operator.vim.

" `x` in normal mode: on a dash, enter a muted note as a digit would (spec 3.4.3);
" elsewhere, erase (6.7).
function! songwriter#tab#actions#EraseOrMute(count, reg) abort
  if getline('.')[col('.') - 1] ==# '-'
    call songwriter#tab#typing#EnterNote('x')
  else
    call songwriter#tab#actions#Erase(a:count, a:reg)
  endif
endfunction

" Spec 6.7: `x`, `count` times on the cursor's string (after the first, from
" the next note on the string). Writes what was erased to `reg` (6.7.3).
function! songwriter#tab#actions#Erase(count, reg) abort
  call songwriter#tab#edit#Do(function('s:erase', [a:count, a:reg]), {
        \ 'repeat': "songwriter#tab#actions#Erase(%d, '" . a:reg . "')", 'count': a:count})
endfunction

function! s:erase(count, reg, ctx) abort
  let l:lines = a:ctx.block.lines
  let l:map = []
  let l:col = a:ctx.col
  let l:rows = []
  " The annotations erased with the notes ([[Annotations]] 5.1), at their
  " offsets in the register's rows.
  let l:above = a:ctx.block.above
  let l:words = []
  let l:lone = 0
  for l:i in range(max([a:count, 1]))
    if l:i > 0 && empty(songwriter#tab#model#NoteAt(l:lines[a:ctx.lin], l:col))
      let l:next = filter(map(songwriter#tab#model#Notes(l:lines[a:ctx.lin]), 'v:val.col'), 'v:val > l:col')
      if empty(l:next)
        break
      endif
      let l:col = l:next[0]
    endif
    let l:res = songwriter#tab#columns#EraseNote(l:lines, a:ctx.lin, l:col)
    if empty(l:res)
      break
    endif
    let l:lone = len(l:res.lines[a:ctx.lin]) < len(l:lines[a:ctx.lin])
    let l:width = empty(l:rows) ? 0 : len(l:rows[0])
    for l:w in songwriter#tab#annotations#Cut(l:above, l:res.map)
      call add(l:words, extend(l:w, {'col': l:w.col - l:res.col + 1 + l:width}))
    endfor
    let l:rows = empty(l:rows) ? l:res.rows : map(l:rows, 'v:val . l:res.rows[v:key]')
    let l:linted = songwriter#tab#edit#Linted(l:res.lines, a:ctx.lin,
          \ max([1, min([l:res.col, len(l:res.lines[a:ctx.lin])])]))
    let [l:lines, l:col] = [l:linted.lines, l:linted.col]
    let l:step = songwriter#tab#colmap#Then(l:res.map, l:linted.map)
    let l:above = songwriter#tab#annotations#Follow(l:above, l:step)
    let l:map = songwriter#tab#colmap#Then(l:map, l:step)
  endfor
  if empty(l:rows)
    return {}
  endif
  let l:annotations = songwriter#tab#annotations#Rows(l:words, 1)
  return {'lines': l:lines, 'map': l:map, 'col': l:lone ? songwriter#tab#columns#NextColumn(l:lines, l:col) : l:col,
        \ 'register': {'name': a:reg, 'rows': l:annotations + l:rows, 'type': 'b',
        \   'names': songwriter#tab#model#Names(l:lines), 'above': len(l:annotations)}}
endfunction

" Spec 6.5 / 6.3.2: `p` (before 0) / `P` (before 1) from register `reg`.
function! songwriter#tab#actions#Put(before, count, reg) abort
  let l:repeat = printf("songwriter#tab#actions#Put(%d, %%d, '%s')", a:before, a:reg)
  if getregtype(a:reg) !=# 'V'
    call songwriter#tab#edit#Do(function('s:put', [a:before, a:count, a:reg]),
          \ {'repeat': l:repeat, 'count': a:count})
    return
  endif
  call songwriter#tab#edit#Do({_ -> {}})
  let l:block = songwriter#tab#model#Read()
  if !empty(l:block)
    call s:put_lines(l:block, getreg(a:reg, 1, 1), a:before, a:count)
    call songwriter#tab#repeat#Record(l:repeat, a:count)
  endif
endfunction

" Spec 6.5: a blockwise register pasted at the cursor of `ctx`.
function! s:put(before, count, reg, ctx) abort
  let l:rows = songwriter#tab#register#BlockRows(a:reg)
  if empty(l:rows)
    return {'error': 'cannot paste a character-wise register into a tab'}
  endif
  let l:reg = songwriter#tab#register#Split(a:reg)
  return songwriter#tab#paste#Paste(a:ctx.block.lines, a:ctx.lin, a:ctx.col, l:reg.rows,
        \ songwriter#tab#register#Names(a:reg), a:before, a:count, l:reg.above)
endfunction

" A line-wise register goes after the tab (before it and its annotations for
" `P`), never between its strings; a blank line keeps a pasted tab from joining
" the tab.
function! s:put_lines(block, rows, before, count) abort
  let l:rows = []
  for l:i in range(max([a:count, 1]))
    call extend(l:rows, a:rows)
  endfor
  if empty(l:rows)
    return
  endif
  if a:before
    if songwriter#grammar#IsTabLine(l:rows[-1])
      call add(l:rows, '')
    endif
    let l:at = a:block.top - 1
    let l:first = l:at + 1
  else
    if songwriter#tab#model#StartsTab(l:rows)
      call insert(l:rows, '')
    endif
    let l:at = a:block.end
    let l:first = l:at + 1 + (l:rows[0] ==# '' ? 1 : 0)
  endif
  call append(l:at, l:rows)
  call cursor(l:first, 1)
endfunction

" Spec 6.13: `>>` (dir +1) / `<<` (dir -1), `count` times.
function! songwriter#tab#actions#Shift(dir, count) abort
  call songwriter#tab#edit#Do(function('s:shift', [a:dir, a:count]), {
        \ 'repeat': 'songwriter#tab#actions#Shift(' . a:dir . ', %d)', 'count': a:count})
endfunction

function! s:shift(dir, count, ctx) abort
  let l:lines = a:ctx.block.lines
  let l:map = []
  let l:col = a:ctx.col
  let l:done = 0
  for l:i in range(max([a:count, 1]))
    let l:res = songwriter#tab#columns#ShiftColumn(l:lines, a:ctx.lin, l:col, a:dir)
    if empty(l:res)
      break
    endif
    let l:linted = songwriter#tab#edit#Linted(l:res.lines, a:ctx.lin, l:res.col)
    let [l:lines, l:col] = [l:linted.lines, l:linted.col]
    let l:map = songwriter#tab#colmap#Then(l:map, songwriter#tab#colmap#Then(l:res.map, l:linted.map))
    let l:done = 1
  endfor
  return l:done ? {'lines': l:lines, 'col': l:col, 'map': l:map} : {}
endfunction

" Spec 6.14: `gp`, overlay a column register onto the cursor's column.
function! songwriter#tab#actions#Overlay(reg) abort
  call songwriter#tab#edit#Do(function('s:overlay', [a:reg]))
endfunction

function! s:overlay(reg, ctx) abort
  let l:rows = songwriter#tab#register#BlockRows(a:reg)
  if empty(l:rows)
    return {'error': 'gp pastes a column register'}
  endif
  " The notes only: the column keeps its own annotations.
  return songwriter#tab#paste#Overlay(a:ctx.block.lines, a:ctx.lin, a:ctx.col,
        \ songwriter#tab#register#Split(a:reg).rows, songwriter#tab#register#Names(a:reg))
endfunction

