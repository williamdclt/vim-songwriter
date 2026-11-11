" autoload/songwriter/tab/columns.vim - the column model behind tablature-mode
" operators (spec [Tablature][[Editing]] 6). Pure: lines in, lines / ranges
" out. See design.md "Operators and text objects".
"
" A time column is the set of notes (`12`, `x`; the 5 and the 7 of `5h7` are two) starting
" at the same byte column on any string of a block. A range is [s, e], two
" 1-indexed inclusive byte columns, applied to every string of the block.
" Block lines are 0-indexed (`lin`), as in the linter.

" Start columns of every note on any string, sorted, unique.
function! songwriter#tab#columns#Columns(lines) abort
  let l:cols = []
  for l:l in a:lines
    call extend(l:cols, map(songwriter#tab#model#Notes(l:l), 'v:val.col'))
  endfor
  return uniq(sort(l:cols, 'n'))
endfunction

" The last column of time column `c`: the end of its longest note.
function! s:column_end(lines, c) abort
  let l:e = a:c
  for l:l in a:lines
    for l:a in songwriter#tab#model#Notes(l:l)
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

" True when column `col` of `line` is its string name or a pipe.
function! songwriter#tab#columns#OnPipeOrName(line, col) abort
  return a:col < songwriter#tab#model#BodyOffset() || a:line[a:col - 1] ==# '|'
endfunction

" Spec 6.1.1 / 6.1.3: `ic` (around 0) / `ac` (around 1) with a count, from
" column `col` of line `lin`. [s, e], or [] on a pipe, the string name or in a
" bar without notes. A count stops at the bar's last column.
function! songwriter#tab#columns#ColumnObject(lines, lin, col, count, around) abort
  if songwriter#tab#columns#OnPipeOrName(a:lines[a:lin], a:col)
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
  if a:col < songwriter#tab#model#BodyOffset() || l:k < 0 || l:k + 1 >= len(l:pipes)
    return []
  endif
  let l:k2 = min([l:k + max([a:count, 1]), len(l:pipes) - 1])
  return [l:pipes[l:k] + 1, l:pipes[l:k2] - (a:around ? 0 : 1)]
endfunction

" `ic`/`ac` (kind 'c') or `i|`/`a|` (kind '|').
function! songwriter#tab#columns#Object(kind, lines, lin, col, count, around) abort
  return a:kind ==# 'c'
        \ ? songwriter#tab#columns#ColumnObject(a:lines, a:lin, a:col, a:count, a:around)
        \ : songwriter#tab#columns#BarObject(a:lines, a:lin, a:col, a:count, a:around)
endfunction

" Spec 6.1.4: `in`/`an`, the note at `col` on line `lin`, or on a dash the
" nearest note of the string to the left in the bar. [s, e] or [].
function! songwriter#tab#columns#NoteObject(lines, lin, col, around) abort
  let l:line = a:lines[a:lin]
  let l:bar = songwriter#tab#model#BarAt(l:line, a:col)
  let l:notes = filter(songwriter#tab#model#Notes(l:line),
        \ 'v:val.col <= a:col && songwriter#tab#model#InBar(v:val.col, l:bar)')
  if empty(l:notes)
    return []
  endif
  let l:n = l:notes[-1]
  if !a:around
    return [l:n.col, l:n.col + l:n.len - 1]
  endif
  let l:column = songwriter#tab#columns#ColumnObject(a:lines, a:lin, l:n.col, 1, 1)
  return [l:n.col, max([l:column[1], l:n.col + l:n.len - 1])]
endfunction

" Spec 6.1.5: `iw`/`aw`, the word (3.2) at `col` on line `lin`, or on a dash
" the nearest word of the string to the left in the bar; `aw` also takes the
" gap after it, as `an`. [s, e] or [].
function! songwriter#tab#columns#WordObject(lines, lin, col, around) abort
  let l:line = a:lines[a:lin]
  let l:bar = songwriter#tab#model#BarAt(l:line, a:col)
  let l:words = filter(songwriter#tab#model#Words(l:line),
        \ 'v:val.start <= a:col && songwriter#tab#model#InBar(v:val.start, l:bar)')
  if empty(l:words)
    return []
  endif
  let l:w = l:words[-1]
  if !a:around
    return [l:w.start, l:w.end]
  endif
  let l:column = songwriter#tab#columns#ColumnObject(a:lines, a:lin, l:w.last, 1, 1)
  return [l:w.start, max([l:column[1], l:w.end])]
endfunction

" `in`/`an` (kind 'n') or `iw`/`aw` (kind 'w').
function! songwriter#tab#columns#StringObject(kind, lines, lin, col, around) abort
  return a:kind ==# 'w'
        \ ? songwriter#tab#columns#WordObject(a:lines, a:lin, a:col, a:around)
        \ : songwriter#tab#columns#NoteObject(a:lines, a:lin, a:col, a:around)
endfunction

" Where a tablature-mode motion can stop, sorted: `w`/`b` the first notes of
" the words of `line`, `e`/`ge` their last notes (3.2), `l`/`h` the time
" columns of the block.
function! songwriter#tab#columns#Stops(lines, line, key) abort
  if a:key =~# '^[wb]$'
    return map(songwriter#tab#model#Words(a:line), 'v:val.first')
  elseif a:key =~# '^g\=e$'
    return map(songwriter#tab#model#Words(a:line), 'v:val.last')
  endif
  return songwriter#tab#columns#Columns(a:lines)
endfunction

" Spec 6.2.2: the range [s, e] on `line` that the string motion `key` covers
" from column `col`, `count` times, trimmed to the notes it covers: from the
" start of the first to the end of the last. `l`/`h` count notes of the
" string (`l` from the note under the cursor), `w`/`b`/`e`/`ge` words. []
" when it covers no note.
function! songwriter#tab#columns#StringMotion(lines, line, col, key, count) abort
  let l:notes = songwriter#tab#model#Notes(a:line)
  let l:count = max([a:count, 1])
  if a:key ==# 'l'
    let l:i = index(map(copy(l:notes), 'v:val.col <= a:col && a:col < v:val.col + v:val.len'), 1)
    if l:i < 0
      return []
    endif
    let l:range = [l:notes[l:i].col, l:notes[min([l:i + l:count, len(l:notes)]) - 1].col]
  elseif a:key ==# 'h'
    let l:at = a:col
    for l:n in l:notes
      if l:n.col <= a:col && a:col < l:n.col + l:n.len
        let l:at = l:n.col
      endif
    endfor
    let l:before = filter(copy(l:notes), 'v:val.col < l:at')
    if empty(l:before)
      return []
    endif
    let l:range = [l:before[max([len(l:before) - l:count, 0])].col, l:at - 1]
  else
    let l:stops = songwriter#tab#columns#Stops(a:lines, a:line, a:key)
    let l:fwd = a:key =~# '^[we]$'
    let l:to = songwriter#tab#model#Advance(l:stops, a:col, l:fwd ? 1 : -1, l:count)
    if l:to == a:col && a:key !=# 'w'
      return []
    endif
    let l:range = a:key ==# 'w' ? [a:col, l:to == a:col ? len(a:line) : l:to - 1]
          \ : a:key ==# 'b' ? [l:to, a:col - 1]
          \ : a:key ==# 'e' ? [a:col, l:to]
          \ : [l:to, a:col]
  endif
  let l:covered = filter(l:notes, 'v:val.col <= l:range[1] && l:range[0] < v:val.col + v:val.len')
  if empty(l:covered)
    return []
  endif
  return [l:covered[0].col, l:covered[-1].col + l:covered[-1].len - 1]
endfunction

" Spec 6.2.2 / 6.1.4: erase every note of line `lin` that lies in [s, e], each
" as `x` does (EraseNote), right to left so that a removed column does not
" shift the next ones. {'lines', 'rows' (what `x` writes for each note, left to
" right), 'col' (the first erased note), 'removed' (a column went)}, or {}
" when there is no note there.
function! songwriter#tab#columns#EraseNotes(lines, lin, s, e) abort
  let l:notes = filter(songwriter#tab#model#Notes(a:lines[a:lin]),
        \ 'v:val.col <= a:e && a:s < v:val.col + v:val.len')
  if empty(l:notes)
    return {}
  endif
  let l:first = l:notes[0].col
  let l:lines = a:lines
  let l:rows = map(copy(a:lines), '""')
  for l:n in reverse(l:notes)
    let l:res = songwriter#tab#columns#EraseNote(l:lines, a:lin, l:n.col)
    let l:rows = map(l:rows, 'l:res.rows[v:key] . v:val')
    let l:lines = l:res.lines
  endfor
  return {'lines': l:lines, 'rows': l:rows, 'col': l:first,
        \ 'removed': len(l:lines[a:lin]) < len(a:lines[a:lin])}
endfunction

" Spec [Tablature][[Editing]] 3.5: where the bar motion `key` goes from column
" `col` of `line`, a line of the block `lines`, `count` times, stopping at the
" last bar reached:
"   W: the first time column of the next bar (the first bar starting at or
"      after `col`, so on a pipe, the bar after it);
"   B: the first time column of the cursor's bar, or of the previous bar when
"      the cursor is on it or before it;
"   E: the last time column of the cursor's bar, or of the next bar when the
"      cursor is on it or after it.
" Bars are read from `line`'s pipes, time columns from the whole block; a bar
" with no note stands for its middle dash.
function! songwriter#tab#columns#BarStop(lines, line, col, key, count) abort
  let l:bars = s:bar_stops(a:lines, a:line)
  let l:col = a:col
  for l:_ in range(a:count)
    if a:key ==# 'W'
      let l:next = filter(copy(l:bars), 'v:val.start >= l:col')
      let l:col = empty(l:next) ? l:col : l:next[0].first
    elseif a:key ==# 'B'
      let l:prev = filter(copy(l:bars), 'v:val.first < l:col')
      let l:col = empty(l:prev) ? l:col : l:prev[-1].first
    else
      let l:next = filter(copy(l:bars), 'v:val.last > l:col')
      let l:col = empty(l:next) ? l:col : l:next[0].last
    endif
  endfor
  return l:col
endfunction

" The bars of `line`, left to right: {start (its opening pipe), first, last
" (its first and last time column of the block `lines`, or both its middle
" dash when it has no note)}. A bar with nothing between its pipes is left out.
function! s:bar_stops(lines, line) abort
  let l:pipes = songwriter#tab#model#Pipes(a:line)
  let l:cols = songwriter#tab#columns#Columns(a:lines)
  let l:bars = []
  for l:i in range(len(l:pipes) - 1)
    let [l:s, l:e] = l:pipes[l:i : l:i + 1]
    if l:e == l:s + 1
      continue
    endif
    let l:in = filter(copy(l:cols), 'l:s < v:val && v:val < l:e')
    let l:mid = l:s + (l:e - l:s) / 2
    call add(l:bars, {'start': l:s,
          \ 'first': empty(l:in) ? l:mid : l:in[0], 'last': empty(l:in) ? l:mid : l:in[-1]})
  endfor
  return l:bars
endfunction

" Spec 6.2.3: snap a motion's range [s, e] outward so it never cuts a note: s
" goes to the start of the note it is in, or, in a gap, to the previous column
" of its bar; e goes to the end of the note it is in, and a range ending on a
" note takes that note's gap too.
function! songwriter#tab#columns#Snap(lines, lin, s, e) abort
  let l:s = a:s
  let l:e = a:e
  let l:covered = 0
  let l:ends = 0
  for l:l in a:lines
    for l:a in songwriter#tab#model#Notes(l:l)
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
  if !l:covered && !songwriter#tab#columns#OnPipeOrName(a:lines[a:lin], a:s)
    let [l:bar, l:cols] = s:bar_columns(a:lines, a:lin, a:s)
    let l:left = filter(copy(l:cols), 'v:val < a:s')
    if !empty(l:left)
      let l:s = l:left[-1]
    endif
  endif
  for l:l in a:lines
    for l:a in songwriter#tab#model#Notes(l:l)
      if l:a.col + l:a.len - 1 == l:e
        let l:ends = 1
      endif
    endfor
  endfor
  if l:ends && !songwriter#tab#columns#OnPipeOrName(a:lines[a:lin], l:e)
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
  let l:o = songwriter#tab#model#BodyOffset()
  return map(copy(a:lines),
        \ "strpart(v:val, 0, l:o) . substitute(strpart(v:val, l:o), songwriter#grammar#Chain(), '\\=repeat(\"-\", len(submatch(0)))', 'g')")
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
  let l:filler = substitute(l:rows[0], songwriter#grammar#NotPipe(), '-', 'g')
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
    let l:dropped += len(songwriter#tab#model#RowNotes(l:rows[l:j]))
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
  let l:names = songwriter#tab#model#Names(a:lines)
  let l:m = songwriter#tab#columns#MatchRows(l:names, a:rows, a:regnames)
  if has_key(l:m, 'error')
    return l:m
  endif
  let l:rows = l:m.rows
  let l:line = a:lines[a:lin]
  let l:col = max([a:col, songwriter#tab#model#BodyOffset()])
  if !empty(filter(copy(l:rows), "stridx(v:val, '|') >= 0"))
    call map(l:rows, "substitute(v:val, songwriter#grammar#LeadingPipe(), '', '')")
    call map(l:rows, "v:val =~# songwriter#grammar#FinalPipe() ? v:val : v:val . '|'")
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
  let l:m = songwriter#tab#columns#MatchRows(songwriter#tab#model#Names(a:lines), a:rows, a:regnames)
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
    let l:p = match(l:r, songwriter#grammar#Note())
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
  for l:a in songwriter#tab#model#Notes(a:lines[a:lin])
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
    if l:i != a:lin && !empty(filter(songwriter#tab#model#Notes(a:lines[l:i]), 'v:val.col == l:c'))
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
    let l:out[a:lin] = songwriter#tab#model#Blank(a:lines[a:lin], l:note)
  else
    let l:out = songwriter#tab#columns#DeleteRange(a:lines, l:c, l:e).lines
  endif
  return {'lines': l:out, 'col': l:c, 'rows': l:rows}
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
    for l:a in songwriter#tab#model#Notes(l:l)
      if l:a.col < l:c && songwriter#tab#model#InBar(l:a.col, l:bar)
        let l:prev_end = max([l:prev_end, l:a.col + l:a.len - 1])
      endif
    endfor
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

" Spec 6.14: write the notes of column register `rows` onto the time column at
" `col` of line `lin`, without adding time: the register's first note column
" lands on that column. Rows are matched as in Paste. Returns {'lines', 'col',
" 'msg'}, or {'error'} for a bar register, no column there, or a note that
" would replace anything but dashes.
function! songwriter#tab#columns#Overlay(lines, lin, col, rows, regnames) abort
  if !empty(filter(copy(a:rows), "stridx(v:val, '|') >= 0"))
    return {'error': 'songwriter: gp pastes a column, not a bar'}
  endif
  let l:m = songwriter#tab#columns#MatchRows(songwriter#tab#model#Names(a:lines), a:rows, a:regnames)
  if has_key(l:m, 'error')
    return l:m
  endif
  let l:c = 0
  if !songwriter#tab#columns#OnPipeOrName(a:lines[a:lin], a:col)
    let [l:bar, l:cols] = s:bar_columns(a:lines, a:lin, a:col)
    let l:c = s:column_for(l:cols, a:col)
  endif
  if l:c == 0
    return {'error': 'songwriter: gp needs a note column under the cursor'}
  endif
  let l:atoms = map(copy(l:m.rows), 'songwriter#tab#model#RowChains(v:val)')
  let l:starts = []
  for l:r in l:m.rows
    call extend(l:starts, map(songwriter#tab#model#RowNotes(l:r), 'v:val.col'))
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
      if strpart(l:line, l:s - 1, l:a.len) !~# songwriter#grammar#OnlyDashes()
        return {'error': printf('songwriter: gp would replace a note on string %s', songwriter#tab#model#Name(a:lines[l:i]))}
      endif
      let l:out[l:i] = songwriter#tab#model#Splice(l:line, l:s, l:a.len, l:a.text)
    endfor
  endfor
  return {'lines': l:out, 'col': l:c, 'msg': l:m.msg}
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
