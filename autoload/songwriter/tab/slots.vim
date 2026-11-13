" autoload/songwriter/tab/slots.vim - slots: room opened for a note that is not
" typed yet (spec [Tablature][[Editing]] 3.1, 4.3, 5, 6.6, 8). The pure functions
" compute where a slot goes; Mark, Open, OpenHere, Forget and Abandon handle the
" one open slot of a buffer, kept in tab/state.vim (see Open); AddNote (`a`,
" `i`) and AddBarSlot (a new bar, spec 5) are the entry points that open one.

" A new, empty bar: five dashes with the slot on the middle one.
let s:new_bar = '-----'
let s:new_bar_slot = 3

" Pure. A new bar of five dashes after every string of a linted block (whose
" strings all end on the same pipe column), with the slot on the middle dash.
" Returns {'lines', 'col', 'map'}.
function! songwriter#tab#slots#AppendBar(block) abort
  return {
        \ 'lines': map(copy(a:block.lines), "v:val . s:new_bar . '|'"),
        \ 'col': len(a:block.lines[0]) + s:new_bar_slot,
        \ 'map': songwriter#tab#colmap#Insert(len(a:block.lines[0]), len(s:new_bar) + 1)}
endfunction

" Pure. A tab with the string names of `block` and one bar of five dashes,
" with the slot on the middle dash (as the new bar of spec 5).
" Returns {'lines', 'col'}.
function! songwriter#tab#slots#EmptyTab(block) abort
  return songwriter#tab#slots#EmptyTabNamed(songwriter#tab#model#Names(a:block.lines))
endfunction

" Pure. As EmptyTab, with the string `names` given as a list, highest first.
function! songwriter#tab#slots#EmptyTabNamed(names) abort
  return {'lines': map(copy(a:names), "v:val . '|' . s:new_bar . '|'"),
        \ 'col': songwriter#tab#model#BodyOffset() + s:new_bar_slot}
endfunction

" Pure. The `a` slot: the anchor is the rightmost note end, on any string,
" among notes of the cursor's bar that start at or before the cursor (so the
" anchor is the note column under or left of the cursor), past any separator
" trailing it with no note after (`7b`). Dashes are inserted after the anchor so
" that the slot sits one dash from it and the next note, on
" any string, stays one dash away (the next pipe, two dashes).
" Returns {'lines', 'col', 'map'}, or {} when there is no anchor note.
function! songwriter#tab#slots#Append(block, lin, col) abort
  let l:bar = songwriter#tab#model#BarAt(a:block.lines[a:lin], a:col)
  let l:e = 0
  for l:n in songwriter#tab#model#BarNotes(a:block, l:bar)
    if l:n.col <= a:col
      let l:e = max([l:e, songwriter#tab#model#NoteEnd(l:n)])
    endif
  endfor
  if l:e == 0
    return {}
  endif
  let l:e += s:loose_separators(a:block, l:e, 1)
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
  return extend(songwriter#tab#model#InsertColumns(a:block.lines, l:e, l:n, '-'), {'col': l:e + 2})
endfunction

" Pure. The `i` slot, mirror of Append: the anchor is the leftmost note
" start, on any string, among notes of the cursor's bar that end at or after
" the cursor, before any separator leading it with no note before (`/5`). Dashes are inserted before it so that the slot sits one dash left
" of it and the previous note, on any string, stays one dash away (the
" previous pipe, two dashes).
" Returns {'lines', 'col', 'map'}, or {} when there is no anchor note.
function! songwriter#tab#slots#Prepend(block, lin, col) abort
  let l:bar = songwriter#tab#model#BarAt(a:block.lines[a:lin], a:col)
  let l:s = 0
  for l:n in songwriter#tab#model#BarNotes(a:block, l:bar)
    if songwriter#tab#model#NoteEnd(l:n) >= a:col && (l:s == 0 || l:n.col < l:s)
      let l:s = l:n.col
    endif
  endfor
  if l:s == 0
    return {}
  endif
  let l:s -= s:loose_separators(a:block, l:s, -1)
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
  return extend(songwriter#tab#model#InsertColumns(a:block.lines, l:s - 1, l:n, '-'),
        \ {'col': l:s + l:n - 2})
endfunction

" The width of the separators right after (dir 1) / before (dir -1) column
" `edge`, on a string where a note ends / starts at `edge`, when they do not
" lead to another note: they belong to that note, so a slot goes beyond them.
function! s:loose_separators(block, edge, dir) abort
  let l:width = 0
  for l:s in a:block.strings
    if empty(filter(copy(l:s.notes), a:dir > 0
          \ ? 'v:val.col + v:val.len - 1 == a:edge' : 'v:val.col == a:edge'))
      continue
    endif
    let l:k = 0
    while songwriter#grammar#IsSeparatorChar(strpart(l:s.text, a:edge - 1 + a:dir * (l:k + 1), 1))
      let l:k += 1
    endwhile
    let l:after = strpart(l:s.text, a:edge - 1 + a:dir * (l:k + 1), 1)
    if l:k > 0 && !songwriter#grammar#IsChainChar(l:after)
      let l:width = max([l:width, l:k])
    endif
  endfor
  return l:width
endfunction

" Spec 6.6: a slot in the (empty) bar around column `col` of line `lin`: the
" bar's content becomes 5 dashes on every string and the slot is the middle
" one. Returns {'lines', 'col', 'map'}, or {} outside a bar. What was in the
" bar keeps its offset from the bar's left pipe (colmap#Resize).
function! songwriter#tab#slots#EmptyBar(lines, lin, col) abort
  let l:bar = songwriter#tab#model#BarAt(a:lines[a:lin], a:col)
  if l:bar.start == 0 || l:bar.end == 0
    return {}
  endif
  let l:out = map(copy(a:lines),
        \ 'strpart(v:val, 0, l:bar.start) . s:new_bar . strpart(v:val, l:bar.end - 1)')
  return {'lines': l:out, 'col': l:bar.start + s:new_bar_slot,
        \ 'map': songwriter#tab#colmap#Resize(l:bar.start + 1, l:bar.end - l:bar.start - 1, len(s:new_bar))}
endfunction

" What closing a slot about to be opened by `a`/`i`, `l`/`h` or a new bar must
" restore (spec 4.3): the block (`before`, a snapshot, model#Snapshot), the
" cursor column (`from`), and the buffer and undo versions, taken before
" anything (even the lint of 4.2) is changed. `side`: +1 for a slot after a
" note, -1 before one, 0 in an empty bar.
function! songwriter#tab#slots#Mark(side) abort
  let l:block = songwriter#tab#model#Read()
  return {'side': a:side, 'from': col('.'), 'tick': b:changedtick,
        \ 'seq': undotree().seq_cur,
        \ 'before': empty(l:block) ? {} : songwriter#tab#model#Snapshot(l:block)}
endfunction

" Record in `mark` (from Mark) the block as linted before its slot opens
" (4.2), `linted` being {'lines', 'map', 'col'} (the cursor column there), for
" a motion closing the slot to keep (4.3.3).
function! songwriter#tab#slots#Linted(mark, linted) abort
  let a:mark.linted = songwriter#tab#edit#Derive(a:mark.before, a:linted.lines, a:linted.map)
  let a:mark.linted_col = a:linted.col
endfunction

" Make `mark` (from Mark, with Linted) that of a slot in the middle of an empty
" bar, at column `col` of the lines as linted: closed by a motion, it goes on
" from that bar's stop (3.3.4), as a slot landed in does.
function! songwriter#tab#slots#InBar(mark, col) abort
  let a:mark.side = 0
  let a:mark.linted_col = a:col
  if a:mark.linted ==# a:mark.before
    let a:mark.from = a:col
  endif
endfunction

" Remember the slot under the cursor and enter the insert state (spec 3.1).
" With a `mark` (from Mark), closing it restores the tab; without one, the slot
" is part of a bigger edit (`c`, `o`, :SongwriterNewTab) and closing lints.
function! songwriter#tab#slots#Open(...) abort
  let l:slot = {'line': line('.'), 'col': col('.')}
  if a:0
    call extend(l:slot, a:1)
    let l:slot.changed = a:1.tick != b:changedtick
    let l:slot.seq_after = undotree().seq_cur
  endif
  call songwriter#tab#state#Set('slot', l:slot)
  call songwriter#tab#insert#Enter()
endfunction

function! songwriter#tab#slots#Forget() abort
  call songwriter#tab#state#Clear('slot')
endfunction

" Spec 4.3: close the open slot if it is still open and empty (the buffer has
" not changed since, e.g. only `j`/`k` were pressed). A slot with a mark puts
" the tab back as it was before it opened, leaving no undo step, and the cursor
" back on its column (on the cursor's line); any other is linted. With
" `keep_lint` (a motion closing it, 4.3.3), a mark that recorded the lint of
" 4.2 (see Linted) puts the tab back as it was once linted instead, the lint
" being an undo step of its own. The insert state is kept. Returns the closed
" slot, or {} when none was open.
function! songwriter#tab#slots#Abandon(...) abort
  let l:keep_lint = a:0 && a:1
  let l:slot = songwriter#tab#state#Get('slot')
  call songwriter#tab#slots#Forget()
  if empty(l:slot)
    return {}
  endif
  let l:insert = songwriter#tab#insert#Active()
  if has_key(l:slot, 'from')
    let l:lnum = line('.')
    if l:slot.changed
      call s:revert(l:slot)
    endif
    if l:keep_lint && has_key(l:slot, 'linted') && l:slot.linted !=# l:slot.before
      call songwriter#tab#model#Write(songwriter#tab#model#ReadTop(l:slot.before.top), l:slot.linted)
      call cursor(l:lnum, l:slot.linted_col)
    else
      call cursor(l:lnum, l:slot.from)
    endif
  else
    call songwriter#tab#edit#LintAndFollow(songwriter#tab#model#Read(l:slot.line))
  endif
  if l:insert
    call songwriter#tab#insert#Keep()
  endif
  return l:slot
endfunction

" Put back the block a slot replaced. Undo, when the slot's change is the last
" undo step and that step holds nothing else (a slot opened in a macro or
" `:normal` shares its step with earlier changes): then no undo step is left.
" Otherwise, or if undoing did not give the block back, write it.
function! s:revert(slot) abort
  if a:slot.seq_after != a:slot.seq && undotree().seq_cur == a:slot.seq_after
    silent undo
    if s:holds(a:slot.before)
      return
    endif
    silent redo
  endif
  call songwriter#tab#model#Write(songwriter#tab#model#ReadTop(a:slot.before.top), a:slot.before)
endfunction

" True when the buffer holds the block of `snapshot` as it is there.
function! s:holds(snapshot) abort
  let l:block = songwriter#tab#model#ReadTop(a:snapshot.top)
  return !empty(l:block) && songwriter#tab#model#Snapshot(l:block) ==# a:snapshot
endfunction

" Spec 6.6: open a slot at the cursor: before its note (side -1, as `i`),
" after it (+1, as `a`), or, side 0, in the cursor's empty bar.
function! songwriter#tab#slots#OpenHere(side) abort
  let l:c = songwriter#tab#model#Cursor()
  if empty(l:c)
    return
  endif
  let l:block = l:c.block
  if a:side < 0
    let l:res = songwriter#tab#slots#Prepend(l:block, l:c.lin, l:c.col)
  elseif a:side > 0
    let l:res = songwriter#tab#slots#Append(l:block, l:c.lin, l:c.col)
  else
    let l:res = songwriter#tab#slots#EmptyBar(l:block.lines, l:c.lin, l:c.col)
  endif
  if empty(l:res)
    return
  endif
  call songwriter#tab#edit#Apply(l:block, l:res)
  call songwriter#tab#slots#Open()
endfunction

" Spec [Tablature][[Editing]] 3.1: open room for a new note on every string,
" to the right of the current note (side +1, `a`) or to its left (side -1,
" `i`), land the cursor on the new slot and enter the insert state. In a bar
" with no note, the slot is its middle dash, as on landing there (3.1.7). An
" open slot is closed first (4.3). The block is linted (4.2), and the slot is
" remembered until a note fills it or it is closed, which restores the tab as it
" was before the lint (4.3).
function! songwriter#tab#slots#AddNote(side) abort
  call songwriter#tab#edit#Do(function('s:add_note', [a:side]),
        \ {'slot': 'close', 'open': a:side, 'lint': 0})
endfunction

function! s:add_note(side, ctx) abort
  let l:bar = songwriter#tab#model#BarAt(a:ctx.line, a:ctx.col)
  if empty(songwriter#tab#model#BarNotes(a:ctx.block, l:bar))
    let l:res = songwriter#tab#slots#EmptyBar(a:ctx.block.lines, a:ctx.lin, a:ctx.col)
    return empty(l:res) ? {} : extend(l:res, {'side': 0})
  endif
  return a:side > 0
        \ ? songwriter#tab#slots#Append(a:ctx.block, a:ctx.lin, a:ctx.col)
        \ : songwriter#tab#slots#Prepend(a:ctx.block, a:ctx.lin, a:ctx.col)
endfunction

" Spec [Tablature][[Editing]] 5: append a new bar to the end of the tab with a
" slot in its middle, and land the cursor on it, ready for a note. Like `a`,
" the block is linted first (4.2) and the slot is remembered (4.3); closed, the
" tab goes back as it was.
function! songwriter#tab#slots#AddBarSlot() abort
  call songwriter#tab#edit#Do({ctx -> songwriter#tab#slots#AppendBar(ctx.block)},
        \ {'open': 1, 'lint': 0})
endfunction
