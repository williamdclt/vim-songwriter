" autoload/songwriter/tab/motion.vim - tablature-mode motions (spec
" [Tablature][[Editing]] 3.2, 3.3, 3.5): the buffer entry points around the
" stops of tab/stops.vim, and the slots the insert state opens on the way.

" Spec [Tablature][[Editing]] 3.2: the word motion `key` (`w`, `b`, `e`, `ge`)
" on the current line (see columns#Stops). No-op off a tab line or with no
" word that way.
" An open slot is closed first (4.3), and the move goes on from the slot's
" side (see s:from_slot).
function! songwriter#tab#motion#MoveWord(key) abort
  let l:slot = songwriter#tab#slots#Abandon(1)
  let l:line = getline('.')
  if !songwriter#grammar#IsTabLine(l:line)
    return
  endif
  let l:cols = songwriter#tab#columns#Stops([], l:line, a:key)
  let l:target = s:from_slot(l:slot, l:cols, col('.'), a:key =~# '^[we]$' ? 1 : -1)
  if l:target != col('.')
    call cursor(line('.'), l:target)
  endif
endfunction

" Spec [Tablature][[Editing]] 3.5: the bar motions `W`/`B`/`E` (`key`),
" `count` times (see columns#BarStop). An open slot is closed first (4.3).
function! songwriter#tab#motion#MoveBar(key, count) abort
  call songwriter#tab#slots#Abandon(1)
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:col = songwriter#tab#columns#BarStop(l:block.lines, getline('.'), col('.'), a:key, a:count)
  if l:col != col('.')
    call cursor(line('.'), l:col)
  endif
endfunction

" Spec [Tablature][[Editing]] 3.3: `l` (dir +1) / `h` (dir -1). In the normal
" state they only move (3.3.2): to the next/previous stop (see model#Stops),
" crossing bar pipes; with none that way, the cursor stays. In the insert state,
" see s:insert_column.
function! songwriter#tab#motion#MoveColumn(dir) abort
  if songwriter#tab#insert#Active()
    call s:insert_column(a:dir)
    return
  endif
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:target = songwriter#tab#model#Advance(songwriter#tab#model#Stops(l:block, getline('.')), col('.'), a:dir, 1)
  if l:target != col('.')
    call cursor(line('.'), l:target)
  endif
endfunction

" Spec 3.3.5: `L` (dir +1) / `H` (dir -1) move to the next/previous stop as
" `l`/`h` do in the normal state, in both states, never opening a slot. An open
" slot is closed first and the move goes on from its note (see s:from_slot).
function! songwriter#tab#motion#StepColumn(dir) abort
  let l:slot = songwriter#tab#slots#Abandon(1)
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:target = s:from_slot(l:slot, songwriter#tab#model#Stops(l:block, getline('.')), col('.'), a:dir)
  if l:target != col('.')
    call cursor(line('.'), l:target)
  endif
endfunction

" Spec 3.3.3 and 5: `l`/`h` in the insert state, where the gaps between notes
" are stops too. On the open slot, close it (4.3) and move on (see
" s:leave_slot). On a note column, open a slot after it (`l`, as `a`) or
" before it (`h`, as `i`). Elsewhere, move as in the normal state, opening the
" slot of an empty bar landed in (3.3.4); `l` with nowhere to go in the tab's
" last bar adds a new bar (5).
function! s:insert_column(dir) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:col = col('.')
  let l:slot = songwriter#tab#state#Get('slot')
  if !empty(l:slot) && l:slot.col == l:col
        \ && songwriter#tab#model#Read(l:slot.line).start == l:block.start
    call s:leave_slot(l:block, l:slot, a:dir)
  elseif index(songwriter#tab#model#NoteColumns(l:block), l:col) >= 0
    call songwriter#tab#slots#AddNote(a:dir)
  else
    let l:target = songwriter#tab#model#Advance(songwriter#tab#model#Stops(l:block, getline('.')), l:col, a:dir, 1)
    if l:target != l:col
      call s:land(l:block, l:target)
    elseif a:dir > 0 && songwriter#tab#model#InLastBar(getline('.'), l:col)
      call songwriter#tab#slots#AddBarSlot()
    endif
  endif
endfunction

" Close `slot`, under the cursor, and move from where the cursor was before it
" opened (see s:from_slot), opening the slot of an empty bar landed in (3.3.4).
" With no stop that way the slot stays open, except that `l` from a slot after
" the last note of the tab's last bar makes a new bar (5) instead.
function! s:leave_slot(block, slot, dir) abort
  let l:col = col('.')
  let l:back = get(a:slot, 'side', 0) == -a:dir
  if !l:back && songwriter#tab#model#Advance(songwriter#tab#model#Stops(a:block, getline('.')), l:col, a:dir, 1) == l:col
    if a:dir > 0 && songwriter#tab#model#InLastBar(getline('.'), l:col) && s:bar_has_notes(a:block, l:col)
      call songwriter#tab#slots#Abandon(1)
      call songwriter#tab#slots#AddBarSlot()
    endif
    return
  endif
  call songwriter#tab#slots#Abandon(1)
  let l:block = songwriter#tab#model#Read()
  call s:land(l:block, s:from_slot(a:slot, songwriter#tab#model#Stops(l:block, getline('.')), col('.'), a:dir))
endfunction

" Where a move in direction `dir` goes among `stops` from column `col`, the
" cursor's column once `slot` (from slots#Abandon, {} if none) is closed. A
" slot opened on one side of a note (Mark's `side`) was between that note and
" the next one: moving back towards the note lands on it (`col` itself when it
" is a stop), moving on goes past it, to the next stop.
function! s:from_slot(slot, stops, col, dir) abort
  if get(a:slot, 'side', 0) == -a:dir && index(a:stops, a:col) >= 0
    return a:col
  endif
  return songwriter#tab#model#Advance(a:stops, a:col, a:dir, 1)
endfunction

" Move the cursor to column `target` of its line, opening the slot of the
" empty bar there if it is one (3.3.4).
function! s:land(block, target) abort
  if index(songwriter#tab#model#EmptyBarStops(getline('.'), songwriter#tab#model#NoteColumns(a:block)), a:target) >= 0
    let l:mark = songwriter#tab#slots#Mark(0)
    call cursor(line('.'), a:target)
    let l:mark.from = a:target
    call songwriter#tab#edit#Apply(a:block, songwriter#tab#slots#EmptyBar(a:block.lines,
          \ songwriter#tab#model#CursorLin(a:block), a:target))
    call songwriter#tab#slots#Open(l:mark)
  else
    call cursor(line('.'), a:target)
  endif
endfunction

" True when the bar of the cursor's line around `col` has a note on any string
" of `block`.
function! s:bar_has_notes(block, col) abort
  return !empty(songwriter#tab#model#BarColumns(a:block,
        \ songwriter#tab#model#CursorLin(a:block), a:col).cols)
endfunction
