" autoload/songwriter/tab/strings.vim - moving notes to another string, keeping
" their time column (spec [Tablature][[Editing]] 7). Move() is pure (block
" lines in, lines and cursor out); Change() is the buffer entry point.
"
" Block lines are 0-indexed (`lin`), columns 1-indexed, as in tab/columns.vim.
" `dir` is -1 for the string above (the line above), +1 for the one below.

" Spec 7: move the chain (the notes joined by separators, grammar Chain) under
" column `col` of line `lin` (column 0), or every chain starting on the time
" column under it (column 1), one string in direction `dir`.
" keep_pitch 0 moves the notes unchanged (7.2), 1 shifts their frets by the
" interval between the two strings (7.3). A chain with a note on the time column
" that starts earlier is refused (7.4). Returns {'lines', 'lin', 'col'}
" (the cursor follows the notes), or {'error': message} (7.4).
function! songwriter#tab#strings#Move(lines, lin, col, dir, keep_pitch, column) abort
  let l:c = s:column_at(a:lines, a:lin, a:col, a:column)
  if l:c == 0
    return {'error': a:column ? 'no time column under the cursor' : 'no note under the cursor'}
  endif

  " The notes to move: [{'lin', 'text'}], with their new text.
  let l:movers = []
  for l:i in (a:column ? range(len(a:lines)) : [a:lin])
    for l:a in songwriter#tab#model#Chains(a:lines[l:i])
      if a:column && l:a.col != l:c && s:has_note_at(a:lines[l:i], l:a, l:c)
        return {'error': printf('the note on string %s is linked to an earlier one',
              \ songwriter#tab#model#Name(a:lines[l:i]))}
      endif
      if l:a.col == l:c
        let l:to = l:i + a:dir
        if l:to < 0 || l:to >= len(a:lines)
          return {'error': printf('no string %s %s', a:dir < 0 ? 'above' : 'below', songwriter#tab#model#Name(a:lines[l:i]))}
        endif
        let l:text = a:keep_pitch ? s:repitch(a:lines, l:i, l:to, l:a.text) : l:a.text
        if type(l:text) == v:t_dict
          return l:text
        endif
        call add(l:movers, {'lin': l:i, 'to': l:to, 'len': l:a.len, 'text': l:text})
      endif
    endfor
  endfor

  " Clear every source first, so that the notes of a column never collide.
  let l:lines = copy(a:lines)
  for l:m in l:movers
    let l:lines[l:m.lin] = strpart(l:lines[l:m.lin], 0, l:c - 1) . repeat('-', l:m.len)
          \ . strpart(l:lines[l:m.lin], l:c - 1 + l:m.len)
  endfor
  for l:m in l:movers
    let l:room = songwriter#tab#columns#MakeRoom(l:lines, l:m.to, l:c, len(l:m.text))
    if has_key(l:room, 'error')
      return l:room
    endif
    let [l:lines, l:c] = [l:room.lines, l:room.col]
    let l:t = l:lines[l:m.to]
    let l:lines[l:m.to] = strpart(l:t, 0, l:c - 1) . l:m.text . strpart(l:t, l:c - 1 + len(l:m.text))
  endfor

  " 7.6: the cursor moves one string with the notes, on the same character of
  " its note when it was on one.
  let l:cur = filter(copy(l:movers), 'v:val.lin == a:lin')
  let l:lin = max([0, min([a:lin + a:dir, len(a:lines) - 1])])
  let l:col = l:c
  if !empty(l:cur)
    let l:col += min([a:col - s:column_at(a:lines, a:lin, a:col, 0), len(l:cur[0].text) - 1])
  endif
  return {'lines': l:lines, 'lin': l:lin, 'col': l:col}
endfunction

" True when a note of `line` inside `chain` starts on column `c`.
function! s:has_note_at(line, chain, c) abort
  return a:c > a:chain.col && a:c < a:chain.col + a:chain.len
        \ && !empty(filter(songwriter#tab#model#Notes(a:line), 'v:val.col == a:c'))
endfunction

" Column 0: the start of the chain covering `col` on line `lin`. Column 1: the
" start of the note covering `col` on line `lin`; off a note, the column `col`
" when a note on another string starts there, else the start of a note covering
" `col` on another string. 0: none.
function! s:column_at(lines, lin, col, column) abort
  let l:here = a:column ? songwriter#tab#model#Notes(a:lines[a:lin])
        \ : songwriter#tab#model#Chains(a:lines[a:lin])
  for l:a in l:here
    if a:col >= l:a.col && a:col < l:a.col + l:a.len
      return l:a.col
    endif
  endfor
  if !a:column
    return 0
  endif
  let l:covering = []
  for l:l in a:lines
    for l:a in songwriter#tab#model#Notes(l:l)
      if l:a.col == a:col
        return a:col
      elseif a:col > l:a.col && a:col < l:a.col + l:a.len
        call add(l:covering, l:a.col)
      endif
    endfor
  endfor
  return empty(l:covering) ? 0 : min(l:covering)
endfunction

" Spec 7.3: `text` (a chain on line `from`) with every fret shifted by the
" interval between strings `from` and `to`, or {'error'}.
" Strings are taken to be listed from the highest to the lowest, neighbouring
" strings less than an octave apart: the interval is read from pitch classes.
" A mark without a fret (`x`) is returned unchanged.
function! s:repitch(lines, from, to, text) abort
  if a:text !~# songwriter#grammar#Fret()
    return a:text
  endif
  for l:lin in [a:from, a:to]
    if songwriter#pitch#Class(songwriter#tab#model#Name(a:lines[l:lin])) < 0
      return {'error': printf('string name %s is not a note', songwriter#tab#model#Name(a:lines[l:lin]))}
    endif
  endfor
  let [l:hi, l:lo] = a:to < a:from ? [a:to, a:from] : [a:from, a:to]
  let l:interval = (songwriter#pitch#Class(songwriter#tab#model#Name(a:lines[l:hi]))
        \ - songwriter#pitch#Class(songwriter#tab#model#Name(a:lines[l:lo])) + 12) % 12
  if l:interval == 0
    return {'error': printf('cannot tell the interval between strings %s and %s',
          \ songwriter#tab#model#Name(a:lines[l:hi]), songwriter#tab#model#Name(a:lines[l:lo]))}
  endif
  let l:shift = a:to < a:from ? -l:interval : l:interval
  let l:frets = map(filter(split(a:text, songwriter#grammar#NotFret()), '!empty(v:val)'), 'str2nr(v:val, 10) + l:shift')
  if min(l:frets) < 0
    return {'error': printf('the fret would go below 0 on string %s', songwriter#tab#model#Name(a:lines[a:to]))}
  endif
  return substitute(a:text, songwriter#grammar#Fret(), '\=str2nr(submatch(0), 10) + l:shift', 'g')
endfunction

" Spec 7: the buffer entry point for `s`/`S` + `k`/`j`/`K`/`J`. Lints first
" (closing any open slot), moves, lints again with the cursor on the moved
" note, and records itself for `.` (6.10). A refusal is echoed.
function! songwriter#tab#strings#Change(dir, keep_pitch, column) abort
  call songwriter#tab#slots#Abandon()
  if empty(songwriter#tab#edit#Run(function('s:move', [a:dir, a:keep_pitch, a:column])))
    return
  endif
  call songwriter#tab#repeat#Record(printf('songwriter#tab#strings#Change(%d, %d, %d)',
        \ a:dir, a:keep_pitch, a:column), 1)
endfunction

function! s:move(dir, keep_pitch, column, ctx) abort
  let l:res = songwriter#tab#strings#Move(a:ctx.block.lines, a:ctx.lin, a:ctx.col,
        \ a:dir, a:keep_pitch, a:column)
  return has_key(l:res, 'error') ? {'error': 'songwriter: ' . l:res.error} : l:res
endfunction
