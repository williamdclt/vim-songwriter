" autoload/songwriter/tab/objects.vim - the ranges of tablature-mode text
" objects (spec [Tablature][[Editing]] 6.1) and the snapping of other ranges
" (6.2.3), pure. A range is [s, e], two 1-indexed inclusive byte columns;
" block lines are 0-indexed (`lin`). Each function parses `lines` once
" (model#Parse) for the model's queries.

" Spec 6.1.1 / 6.1.3: `ic` (around 0) / `ac` (around 1) with a count, from
" column `col` of line `lin`. [s, e], or [] on a pipe, the string name or in a
" bar without notes. A count stops at the bar's last column.
function! songwriter#tab#objects#ColumnObject(lines, lin, col, count, around) abort
  if songwriter#tab#columns#OnPipeOrName(a:lines[a:lin], a:col)
    return []
  endif
  let l:tab = songwriter#tab#model#Parse(0, a:lines)
  let l:bc = songwriter#tab#model#BarColumns(l:tab, a:lin, a:col)
  let l:c = songwriter#tab#model#ColumnFor(l:bc.cols, a:col)
  if l:c == 0
    return []
  endif
  let l:last = l:bc.cols[min([index(l:bc.cols, l:c) + max([a:count, 1]) - 1, len(l:bc.cols) - 1])]
  let l:e = a:around ? songwriter#tab#model#GapEnd(l:tab, a:lin, l:bc, l:last)
        \ : songwriter#tab#model#ColumnEnd(l:tab, l:last)
  return [l:c, l:e]
endfunction

" Spec 6.1.2 / 6.1.3: `i|` (around 0) / `a|` (around 1, with the closing
" pipe) with a count. On a pipe, the bar to its right. [] on the string name,
" the last pipe or past it. A count stops at the tab's last bar.
function! songwriter#tab#objects#BarObject(lines, lin, col, count, around) abort
  let l:pipes = songwriter#tab#model#Pipes(a:lines[a:lin])
  let l:k = len(filter(copy(l:pipes), 'v:val <= a:col')) - 1
  if a:col < songwriter#tab#model#BodyOffset() || l:k < 0 || l:k + 1 >= len(l:pipes)
    return []
  endif
  let l:k2 = min([l:k + max([a:count, 1]), len(l:pipes) - 1])
  return [l:pipes[l:k] + 1, l:pipes[l:k2] - (a:around ? 0 : 1)]
endfunction

" `ic`/`ac` (kind 'c') or `i|`/`a|` (kind '|').
function! songwriter#tab#objects#Object(kind, lines, lin, col, count, around) abort
  return a:kind ==# 'c'
        \ ? songwriter#tab#objects#ColumnObject(a:lines, a:lin, a:col, a:count, a:around)
        \ : songwriter#tab#objects#BarObject(a:lines, a:lin, a:col, a:count, a:around)
endfunction

" Spec 6.1.4: `in`/`an`, the note at `col` on line `lin`, or on a dash the
" nearest note of the string to the left in the bar. [s, e] or [].
function! songwriter#tab#objects#NoteObject(lines, lin, col, around) abort
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
  let l:column = songwriter#tab#objects#ColumnObject(a:lines, a:lin, l:n.col, 1, 1)
  return [l:n.col, max([l:column[1], l:n.col + l:n.len - 1])]
endfunction

" Spec 6.1.5: `iw`/`aw`, the word (3.2) at `col` on line `lin`, or on a dash
" the nearest word of the string to the left in the bar; `aw` also takes the
" gap after it, as `an`. [s, e] or [].
function! songwriter#tab#objects#WordObject(lines, lin, col, around) abort
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
  let l:column = songwriter#tab#objects#ColumnObject(a:lines, a:lin, l:w.last, 1, 1)
  return [l:w.start, max([l:column[1], l:w.end])]
endfunction

" `in`/`an` (kind 'n') or `iw`/`aw` (kind 'w').
function! songwriter#tab#objects#StringObject(kind, lines, lin, col, around) abort
  return a:kind ==# 'w'
        \ ? songwriter#tab#objects#WordObject(a:lines, a:lin, a:col, a:around)
        \ : songwriter#tab#objects#NoteObject(a:lines, a:lin, a:col, a:around)
endfunction

" Spec 6.2.3: snap a motion's range [s, e] outward so it never cuts a note: s
" goes to the start of the note it is in, or, in a gap, to the previous column
" of its bar; e goes to the end of the note it is in, and a range ending on a
" note takes that note's gap too.
function! songwriter#tab#objects#Snap(lines, lin, s, e) abort
  let l:tab = songwriter#tab#model#Parse(0, a:lines)
  let l:s = a:s
  let l:e = a:e
  let l:covered = 0
  let l:ends = 0
  for l:str in l:tab.strings
    for l:a in l:str.notes
      let l:aend = songwriter#tab#model#NoteEnd(l:a)
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
    let l:left = filter(songwriter#tab#model#BarColumns(l:tab, a:lin, a:s).cols, 'v:val < a:s')
    if !empty(l:left)
      let l:s = l:left[-1]
    endif
  endif
  for l:str in l:tab.strings
    for l:a in l:str.notes
      if songwriter#tab#model#NoteEnd(l:a) == l:e
        let l:ends = 1
      endif
    endfor
  endfor
  if l:ends && !songwriter#tab#columns#OnPipeOrName(a:lines[a:lin], l:e)
    let l:e = songwriter#tab#model#GapEnd(l:tab, a:lin,
          \ songwriter#tab#model#BarColumns(l:tab, a:lin, l:e), l:e)
  endif
  return [l:s, l:e]
endfunction
