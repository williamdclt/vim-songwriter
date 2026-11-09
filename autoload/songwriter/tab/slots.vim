" autoload/songwriter/tab/slots.vim - slots: room opened for a note that is not
" typed yet (spec [Tablature][[Editing]] 3.1, 4.3, 5, 6.6, 8). The pure functions
" compute where a slot goes; Open, OpenHere, Forget and Abandon handle the one
" open slot of a buffer, kept in tab/state.vim as {'line'}.

" A new, empty bar: five dashes with the slot on the middle one.
let s:new_bar = '-----'
let s:new_bar_slot = 3

" Pure. A new bar of five dashes after every string of a linted block (whose
" strings all end on the same pipe column), with the slot on the middle dash.
" Returns {'lines', 'col'}.
function! songwriter#tab#slots#AppendBar(block) abort
  return {
        \ 'lines': map(copy(a:block.lines), "v:val . s:new_bar . '|'"),
        \ 'col': len(a:block.lines[0]) + s:new_bar_slot}
endfunction

" Pure. A tab with the string names of `block` and one bar of five dashes,
" with the slot on the middle dash (as the new bar of spec 5).
" Returns {'lines', 'col'}.
function! songwriter#tab#slots#EmptyTab(block) abort
  return {'lines': map(copy(a:block.lines), "v:val[0] . '|' . s:new_bar . '|'"), 'col': 2 + s:new_bar_slot}
endfunction

" Pure. The `a` slot: the anchor is the rightmost note end, on any string,
" among notes of the cursor's bar that start at or before the cursor (so the
" anchor is the note column under or left of the cursor). Dashes are inserted
" after the anchor so that the slot sits one dash from it and the next note, on
" any string, stays one dash away (the next pipe, two dashes).
" Returns {'lines', 'col'}, or {} when there is no anchor note.
function! songwriter#tab#slots#Append(block, line, col) abort
  let l:bar = songwriter#tab#model#BarAt(a:line, a:col)
  let l:e = 0
  for l:s in a:block.strings
    for l:n in l:s.notes
      if l:n.col <= a:col && songwriter#tab#model#InBar(l:n.col, l:bar)
        let l:e = max([l:e, l:n.col - 1 + l:n.len])
      endif
    endfor
  endfor
  if l:e == 0
    return {}
  endif
  " Wanted column of the nearest next note (e + 4) or pipe (e + 5), any string.
  let l:n = 0
  for l:s in a:block.strings
    for l:note in l:s.notes
      if l:note.col > l:e
        let l:n = max([l:n, l:e + 4 - l:note.col])
      endif
    endfor
    for l:p in l:s.pipes
      if l:p > l:e
        let l:n = max([l:n, l:e + 5 - l:p])
      endif
    endfor
  endfor
  return {
        \ 'lines': songwriter#tab#model#InsertColumns(a:block.lines, l:e, l:n, '-'),
        \ 'col': l:e + 2}
endfunction

" Pure. The `i` slot, mirror of Append: the anchor is the leftmost note
" start, on any string, among notes of the cursor's bar that end at or after
" the cursor. Dashes are inserted before it so that the slot sits one dash left
" of it and the previous note, on any string, stays one dash away (the
" previous pipe, two dashes).
" Returns {'lines', 'col'}, or {} when there is no anchor note.
function! songwriter#tab#slots#Prepend(block, line, col) abort
  let l:bar = songwriter#tab#model#BarAt(a:line, a:col)
  let l:s = 0
  for l:str in a:block.strings
    for l:n in l:str.notes
      if l:n.col - 1 + l:n.len >= a:col
            \ && songwriter#tab#model#InBar(l:n.col, l:bar)
            \ && (l:s == 0 || l:n.col < l:s)
        let l:s = l:n.col
      endif
    endfor
  endfor
  if l:s == 0
    return {}
  endif
  " Dashes needed so the previous note end (s - 4) or pipe (s - 5) is far enough.
  let l:n = 0
  for l:str in a:block.strings
    for l:note in l:str.notes
      let l:end = l:note.col - 1 + l:note.len
      if l:end < l:s
        let l:n = max([l:n, l:end + 4 - l:s])
      endif
    endfor
    for l:p in l:str.pipes
      if l:p < l:s
        let l:n = max([l:n, l:p + 5 - l:s])
      endif
    endfor
  endfor
  return {
        \ 'lines': songwriter#tab#model#InsertColumns(a:block.lines, l:s - 1, l:n, '-'),
        \ 'col': l:s + l:n - 2}
endfunction

" Spec 6.6: a slot in the (empty) bar around column `col` of line `lin`: the
" bar's content becomes 5 dashes on every string and the slot is the middle
" one. Returns {'lines', 'col'}, or {} outside a bar.
function! songwriter#tab#slots#EmptyBar(lines, lin, col) abort
  let l:bar = songwriter#tab#model#BarAt(a:lines[a:lin], a:col)
  if l:bar.start == 0 || l:bar.end == 0
    return {}
  endif
  let l:out = map(copy(a:lines),
        \ 'strpart(v:val, 0, l:bar.start) . s:new_bar . strpart(v:val, l:bar.end - 1)')
  return {'lines': l:out, 'col': l:bar.start + s:new_bar_slot}
endfunction

" Remember the slot under the cursor.
function! songwriter#tab#slots#Open() abort
  call songwriter#tab#state#Set('slot', {'line': line('.')})
endfunction

function! songwriter#tab#slots#Forget() abort
  call songwriter#tab#state#Clear('slot')
endfunction

" Spec 4.3: if the slot opened by `a`/`i` (or `l`, 3.3.2 and 5) is still open and
" empty (the buffer has not changed since, e.g. only `j`/`k` were pressed),
" lint its block. Called by the tablature-mode keys that abandon a slot.
function! songwriter#tab#slots#Abandon() abort
  let l:slot = songwriter#tab#state#Get('slot')
  call songwriter#tab#slots#Forget()
  if empty(l:slot)
    return
  endif
  call songwriter#tab#edit#LintAndFollow(songwriter#tab#model#Read(l:slot.line))
endfunction

" Spec 6.6: open a slot at the cursor: before its note (side -1, as `i`),
" after it (+1, as `a`), or, side 0, in the cursor's empty bar.
function! songwriter#tab#slots#OpenHere(side) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:line = getline('.')
  if a:side < 0
    let l:res = songwriter#tab#slots#Prepend(l:block, l:line, col('.'))
  elseif a:side > 0
    let l:res = songwriter#tab#slots#Append(l:block, l:line, col('.'))
  else
    let l:res = songwriter#tab#slots#EmptyBar(l:block.lines, line('.') - l:block.start, col('.'))
  endif
  if empty(l:res)
    return
  endif
  call songwriter#tab#edit#Apply(l:block, l:res)
  call songwriter#tab#slots#Open()
endfunction
