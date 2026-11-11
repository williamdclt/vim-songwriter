" autoload/songwriter/tab/frets.vim - moving a note up or down the frets, on
" its string and time column (spec [Tablature][[Editing]] 11). Shift() is pure
" (block lines in, lines and cursor out); Change() is the buffer entry point.
"
" Block lines are 0-indexed (`lin`), columns 1-indexed, as in tab/columns.vim.

" Spec 11: the note under column `col` of line `lin`, `n` frets up (n > 0) or
" down. Only that note changes; its chain is rewritten in place (11.1), making
" room as a string move does when it gets wider (11.2, columns#PutNote).
" Returns {'lines', 'lin', 'col'} (the cursor on the note, on its last digit at
" most), or {'error': message} (11.3).
function! songwriter#tab#frets#Shift(lines, lin, col, n) abort
  let l:line = a:lines[a:lin]
  let l:note = s:covering(songwriter#tab#model#Notes(l:line), a:col)
  if empty(l:note) || l:note.text !~# '^' . songwriter#grammar#Fret() . '$'
    return {'error': 'no fretted note under the cursor'}
  endif
  let l:fret = str2nr(l:note.text, 10) + a:n
  if l:fret < 0
    return {'error': 'the fret would go below 0'}
  endif
  let l:max = get(g:, 'songwriter_max_fret', 24)
  if l:fret > l:max
    return {'error': printf('the fret would go above %d', l:max)}
  endif

  let l:chain = s:covering(songwriter#tab#model#Chains(l:line), a:col)
  let l:text = songwriter#tab#model#Splice(l:chain.text, l:note.col - l:chain.col + 1,
        \ l:note.len, string(l:fret))
  let l:lines = copy(a:lines)
  let l:lines[a:lin] = songwriter#tab#model#Blank(l:line, l:chain)
  let l:room = songwriter#tab#columns#PutNote(l:lines, a:lin, l:chain.col, l:text)
  if has_key(l:room, 'error')
    return l:room
  endif
  let l:start = l:room.col + l:note.col - l:chain.col
  let l:col = l:start + min([a:col - l:note.col, len(string(l:fret)) - 1])
  return {'lines': l:room.lines, 'lin': a:lin, 'col': l:col}
endfunction

" The item of `items` (as model#Notes() gives them) covering column `col`, or {}.
function! s:covering(items, col) abort
  for l:a in a:items
    if a:col >= l:a.col && a:col < l:a.col + l:a.len
      return l:a
    endif
  endfor
  return {}
endfunction

" Spec 11: the buffer entry point for `]` / `[`. Lints first (closing any open
" slot), changes the fret, lints again with the cursor on the note, and records
" itself for `.` (spec 6.10). A refusal is echoed.
function! songwriter#tab#frets#Change(n) abort
  call songwriter#tab#edit#Do(function('s:shift', [a:n]), {
        \ 'slot': 'close',
        \ 'repeat': printf('songwriter#tab#frets#Change(%d)', a:n)})
endfunction

function! s:shift(n, ctx) abort
  let l:res = songwriter#tab#frets#Shift(a:ctx.block.lines, a:ctx.lin, a:ctx.col, a:n)
  return has_key(l:res, 'error') ? {'error': 'songwriter: ' . l:res.error} : l:res
endfunction
