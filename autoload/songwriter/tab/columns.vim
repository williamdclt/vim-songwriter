" autoload/songwriter/tab/columns.vim - editing time columns (spec
" [Tablature][[Editing]] 6, 7.5): extract, delete and erase columns and notes,
" shift a column, make room for a note. Pure: lines in, lines out, each
" function parsing `lines` once (model#Parse) for the model's queries. See
" design.md "Operators and text objects"; text objects are in tab/objects.vim,
" pasting in tab/paste.vim.
"
" A time column is the set of notes (`12`, `x`; the 5 and the 7 of `5h7` are
" two) starting at the same byte column on any string of a block. A range is
" [s, e], two 1-indexed inclusive byte columns, applied to every string of the
" block. Block lines are 0-indexed (`lin`), as in the linter.

" True when column `col` of `line` is its string name or a pipe.
function! songwriter#tab#columns#OnPipeOrName(line, col) abort
  return a:col < songwriter#tab#model#BodyOffset() || a:line[a:col - 1] ==# '|'
endfunction

" Spec 6.2.2 / 6.1.4: erase every note of line `lin` that lies in [s, e], each
" as `x` does (EraseSet). {'lines', 'rows' (what `x` writes for each note, left
" to right), 'col' (the first erased note), 'removed' (a column went)}, or {}
" when there is no note there.
function! songwriter#tab#columns#EraseNotes(lines, lin, s, e) abort
  let l:notes = filter(songwriter#tab#model#Notes(a:lines[a:lin]),
        \ 'v:val.col <= a:e && a:s < v:val.col + v:val.len')
  if empty(l:notes)
    return {}
  endif
  let l:res = songwriter#tab#columns#EraseSet(a:lines,
        \ map(l:notes, {_, n -> {'lin': a:lin, 'col': n.col}}))
  let l:rows = map(copy(a:lines), '""')
  for l:r in l:res.rows
    let l:rows = map(l:rows, 'v:val . l:r[v:key]')
  endfor
  return {'lines': l:res.lines, 'rows': l:rows, 'col': l:res.col, 'removed': l:res.removed}
endfunction

" Erase the notes `notes` ([{'lin', 'col'}], any column of each note, on any
" strings), each as `x` does (EraseNote), right to left so that a removed
" column does not shift the next ones; on one column, the last note erased
" takes the column with it when it goes (6.7.2). {'lines', 'rows' (what `x`
" writes for each note, left to right), 'col' (the leftmost note's start),
" 'removed' (a column went)}.
function! songwriter#tab#columns#EraseSet(lines, notes) abort
  let l:notes = map(copy(a:notes), {_, n -> extend(copy(n),
        \ {'col': songwriter#tab#model#NoteAt(a:lines[n.lin], n.col).col})})
  call sort(l:notes, {a, b -> a.col != b.col ? b.col - a.col : a.lin - b.lin})
  let l:lines = a:lines
  let l:rows = []
  for l:n in l:notes
    let l:res = songwriter#tab#columns#EraseNote(l:lines, l:n.lin, l:n.col)
    call insert(l:rows, l:res.rows)
    let l:lines = l:res.lines
  endfor
  return {'lines': l:lines, 'rows': l:rows, 'col': l:notes[-1].col,
        \ 'removed': len(l:lines[0]) < len(a:lines[0])}
endfunction

" The columns [s, e] of every line (short lines padded with dashes).
function! songwriter#tab#columns#Extract(lines, s, e) abort
  return map(copy(a:lines), 'strpart(songwriter#tab#model#Pad(v:val, a:e), a:s - 1, a:e - a:s + 1)')
endfunction

" Remove columns [s, e] from every line. When the range holds a bar line and
" does not start right after one, a pipe is put back at s: the bar where the
" range starts is closed there. Returns {'lines', 'rows'} (rows: what was
" removed, one per line).
function! songwriter#tab#columns#DeleteRange(lines, s, e) abort
  let l:rows = songwriter#tab#columns#Extract(a:lines, a:s, a:e)
  let l:out = []
  for l:i in range(len(a:lines))
    let l:l = songwriter#tab#model#Pad(a:lines[l:i], a:e)
    let l:keep = strpart(l:l, 0, a:s - 1)
    if stridx(l:rows[l:i], '|') >= 0 && l:keep[-1:] !=# '|'
      let l:keep .= '|'
    endif
    call add(l:out, l:keep . strpart(l:l, a:e))
  endfor
  return {'lines': l:out, 'rows': l:rows}
endfunction

" Spec 6.3.1: every note becomes dashes; bars and pipes are kept.
function! songwriter#tab#columns#ClearNotes(lines) abort
  let l:o = songwriter#tab#model#BodyOffset()
  return map(copy(a:lines),
        \ "strpart(v:val, 0, l:o) . substitute(strpart(v:val, l:o), songwriter#grammar#Chain(), '\\=repeat(\"-\", len(submatch(0)))', 'g')")
endfunction

" Spec 6.7: erase the note at column `col` of line `lin`. Shared column (6.7.1):
" the note becomes dashes. Lone column (6.7.2): the column and its gap go on
" every string, as far as another string's notes stay apart: the end of the
" removed range comes back until no other string loses a note or separator
" there, nor has two of its notes or chains joined. When not even the note's
" own columns can go, the note becomes dashes, as on a shared column. Returns
" {'lines', 'col', 'rows'} where rows is what `ac` would yank with the other
" strings as dashes (6.7.3), or {} off a note.
function! songwriter#tab#columns#EraseNote(lines, lin, col) abort
  let l:note = songwriter#tab#model#NoteAt(a:lines[a:lin], a:col)
  if empty(l:note)
    return {}
  endif
  let l:tab = songwriter#tab#model#Parse(0, a:lines)
  let l:c = l:note.col
  let l:shared = songwriter#tab#model#IsShared(l:tab, a:lin, l:c)
  let l:e = songwriter#tab#model#GapEnd(l:tab, a:lin, songwriter#tab#model#BarColumns(l:tab, a:lin, l:c), l:c)
  let l:rows = songwriter#tab#columns#Extract(a:lines, l:c, l:e)
  for l:i in range(len(l:rows))
    if l:i != a:lin
      let l:rows[l:i] = repeat('-', len(l:rows[l:i]))
    endif
  endfor
  if !l:shared
    let l:end = l:e
    while l:end >= songwriter#tab#model#NoteEnd(l:note) && !s:removable(a:lines, a:lin, l:c, l:end)
      let l:end -= 1
    endwhile
  endif
  if l:shared || l:end < songwriter#tab#model#NoteEnd(l:note)
    let l:out = copy(a:lines)
    let l:out[a:lin] = songwriter#tab#model#Blank(a:lines[a:lin], l:note)
  else
    let l:out = songwriter#tab#columns#DeleteRange(a:lines, l:c, l:end).lines
  endif
  return {'lines': l:out, 'col': l:c, 'rows': l:rows}
endfunction

" True when columns [s, e] can be removed from every line but `lin` without
" changing its music: only dashes there (or nothing), and not a chain on both
" sides, which removing them would join.
function! s:removable(lines, lin, s, e) abort
  for l:i in range(len(a:lines))
    let l:l = a:lines[l:i]
    if l:i == a:lin
      continue
    endif
    if strpart(l:l, a:s - 1, a:e - a:s + 1) =~# '[^-]'
          \ || s:in_chain(l:l, a:s - 1) && s:in_chain(l:l, a:e + 1)
      return 0
    endif
  endfor
  return 1
endfunction

" Spec 6.13: move the time column at `col` of line `lin` one dash later (dir
" +1: a dash inserted before it on every string) or earlier (dir -1: a column
" of dashes before it removed, keeping at least one dash after the previous note
" on any string; a separator is never removed). Returns {'lines', 'col'}, or {} when nothing changes, including on
" a bar's first column (lint keeps two dashes after the pipe there).
function! songwriter#tab#columns#ShiftColumn(lines, lin, col, dir) abort
  if songwriter#tab#columns#OnPipeOrName(a:lines[a:lin], a:col)
    return {}
  endif
  let l:tab = songwriter#tab#model#Parse(0, a:lines)
  let l:bc = songwriter#tab#model#BarColumns(l:tab, a:lin, a:col)
  let l:c = songwriter#tab#model#ColumnFor(l:bc.cols, a:col)
  if l:c == 0 || l:c == l:bc.cols[0]
    return {}
  endif
  if a:dir > 0
    return {'lines': songwriter#tab#model#InsertColumns(a:lines, l:c - 1, 1, '-'), 'col': l:c + 1}
  endif
  let l:prev_end = 0
  for l:a in songwriter#tab#model#BarNotes(l:tab, l:bc.bar)
    if l:a.col < l:c
      let l:prev_end = max([l:prev_end, songwriter#tab#model#NoteEnd(l:a)])
    endif
  endfor
  if l:c - l:prev_end - 1 < 2
    return {}
  endif
  let l:o = l:c - 1
  while l:o > l:prev_end && !s:all_dashes(a:lines, l:o)
    let l:o -= 1
  endwhile
  if l:o <= l:prev_end
    return {}
  endif
  return {'lines': songwriter#tab#columns#DeleteRange(a:lines, l:o, l:o).lines, 'col': l:c - 1}
endfunction

" True when column `col` holds a dash (or nothing) on every line.
function! s:all_dashes(lines, col) abort
  return empty(filter(copy(a:lines), "v:val[a:col - 1] !=# '-' && v:val[a:col - 1] !=# ''"))
endfunction

" Make room on line `to` for a note of width `len` at column `c` (spec 7.5, 10.5):
" a dash before the column when a note ends right before it, dashes after it
" when the note would touch the next note (a 1-dash gap is kept) or the pipe.
" Dashes are inserted on every line. Returns {'lines', 'col'} (the column may
" move right by one), or {'error'}.
function! songwriter#tab#columns#MakeRoom(lines, to, c, len) abort
  let l:lines = a:lines
  let l:c = a:c
  let l:t = l:lines[a:to]
  if s:in_chain(l:t, l:c)
    return {'error': printf('string %s already has a note there', songwriter#tab#model#Name(l:lines[a:to]))}
  endif
  if l:c > 1 && s:in_chain(l:t, l:c - 1)
    if s:splits(l:lines, l:c - 1)
      return {'error': printf('no room on string %s', songwriter#tab#model#Name(l:lines[a:to]))}
    endif
    let l:lines = songwriter#tab#model#InsertColumns(l:lines, l:c - 1, 1, '-')
    let l:c += 1
    let l:t = l:lines[a:to]
  endif
  let l:free = len(matchstr(l:t, songwriter#grammar#DashRun(), l:c - 1))
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
    return {'error': printf('no room on string %s', songwriter#tab#model#Name(l:lines[a:to]))}
  endif
  return {'lines': songwriter#tab#model#InsertColumns(l:lines, l:o, l:k, '-'), 'col': l:c}
endfunction

" Write `text`, a note, at column `c` of line `to`, room made for it as
" MakeRoom does. Returns {'lines', 'col'} (where it went), or {'error'}.
function! songwriter#tab#columns#PutNote(lines, to, c, text) abort
  let l:room = songwriter#tab#columns#MakeRoom(a:lines, a:to, a:c, len(a:text))
  if has_key(l:room, 'error')
    return l:room
  endif
  let l:room.lines[a:to] = songwriter#tab#model#Splice(l:room.lines[a:to], l:room.col, len(a:text), a:text)
  return l:room
endfunction

" Rewrite the note starting at column `c` of line `lin` as `text` (another
" note), keeping every note on its time column, this one included (spec 3.4,
" 11.2). A narrower note leaves dashes after it, even before a separator
" (`10h7` -> `9-h7`). A wider one takes the dashes after it, as long as one
" stays before the next chain on its string (none is needed before a pipe) and
" it covers no other string's time column; the rest of the room is dashes
" inserted on every string between the note and the next time column, so all
" that follows moves together. A separator right after the note stays attached
" to it. Returns {'lines', 'col'} (the note's column), or {'error'} when the
" room would cut a note in two on another string.
function! songwriter#tab#columns#SetNote(lines, lin, c, text) abort
  let l:lines = copy(a:lines)
  let l:t = l:lines[a:lin]
  let l:old = songwriter#tab#model#NoteAt(l:t, a:c)
  let l:w = len(a:text)
  let l:end = a:c + l:old.len - 1
  if l:w <= l:old.len
    let l:lines[a:lin] = songwriter#tab#model#Splice(l:t, a:c, l:old.len,
          \ a:text . repeat('-', l:old.len - l:w))
    return {'lines': l:lines, 'col': a:c}
  endif
  let l:free = len(matchstr(l:t, songwriter#grammar#DashRun(), l:end))
  let l:next = l:t[l:end + l:free : l:end + l:free]
  let l:spare = l:next ==# '' ? l:w : l:free - (l:next ==# '|' || l:free == 0 ? 0 : 1)
  let l:k = l:w - l:old.len - l:spare
  let l:later = filter(songwriter#tab#model#NoteColumns(songwriter#tab#model#Parse(1, l:lines)),
        \ 'v:val > a:c')
  let l:last = l:end + l:free
  if !empty(l:later)
    let l:k = max([l:k, a:c + l:w - l:later[0]])
    let l:last = min([l:last, l:later[0] - 1])
  endif
  if l:k > 0
    " Insert after the latest offset before the next column that splits no
    " note on another string.
    let l:o = l:last
    while l:o >= l:end && s:splits(s:others(l:lines, a:lin), l:o)
      let l:o -= 1
    endwhile
    if l:o < l:end
      return {'error': printf('no room on string %s', songwriter#tab#model#Name(l:t))}
    endif
    let l:lines = songwriter#tab#model#InsertColumns(l:lines, l:o, l:k, '-')
  endif
  let l:t = songwriter#tab#model#Pad(l:lines[a:lin], a:c + l:w - 1)
  let l:lines[a:lin] = songwriter#tab#model#Splice(l:t, a:c, l:w, a:text)
  return {'lines': l:lines, 'col': a:c}
endfunction

" `lines` without line `lin`.
function! s:others(lines, lin) abort
  return filter(copy(a:lines), 'v:key != a:lin')
endfunction

" True when inserting after byte offset `o` would cut a note in two on a line.
function! s:splits(lines, o) abort
  for l:l in a:lines
    if s:in_chain(l:l, a:o) && s:in_chain(l:l, a:o + 1)
      return 1
    endif
  endfor
  return 0
endfunction

" True when column `col` of `line` is part of a chain.
function! s:in_chain(line, col) abort
  return a:col > songwriter#tab#model#BodyOffset() && a:col <= len(a:line)
        \ && songwriter#grammar#IsChainChar(a:line[a:col - 1])
endfunction
