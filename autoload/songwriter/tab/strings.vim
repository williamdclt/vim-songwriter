" autoload/songwriter/tab/strings.vim - moving notes to another string, keeping
" their time column (spec [Tablature][[Editing]] 7). Move() is pure (block
" lines in, lines and cursor out); Change() is the buffer entry point.
"
" Block lines are 0-indexed (`lin`), columns 1-indexed, as in tab/columns.vim.
" `dir` is -1 for the string above (the line above), +1 for the one below.

" Spec 7: move the note under column `col` of line `lin` (column 0), or every
" note of the time column under it (column 1), one string in direction `dir`.
" keep_pitch 0 moves the notes unchanged (7.2), 1 shifts their frets by the
" interval between the two strings (7.3). Returns {'lines', 'lin', 'col'}
" (the cursor follows the notes), or {'error': message} (7.4).
function! songwriter#tab#strings#Move(lines, lin, col, dir, keep_pitch, column) abort
  let l:c = s:column_at(a:lines, a:lin, a:col, a:column)
  if l:c == 0
    return {'error': a:column ? 'no time column under the cursor' : 'no note under the cursor'}
  endif

  " The notes to move: [{'lin', 'text'}], with their new text.
  let l:movers = []
  for l:i in (a:column ? range(len(a:lines)) : [a:lin])
    for l:a in songwriter#tab#columns#Atoms(a:lines[l:i])
      if l:a.col == l:c
        let l:to = l:i + a:dir
        if l:to < 0 || l:to >= len(a:lines)
          return {'error': printf('no string %s %s', a:dir < 0 ? 'above' : 'below', s:name(a:lines, l:i))}
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
    let l:room = s:make_room(l:lines, l:m.to, l:c, len(l:m.text))
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

" The start column of the note covering `col` on line `lin`; for a time column
" (column 1) off a note, the column `col` when a note on another string starts
" there, else the start of a note covering `col` on another string. 0: none.
function! s:column_at(lines, lin, col, column) abort
  for l:a in songwriter#tab#columns#Atoms(a:lines[a:lin])
    if a:col >= l:a.col && a:col < l:a.col + l:a.len
      return l:a.col
    endif
  endfor
  if !a:column
    return 0
  endif
  let l:covering = []
  for l:l in a:lines
    for l:a in songwriter#tab#columns#Atoms(l:l)
      if l:a.col == a:col
        return a:col
      elseif a:col > l:a.col && a:col < l:a.col + l:a.len
        call add(l:covering, l:a.col)
      endif
    endfor
  endfor
  return empty(l:covering) ? 0 : min(l:covering)
endfunction

" Make room on line `to` for a note of width `len` at column `c` (spec 7.5):
" a dash before the column when a note ends right before it, dashes after it
" when the note would touch the next note (a 1-dash gap is kept) or the pipe.
" Dashes are inserted on every line. Returns {'lines', 'col'} (the column may
" move right by one), or {'error'}.
function! s:make_room(lines, to, c, len) abort
  let l:lines = a:lines
  let l:c = a:c
  let l:t = l:lines[a:to]
  if s:is_atom(l:t, l:c)
    return {'error': printf('string %s already has a note there', s:name(l:lines, a:to))}
  endif
  if l:c > 1 && s:is_atom(l:t, l:c - 1)
    if s:splits(l:lines, l:c - 1)
      return {'error': printf('no room on string %s', s:name(l:lines, a:to))}
    endif
    let l:lines = songwriter#tab#model#InsertColumns(l:lines, l:c - 1, 1, '-')
    let l:c += 1
    let l:t = l:lines[a:to]
  endif
  let l:free = len(matchstr(l:t, '^-*', l:c - 1))
  let l:next = l:t[l:c - 1 + l:free : l:c - 1 + l:free]
  if l:next ==# ''
    let l:lines[a:to] = l:t . repeat('-', l:c - 1 + a:len - len(l:t))
    return {'lines': l:lines, 'col': l:c}
  endif
  let l:k = a:len + (l:next ==# '|' ? 0 : 1) - l:free
  if l:k <= 0
    return {'lines': l:lines, 'col': l:c}
  endif
  " Insert after the latest offset in the dash run that splits no note.
  let l:o = l:c - 1 + l:free
  while l:o >= l:c && s:splits(l:lines, l:o)
    let l:o -= 1
  endwhile
  if l:o < l:c
    return {'error': printf('no room on string %s', s:name(l:lines, a:to))}
  endif
  return {'lines': songwriter#tab#model#InsertColumns(l:lines, l:o, l:k, '-'), 'col': l:c}
endfunction

" True when inserting after byte offset `o` would cut a note in two on a line.
function! s:splits(lines, o) abort
  for l:l in a:lines
    if s:is_atom(l:l, a:o) && s:is_atom(l:l, a:o + 1)
      return 1
    endif
  endfor
  return 0
endfunction

" True when column `col` of `line` is part of a note group.
function! s:is_atom(line, col) abort
  return a:col >= 3 && a:col <= len(a:line)
        \ && a:line[a:col - 1] =~# '^' . songwriter#grammar#TabAtom() . '$'
endfunction

" The string name of line `lin`.
function! s:name(lines, lin) abort
  return a:lines[a:lin][0]
endfunction

" Spec 7.3: `text` (a note group on line `from`) with every fret shifted by the
" interval between strings `from` and `to`, or {'error'}.
" Strings are taken to be listed from the highest to the lowest, neighbouring
" strings less than an octave apart: the interval is read from pitch classes.
" A mark without a fret (`x`) is returned unchanged.
function! s:repitch(lines, from, to, text) abort
  if a:text !~# '\d'
    return a:text
  endif
  for l:lin in [a:from, a:to]
    if songwriter#pitch#Class(s:name(a:lines, l:lin)) < 0
      return {'error': printf('string name %s is not a note', s:name(a:lines, l:lin))}
    endif
  endfor
  let [l:hi, l:lo] = a:to < a:from ? [a:to, a:from] : [a:from, a:to]
  let l:interval = (songwriter#pitch#Class(s:name(a:lines, l:hi))
        \ - songwriter#pitch#Class(s:name(a:lines, l:lo)) + 12) % 12
  if l:interval == 0
    return {'error': printf('cannot tell the interval between strings %s and %s',
          \ s:name(a:lines, l:hi), s:name(a:lines, l:lo))}
  endif
  let l:shift = a:to < a:from ? -l:interval : l:interval
  let l:frets = map(filter(split(a:text, '\D\+'), '!empty(v:val)'), 'str2nr(v:val, 10) + l:shift')
  if min(l:frets) < 0
    return {'error': printf('the fret would go below 0 on string %s', s:name(a:lines, a:to))}
  endif
  return substitute(a:text, '\d\+', '\=str2nr(submatch(0), 10) + l:shift', 'g')
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
