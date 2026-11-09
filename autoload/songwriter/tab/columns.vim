" autoload/songwriter/tab/columns.vim - the column model behind tablature-mode
" operators (spec [Tablature][[Editing]] 6). Pure: lines in, lines / ranges
" out. See design.md "Operators and text objects".
"
" A time column is the set of notes (note groups: `12`, `5h7`, `x`) starting
" at the same byte column on any string of a block. A range is [s, e], two
" 1-indexed inclusive byte columns, applied to every string of the block.
" Block lines are 0-indexed (`lin`), as in the linter.

" Note groups on a tab line, left to right, skipping the string name and the
" first pipe: [{'col', 'len', 'text'}].
function! songwriter#tab#columns#Atoms(line) abort
  let l:res = []
  let l:m = matchstrpos(a:line, songwriter#grammar#TabAtom(), 2)
  while l:m[1] >= 0
    call add(l:res, {'col': l:m[1] + 1, 'len': len(l:m[0]), 'text': l:m[0]})
    let l:m = matchstrpos(a:line, songwriter#grammar#TabAtom(), l:m[2])
  endwhile
  return l:res
endfunction

" Start columns of every note group on any string, sorted, unique.
function! songwriter#tab#columns#Columns(lines) abort
  let l:cols = []
  for l:l in a:lines
    call extend(l:cols, map(songwriter#tab#columns#Atoms(l:l), 'v:val.col'))
  endfor
  return uniq(sort(l:cols, 'n'))
endfunction

" The last column of time column `c`: the end of its longest note.
function! s:column_end(lines, c) abort
  let l:e = a:c
  for l:l in a:lines
    for l:a in songwriter#tab#columns#Atoms(l:l)
      if l:a.col == a:c
        let l:e = max([l:e, l:a.col + l:a.len - 1])
      endif
    endfor
  endfor
  return l:e
endfunction

" Columns of the bar around `col` on line `lin`, and the bar itself.
function! s:bar_columns(lines, lin, col) abort
  let l:bar = songwriter#tab#model#BarAt(a:lines[a:lin], a:col)
  let l:cols = filter(songwriter#tab#columns#Columns(a:lines),
        \ 'songwriter#tab#model#InBar(v:val, l:bar)')
  return [l:bar, l:cols]
endfunction

" The end of the gap after column `c` in `bar`: the next column of the bar, or
" the bar's closing pipe (the line end when unbounded), minus one.
function! s:gap_end(lines, lin, bar, cols, c) abort
  let l:next = filter(copy(a:cols), 'v:val > a:c')
  if !empty(l:next)
    return l:next[0] - 1
  endif
  return a:bar.end > 0 ? a:bar.end - 1 : len(a:lines[a:lin])
endfunction

" The time column for the cursor: the nearest column start at or left of `col`
" in its bar, else the bar's first column right of it; 0 when the bar has none.
function! s:column_for(cols, col) abort
  let l:left = filter(copy(a:cols), 'v:val <= a:col')
  if !empty(l:left)
    return l:left[-1]
  endif
  let l:right = filter(copy(a:cols), 'v:val > a:col')
  return empty(l:right) ? 0 : l:right[0]
endfunction

function! s:on_pipe_or_name(line, col) abort
  return a:col <= 1 || a:line[a:col - 1] ==# '|'
endfunction

" Spec 6.1.1 / 6.1.3: `ic` (around 0) / `ac` (around 1) with a count, from
" column `col` of line `lin`. [s, e], or [] on a pipe, the string name or in a
" bar without notes. A count stops at the bar's last column.
function! songwriter#tab#columns#ColumnObject(lines, lin, col, count, around) abort
  if s:on_pipe_or_name(a:lines[a:lin], a:col)
    return []
  endif
  let [l:bar, l:cols] = s:bar_columns(a:lines, a:lin, a:col)
  let l:c = s:column_for(l:cols, a:col)
  if l:c == 0
    return []
  endif
  let l:last = l:cols[min([index(l:cols, l:c) + max([a:count, 1]) - 1, len(l:cols) - 1])]
  let l:e = a:around ? s:gap_end(a:lines, a:lin, l:bar, l:cols, l:last)
        \ : s:column_end(a:lines, l:last)
  return [l:c, l:e]
endfunction

" Spec 6.1.2 / 6.1.3: `i|` (around 0) / `a|` (around 1, with the closing
" pipe) with a count. On a pipe, the bar to its right. [] on the string name,
" the last pipe or past it. A count stops at the tab's last bar.
function! songwriter#tab#columns#BarObject(lines, lin, col, count, around) abort
  let l:pipes = songwriter#tab#model#Pipes(a:lines[a:lin])
  let l:k = len(filter(copy(l:pipes), 'v:val <= a:col')) - 1
  if a:col <= 1 || l:k < 0 || l:k + 1 >= len(l:pipes)
    return []
  endif
  let l:k2 = min([l:k + max([a:count, 1]), len(l:pipes) - 1])
  return [l:pipes[l:k] + 1, l:pipes[l:k2] - (a:around ? 0 : 1)]
endfunction

" Spec 6.2: snap a motion's range [s, e] outward so it never cuts a note: s
" goes to the start of the note it is in, or, in a gap, to the previous column
" of its bar; e goes to the end of the note it is in, and a range ending on a
" note takes that note's gap too.
function! songwriter#tab#columns#Snap(lines, lin, s, e) abort
  let l:s = a:s
  let l:e = a:e
  let l:covered = 0
  let l:ends = 0
  for l:l in a:lines
    for l:a in songwriter#tab#columns#Atoms(l:l)
      let l:aend = l:a.col + l:a.len - 1
      if l:a.col <= a:s && a:s <= l:aend
        let l:s = min([l:s, l:a.col])
        let l:covered = 1
      endif
      if l:a.col <= a:e && a:e <= l:aend
        let l:e = max([l:e, l:aend])
      endif
    endfor
  endfor
  if !l:covered && !s:on_pipe_or_name(a:lines[a:lin], a:s)
    let [l:bar, l:cols] = s:bar_columns(a:lines, a:lin, a:s)
    let l:left = filter(copy(l:cols), 'v:val < a:s')
    if !empty(l:left)
      let l:s = l:left[-1]
    endif
  endif
  for l:l in a:lines
    for l:a in songwriter#tab#columns#Atoms(l:l)
      if l:a.col + l:a.len - 1 == l:e
        let l:ends = 1
      endif
    endfor
  endfor
  if l:ends && !s:on_pipe_or_name(a:lines[a:lin], l:e)
    let [l:bar, l:cols] = s:bar_columns(a:lines, a:lin, l:e)
    let l:e = s:gap_end(a:lines, a:lin, l:bar, l:cols, l:e)
  endif
  return [l:s, l:e]
endfunction

function! s:pad(line, width) abort
  return len(a:line) < a:width ? a:line . repeat('-', a:width - len(a:line)) : a:line
endfunction

" The columns [s, e] of every line (short lines padded with dashes).
function! songwriter#tab#columns#Extract(lines, s, e) abort
  return map(copy(a:lines), 'strpart(s:pad(v:val, a:e), a:s - 1, a:e - a:s + 1)')
endfunction

" Remove columns [s, e] from every line. When the range holds a bar line and
" does not start right after one, a pipe is put back at s: the bar where the
" range starts is closed there. Returns {'lines', 'rows'} (rows: what was
" removed, one per line).
function! songwriter#tab#columns#DeleteRange(lines, s, e) abort
  let l:rows = songwriter#tab#columns#Extract(a:lines, a:s, a:e)
  let l:out = []
  for l:i in range(len(a:lines))
    let l:l = s:pad(a:lines[l:i], a:e)
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
  return map(copy(a:lines),
        \ "v:val[0:1] . substitute(v:val[2:], songwriter#grammar#TabAtom(), '\\=repeat(\"-\", len(submatch(0)))', 'g')")
endfunction

" Spec 6.5.3: register rows for a block with `names`, matched from the bottom
" string. `regnames` is [] when unknown. {'rows', 'msg'} or {'error'}.
function! songwriter#tab#columns#MatchRows(names, rows, regnames) abort
  let l:ns = len(a:names)
  let l:nr = len(a:rows)
  let l:width = max(map(copy(a:rows), 'len(v:val)'))
  let l:rows = map(copy(a:rows), 's:pad(v:val, l:width)')
  if l:ns == l:nr
    return {'rows': l:rows, 'msg': ''}
  endif
  let l:filler = substitute(l:rows[0], '[^|]', '-', 'g')
  let l:out = []
  for l:i in range(l:ns)
    let l:j = l:i - (l:ns - l:nr)
    if l:j < 0
      call add(l:out, l:filler)
      continue
    endif
    if !empty(a:regnames) && a:regnames[l:j] !=# a:names[l:i]
      return {'error': printf('songwriter: string names differ (register vs tab): %s vs %s',
            \ a:regnames[l:j], a:names[l:i])}
    endif
    call add(l:out, l:rows[l:j])
  endfor
  let l:msgs = []
  if empty(a:regnames)
    call add(l:msgs, 'strings matched by position')
  endif
  let l:dropped = 0
  for l:j in range(max([l:nr - l:ns, 0]))
    let l:dropped += len(filter(split(l:rows[l:j], '[-|]\+'), '!empty(v:val)'))
  endfor
  if l:dropped > 0
    call add(l:msgs, l:dropped . ' notes dropped')
  endif
  return {'rows': l:out, 'msg': empty(l:msgs) ? '' : 'songwriter: ' . join(l:msgs, ', ')}
endfunction

" Spec 6.5: paste blockwise register `rows` (source string names `regnames`,
" [] when unknown) into the block, from column `col` of line `lin`; `before`
" for `P`; `count` copies. A register holding a pipe is a bar register (6.5.2),
" pasted at a bar line; otherwise a column register (6.5.1), pasted after /
" before the cursor's column and its gap. Returns {'lines', 'col' (first
" pasted note, any string), 'msg'} or {'error'}.
function! songwriter#tab#columns#Paste(lines, lin, col, rows, regnames, before, count) abort
  let l:names = map(copy(a:lines), 'v:val[0]')
  let l:m = songwriter#tab#columns#MatchRows(l:names, a:rows, a:regnames)
  if has_key(l:m, 'error')
    return l:m
  endif
  let l:rows = l:m.rows
  let l:line = a:lines[a:lin]
  let l:col = max([a:col, 2])
  if !empty(filter(copy(l:rows), "stridx(v:val, '|') >= 0"))
    call map(l:rows, "substitute(v:val, '^|', '', '')")
    call map(l:rows, "v:val =~# '|$' ? v:val : v:val . '|'")
    let l:pipes = songwriter#tab#model#Pipes(l:line)
    if index(l:pipes, l:col) >= 0
      let l:offset = l:col
    else
      let l:bar = songwriter#tab#model#BarAt(l:line, l:col)
      let l:offset = a:before ? l:bar.start : (l:bar.end > 0 ? l:bar.end : len(l:line))
    endif
  else
    let [l:bar, l:cols] = s:bar_columns(a:lines, a:lin, l:col)
    let l:c = s:column_for(l:cols, l:col)
    if l:c == 0
      let l:offset = l:bar.start + 2
    else
      let l:offset = a:before ? l:c - 1 : s:gap_end(a:lines, a:lin, l:bar, l:cols, l:c)
    endif
  endif
  let l:res = s:insert_rows(a:lines, l:offset, l:rows, a:count)
  let l:res.msg = l:m.msg
  return l:res
endfunction

" Spec 6.9.4: paste register `rows` right after byte `offset` (0 = line
" start), rows matched as in Paste. {'lines', 'col', 'msg'} or {'error'}.
function! songwriter#tab#columns#PasteAt(lines, offset, rows, regnames) abort
  let l:m = songwriter#tab#columns#MatchRows(map(copy(a:lines), 'v:val[0]'), a:rows, a:regnames)
  if has_key(l:m, 'error')
    return l:m
  endif
  let l:res = s:insert_rows(a:lines, a:offset, l:m.rows, 1)
  let l:res.msg = l:m.msg
  return l:res
endfunction

" Insert `count` copies of `rows` after byte `offset` on every line. Returns
" {'lines', 'col': the first inserted note on any string}.
function! s:insert_rows(lines, offset, rows, count) abort
  let l:rows = map(copy(a:rows), 'repeat(v:val, max([a:count, 1]))')
  let l:out = []
  for l:i in range(len(a:lines))
    let l:l = s:pad(a:lines[l:i], a:offset)
    call add(l:out, strpart(l:l, 0, a:offset) . l:rows[l:i] . strpart(l:l, a:offset))
  endfor
  let l:first = 0
  for l:r in l:rows
    let l:p = match(l:r, songwriter#grammar#TabAtom())
    if l:p >= 0 && (l:first == 0 || l:p + 1 < l:first)
      let l:first = l:p + 1
    endif
  endfor
  return {'lines': l:out, 'col': a:offset + max([l:first, 1])}
endfunction

" Spec 6.7: erase the note at column `col` of line `lin`. Shared column (6.7.1):
" the note becomes dashes. Lone column (6.7.2): the column and its gap go on
" every string. Returns {'lines', 'col', 'rows'} where rows is what `ac` would
" yank with the other strings as dashes (6.7.3), or {} off a note.
function! songwriter#tab#columns#EraseNote(lines, lin, col) abort
  let l:note = {}
  for l:a in songwriter#tab#columns#Atoms(a:lines[a:lin])
    if l:a.col <= a:col && a:col < l:a.col + l:a.len
      let l:note = l:a
    endif
  endfor
  if empty(l:note)
    return {}
  endif
  let l:c = l:note.col
  let l:shared = 0
  for l:i in range(len(a:lines))
    if l:i != a:lin && !empty(filter(songwriter#tab#columns#Atoms(a:lines[l:i]), 'v:val.col == l:c'))
      let l:shared = 1
    endif
  endfor
  let [l:bar, l:cols] = s:bar_columns(a:lines, a:lin, l:c)
  let l:e = s:gap_end(a:lines, a:lin, l:bar, l:cols, l:c)
  let l:rows = songwriter#tab#columns#Extract(a:lines, l:c, l:e)
  for l:i in range(len(l:rows))
    if l:i != a:lin
      let l:rows[l:i] = repeat('-', len(l:rows[l:i]))
    endif
  endfor
  if l:shared
    let l:out = copy(a:lines)
    let l:l = a:lines[a:lin]
    let l:out[a:lin] = strpart(l:l, 0, l:c - 1) . repeat('-', l:note.len) . strpart(l:l, l:c - 1 + l:note.len)
  else
    let l:out = songwriter#tab#columns#DeleteRange(a:lines, l:c, l:e).lines
  endif
  return {'lines': l:out, 'col': l:c, 'rows': l:rows}
endfunction

" Spec 6.6: a slot in the (empty) bar around column `col` of line `lin`: the
" bar's content becomes 5 dashes on every string and the slot is the middle
" one. Returns {'lines', 'col'}, or {} outside a bar.
function! songwriter#tab#columns#EmptyBarSlot(lines, lin, col) abort
  let l:bar = songwriter#tab#model#BarAt(a:lines[a:lin], a:col)
  if l:bar.start == 0 || l:bar.end == 0
    return {}
  endif
  let l:out = map(copy(a:lines),
        \ 'strpart(v:val, 0, l:bar.start) . "-----" . strpart(v:val, l:bar.end - 1)')
  return {'lines': l:out, 'col': l:bar.start + 3}
endfunction

" Spec 6.13: move the time column at `col` of line `lin` one dash later (dir
" +1: a dash inserted before it on every string) or earlier (dir -1: a dash
" removed before it, keeping at least one dash after the previous note on any
" string). Returns {'lines', 'col'}, or {} when nothing changes, including on
" a bar's first column (lint keeps two dashes after the pipe there).
function! songwriter#tab#columns#ShiftColumn(lines, lin, col, dir) abort
  if s:on_pipe_or_name(a:lines[a:lin], a:col)
    return {}
  endif
  let [l:bar, l:cols] = s:bar_columns(a:lines, a:lin, a:col)
  let l:c = s:column_for(l:cols, a:col)
  if l:c == 0 || l:c == l:cols[0]
    return {}
  endif
  if a:dir > 0
    return {'lines': songwriter#tab#model#InsertColumns(a:lines, l:c - 1, 1, '-'), 'col': l:c + 1}
  endif
  let l:prev_end = 0
  for l:l in a:lines
    for l:a in songwriter#tab#columns#Atoms(l:l)
      if l:a.col < l:c && songwriter#tab#model#InBar(l:a.col, l:bar)
        let l:prev_end = max([l:prev_end, l:a.col + l:a.len - 1])
      endif
    endfor
  endfor
  if l:c - l:prev_end - 1 < 2
    return {}
  endif
  return {'lines': songwriter#tab#columns#DeleteRange(a:lines, l:c - 1, l:c - 1).lines, 'col': l:c - 1}
endfunction

" Spec 6.14: write the notes of column register `rows` onto the time column at
" `col` of line `lin`, without adding time: the register's first note column
" lands on that column. Rows are matched as in Paste. Returns {'lines', 'col',
" 'msg'}, or {'error'} for a bar register, no column there, or a note that
" would replace anything but dashes.
function! songwriter#tab#columns#Overlay(lines, lin, col, rows, regnames) abort
  if !empty(filter(copy(a:rows), "stridx(v:val, '|') >= 0"))
    return {'error': 'songwriter: gp pastes a column, not a bar'}
  endif
  let l:m = songwriter#tab#columns#MatchRows(map(copy(a:lines), 'v:val[0]'), a:rows, a:regnames)
  if has_key(l:m, 'error')
    return l:m
  endif
  let l:c = 0
  if !s:on_pipe_or_name(a:lines[a:lin], a:col)
    let [l:bar, l:cols] = s:bar_columns(a:lines, a:lin, a:col)
    let l:c = s:column_for(l:cols, a:col)
  endif
  if l:c == 0
    return {'error': 'songwriter: gp needs a note column under the cursor'}
  endif
  let l:atoms = map(copy(l:m.rows), 's:row_atoms(v:val)')
  let l:starts = []
  for l:r in l:atoms
    call extend(l:starts, map(copy(l:r), 'v:val.col'))
  endfor
  if empty(l:starts)
    return {'lines': copy(a:lines), 'col': l:c, 'msg': l:m.msg}
  endif
  let l:qmin = min(l:starts)
  let l:out = copy(a:lines)
  for l:i in range(len(l:out))
    for l:a in l:atoms[l:i]
      let l:s = l:c + l:a.col - l:qmin
      let l:line = s:pad(l:out[l:i], l:s + l:a.len)
      if strpart(l:line, l:s - 1, l:a.len) !~# '^-\+$'
        return {'error': printf('songwriter: gp would replace a note on string %s', a:lines[l:i][0])}
      endif
      let l:out[l:i] = strpart(l:line, 0, l:s - 1) . l:a.text . strpart(l:line, l:s - 1 + l:a.len)
    endfor
  endfor
  return {'lines': l:out, 'col': l:c, 'msg': l:m.msg}
endfunction

" Note groups of a register row (no string name), with 1-indexed columns.
function! s:row_atoms(row) abort
  let l:res = []
  let l:m = matchstrpos(a:row, songwriter#grammar#TabAtom())
  while l:m[1] >= 0
    call add(l:res, {'col': l:m[1] + 1, 'len': len(l:m[0]), 'text': l:m[0]})
    let l:m = matchstrpos(a:row, songwriter#grammar#TabAtom(), l:m[2])
  endwhile
  return l:res
endfunction
