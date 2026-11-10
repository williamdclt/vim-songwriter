" autoload/songwriter/tab/operator.vim - tablature-mode operators and text
" objects (spec [Tablature][[Editing]] 6): the buffer entry points
" around the pure column model (tab/columns.vim). Visual mode is tab/visual.vim,
" registers tab/register.vim, `.` tab/repeat.vim. See design.md "Operators and
" text objects".
"
" d/y/c run through 'operatorfunc' and g@, so counts, motions and `.` work as
" for native operators. The operator, register, whether the target was one of
" our text objects or string motions (exact: no snapping) and its reach
" (`note`, see ApplyRange) are kept in s:pending, since v:register is not
" reliable inside 'operatorfunc'.

let s:pending = {'op': 'd', 'reg': '"', 'exact': 0, 'note': 0, 'cancel': 0, 'tick': -1}

" === Operators ===

" `d`/`y`/`c` in tablature mode: lint first (own undo step, joined to the
" operation's), then g@. The <Cmd> that lints consumes the count, so it is
" given again after g@ (`3dw` runs as `g@3w`).
function! songwriter#tab#operator#Start(op) abort
  let s:pending = {'op': a:op, 'reg': v:register, 'exact': 0, 'note': 0, 'cancel': 0, 'tick': -1}
  set operatorfunc=songwriter#tab#operator#Opfunc
  return "\<Cmd>call songwriter#tab#operator#Prelint()\<CR>g@"
        \ . (v:count ? v:count : '')
endfunction

" `Y`, `S` (target "column": the column, as `yy`/`cc`) and `D`, `C` (target
" "bar-end": to the end of the bar, as `dW`/`cW`): the operator, then its
" target as a <Cmd> (a returned key would not be remapped).
function! songwriter#tab#operator#StartOn(op, target) abort
  let l:keys = songwriter#tab#operator#Start(a:op)
  return l:keys . (a:target ==# 'column'
        \ ? "\<Cmd>call songwriter#tab#operator#Object('c', 1)\<CR>"
        \ : "\<Cmd>call songwriter#keys#JumpBarLine(1)\<CR>")
endfunction

" Spec 6.8: the second key of `dd`/`yy`/`cc` (after the operator, so `d3d`
" takes a count): the column and its gap, as `ac`. Another operator key (`dy`)
" cancels.
function! songwriter#tab#operator#Doubled(key) abort
  if s:pending.op ==# a:key
    call songwriter#tab#operator#Object('c', 1)
  else
    let s:pending.cancel = 1
  endif
endfunction

function! songwriter#tab#operator#Prelint() abort
  let l:tick = b:changedtick
  call songwriter#tab#edit#LintAndFollow(songwriter#tab#model#Read())
  let s:pending.tick = b:changedtick != l:tick ? b:changedtick : -1
endfunction

function! songwriter#tab#operator#Opfunc(type) abort
  let l:p = copy(s:pending)
  let s:pending.exact = 0
  let s:pending.note = 0
  let s:pending.cancel = 0
  if l:p.cancel
    return
  endif
  if l:p.tick == b:changedtick
    silent! undojoin
  endif
  if a:type ==# 'line'
    call songwriter#tab#operator#ApplyLines(l:p.op, l:p.reg, line("'["), line("']"))
  else
    let l:lnum = line("'[")
    let l:block = songwriter#tab#model#Read(l:lnum)
    if empty(l:block)
      return
    endif
    let l:lin = l:lnum - l:block.start
    let l:s = col("'[")
    let l:e = col("']")
    if a:type ==# 'block' || line("'[") != line("']")
      let [l:s, l:e] = [min([l:s, l:e]), max([l:s, l:e])]
    endif
    if !l:p.exact
      let [l:s, l:e] = songwriter#tab#columns#Snap(l:block.lines, l:lin, l:s, l:e)
    endif
    if l:s > l:e
      return
    endif
    call cursor(l:lnum, l:s)
    call songwriter#tab#operator#ApplyRange(l:p.op, l:p.reg, l:block, l:s, l:e, l:p.note)
  endif
endfunction

" Apply `op` to columns [s, e] of `block`, cursor on its line. `note` is the
" reach: 0 the time columns (6.2.3), 1 the notes of the cursor's string, a
" string object (6.1.4, 6.1.5), 2 the notes of the cursor's string, a string
" motion (6.2.2).
function! songwriter#tab#operator#ApplyRange(op, reg, block, s, e, note) abort
  if a:note
    call s:noteop(a:op, a:reg, a:block, a:s, a:e, a:note == 1)
  else
    call s:columnwise(a:op, a:reg, a:block, a:s, a:e)
  endif
endfunction

function! s:columnwise(op, reg, block, s, e) abort
  let l:names = songwriter#tab#model#Names(a:block.lines)
  if a:op ==# 'y'
    call songwriter#tab#register#Set(a:reg, songwriter#tab#columns#Extract(a:block.lines, a:s, a:e), 'b', l:names)
    return
  endif
  let l:res = songwriter#tab#columns#DeleteRange(a:block.lines, a:s, a:e)
  call songwriter#tab#register#Set(a:reg, l:res.rows, 'b', l:names)
  call s:write_deleted(a:op, a:block, l:res.lines, a:s)
endfunction

" Write `lines`, from which columns were removed at `s`, lint, then for `c`
" open a slot where they were (6.6), else go to the next note column (6.11).
function! s:write_deleted(op, block, lines, s) abort
  let l:anchor = s:slot_anchor(a:lines, songwriter#tab#model#CursorLin(a:block), a:s)
  if a:op ==# 'c'
    call songwriter#tab#edit#Commit(a:block, {'lines': a:lines, 'col': l:anchor[0]})
    if l:anchor[1] == 0
      call cursor(line('.'), col('.') + 1)
    endif
    call songwriter#tab#slots#OpenHere(l:anchor[1])
  else
    call songwriter#tab#edit#Commit(a:block, {'lines': a:lines})
    call s:to_next_column()
  endif
endfunction

" Spec 6.1.4, 6.1.5, 6.2.2: `op` on the notes in columns [s, e] of the
" cursor's string. The register holds, with the other strings as dashes,
" those columns (`exact`, an object) or what `x` writes for each note (a
" motion, so `dl` fills it as `x`). `d`/`c` erase the notes as `x` does
" (6.7), and `c` opens a slot if a column went.
function! s:noteop(op, reg, block, s, e, exact) abort
  let l:lin = songwriter#tab#model#CursorLin(a:block)
  let l:res = songwriter#tab#columns#EraseNotes(a:block.lines, l:lin, a:s, a:e)
  if empty(l:res)
    return
  endif
  if a:exact
    let l:rows = songwriter#tab#columns#Extract(a:block.lines, a:s, a:e)
    call map(l:rows, 'v:key == l:lin ? v:val : repeat("-", len(v:val))')
  else
    let l:rows = l:res.rows
  endif
  call songwriter#tab#register#Set(a:reg, l:rows, 'b', songwriter#tab#model#Names(a:block.lines))
  if a:op ==# 'y'
    return
  endif
  call cursor(line('.'), l:res.col)
  if l:res.removed
    call s:write_deleted(a:op, a:block, l:res.lines, l:res.col)
  else
    call songwriter#tab#edit#Commit(a:block, {'lines': l:res.lines})
  endif
endfunction

" Where `c` opens its slot once `lines` (just deleted from column s) are
" linted: [column to follow through the lint, side] with side -1 for before
" the next note of the bar, +1 for after the previous one, 0 for an empty bar
" (then the column is the bar's left pipe).
function! s:slot_anchor(lines, lin, s) abort
  let l:pipes = songwriter#tab#model#Pipes(a:lines[a:lin])
  let l:left = max([0] + filter(copy(l:pipes), 'v:val < a:s'))
  let l:right = get(filter(copy(l:pipes), 'v:val >= a:s'), 0, 0)
  let l:cols = filter(songwriter#tab#columns#Columns(a:lines),
        \ 'v:val > l:left && (l:right == 0 || v:val < l:right)')
  let l:next = filter(copy(l:cols), 'v:val >= a:s')
  let l:prev = filter(copy(l:cols), 'v:val < a:s')
  return !empty(l:next) ? [l:next[0], -1] : !empty(l:prev) ? [l:prev[-1], 1] : [l:left, 0]
endfunction

" Spec 6.3: line-wise targets cover every tab they touch, whole.
function! songwriter#tab#operator#ApplyLines(op, reg, l1, l2) abort
  let l:l1 = a:l1
  let l:l2 = a:l2
  if songwriter#grammar#IsTabLine(getline(l:l1))
    let l:l1 = songwriter#tab#model#Read(l:l1).start
  endif
  if songwriter#grammar#IsTabLine(getline(l:l2))
    let l:b = songwriter#tab#model#Read(l:l2)
    let l:l2 = l:b.end
  endif
  if a:op ==# 'y'
    call songwriter#tab#register#Set(a:reg, getline(l:l1, l:l2), 'l', [])
  elseif a:op ==# 'd'
    call songwriter#tab#register#Set(a:reg, getline(l:l1, l:l2), 'l', [])
    call deletebufline('%', l:l1, l:l2)
    call cursor(min([l:l1, line('$')]), 1)
  else
    " 6.3.1: clear every note of each tab, open a slot. Lint then drops the
    " emptied bars at the end (1.4), leaving the first one.
    let l:cur = line('.')
    let l:lnum = l:l1
    while l:lnum <= l:l2
      let l:block = songwriter#tab#model#Read(l:lnum)
      if empty(l:block)
        let l:lnum += 1
        continue
      endif
      let l:lines = songwriter#tab#columns#ClearNotes(l:block.lines)
      call songwriter#tab#model#Write(l:block, songwriter#tab#lint#Lint(l:lines).lines)
      let l:lnum = l:block.end + 1
    endwhile
    if !songwriter#grammar#IsTabLine(getline(l:cur))
      let l:cur = l:l1
    endif
    call cursor(l:cur, songwriter#tab#model#BodyOffset() + 1)
    call songwriter#tab#slots#OpenHere(0)
  endif
endfunction

" Spec 6.11: the cursor goes to the first note column at or after it.
function! s:to_next_column() abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:next = filter(songwriter#tab#columns#Columns(l:block.lines), 'v:val >= col(".")')
  if !empty(l:next)
    call cursor(line('.'), l:next[0])
  endif
endfunction

" === Operator-pending targets ===

" Spec 6.2.1 / 6.2.2: the string motions after an operator (`l`, `h`, `w`,
" `b`, `e`, `ge`). Pure: no slot, no lint. They select the notes they cover on
" the cursor's string, which the operator erases as `x` does; covering no
" note cancels the operator.
function! songwriter#tab#operator#Motion(key) abort
  let l:c = songwriter#tab#model#Cursor()
  call s:select_exact(empty(l:c) ? [] : songwriter#tab#columns#StringMotion(l:c.block.lines,
        \ l:c.line, l:c.col, a:key, v:count1), 2)
endfunction

" Spec 6.1: `ic`/`ac` (kind 'c') and `i|`/`a|` (kind '|'), with a count.
" Selects the range on the cursor line; the operator widens it to every string
" without snapping. Off a column / bar, the operator is cancelled.
function! songwriter#tab#operator#Object(kind, around) abort
  let l:c = songwriter#tab#model#Cursor()
  call s:select_exact(empty(l:c) ? [] : songwriter#tab#columns#Object(a:kind, l:c.block.lines,
        \ l:c.lin, l:c.col, v:count1, a:around), 0)
endfunction

" Spec 6.1.4 / 6.1.5: `in`/`an` (kind 'n') and `iw`/`aw` (kind 'w'), the note
" or word under the cursor on its string.
function! songwriter#tab#operator#StringObject(kind, around) abort
  let l:c = songwriter#tab#model#Cursor()
  call s:select_exact(empty(l:c) ? [] : songwriter#tab#columns#StringObject(a:kind,
        \ l:c.block.lines, l:c.lin, l:c.col, a:around), 1)
endfunction

" Select `range` on the cursor line as the operator's exact target, with the
" reach `note` (see ApplyRange); no range cancels the operator.
function! s:select_exact(range, note) abort
  if empty(a:range)
    let s:pending.cancel = 1
    return
  endif
  let s:pending.exact = 1
  let s:pending.note = a:note
  call cursor(line('.'), a:range[0])
  normal! v
  call cursor(line('.'), a:range[1])
endfunction

" === Erase and paste (spec 6.5, 6.7) ===

" `x` in normal mode: on a dash, enter a muted note as a digit would (spec 3.4.3);
" elsewhere, erase (6.7).
function! songwriter#tab#operator#EraseOrMute(count, reg) abort
  if getline('.')[col('.') - 1] ==# '-'
    call songwriter#tab#EnterNote('x')
  else
    call songwriter#tab#operator#Erase(a:count, a:reg)
  endif
endfunction

" Spec 6.7: `x`, `count` times on the cursor's string (after the first, from
" the next note on the string). Writes what was erased to `reg` (6.7.3).
function! songwriter#tab#operator#Erase(count, reg) abort
  let l:block = songwriter#tab#edit#LintAndFollow(songwriter#tab#model#Read())
  if empty(l:block)
    return
  endif
  let l:rows = []
  let l:lone = 0
  for l:i in range(max([a:count, 1]))
    let l:lin = songwriter#tab#model#CursorLin(l:block)
    if l:i > 0 && !s:on_note(getline('.'), col('.'))
      let l:next = filter(map(songwriter#tab#model#Notes(getline('.')), 'v:val.col'), 'v:val > col(".")')
      if empty(l:next)
        break
      endif
      call cursor(line('.'), l:next[0])
    endif
    let l:res = songwriter#tab#columns#EraseNote(l:block.lines, l:lin, col('.'))
    if empty(l:res)
      break
    endif
    let l:lone = len(l:res.lines[l:lin]) < len(l:block.lines[l:lin])
    let l:rows = empty(l:rows) ? l:res.rows : map(l:rows, 'v:val . l:res.rows[v:key]')
    let l:block = songwriter#tab#edit#Commit(l:block, l:res)
  endfor
  if empty(l:rows)
    return
  endif
  call songwriter#tab#register#Set(a:reg, l:rows, 'b', songwriter#tab#model#Names(l:block.lines))
  if l:lone
    call s:to_next_column()
  endif
  call songwriter#tab#repeat#Record("songwriter#tab#operator#Erase(%d, '" . a:reg . "')", a:count)
endfunction

function! s:on_note(line, col) abort
  return !empty(filter(songwriter#tab#model#Notes(a:line),
        \ 'v:val.col <= a:col && a:col < v:val.col + v:val.len'))
endfunction

" Spec 6.5 / 6.3.2: `p` (before 0) / `P` (before 1) from register `reg`.
function! songwriter#tab#operator#Put(before, count, reg) abort
  let l:block = songwriter#tab#edit#LintAndFollow(songwriter#tab#model#Read())
  if empty(l:block)
    return
  endif
  let l:rows = songwriter#tab#register#BlockRows(a:reg)
  if getregtype(a:reg) ==# 'V'
    call s:put_lines(l:block, getreg(a:reg, 1, 1), a:before, a:count)
  elseif !empty(l:rows)
    let l:res = songwriter#tab#columns#Paste(l:block.lines, songwriter#tab#model#CursorLin(l:block),
          \ col('.'), l:rows, songwriter#tab#register#Names(a:reg), a:before, a:count)
    if empty(songwriter#tab#edit#Commit(l:block, l:res))
      return
    endif
  else
    call songwriter#tab#edit#Error('songwriter: cannot paste a character-wise register into a tab')
    return
  endif
  call songwriter#tab#repeat#Record(printf("songwriter#tab#operator#Put(%d, %%d, '%s')", a:before, a:reg), a:count)
endfunction

" A line-wise register goes after the tab (before it for `P`), never between
" its strings; a blank line keeps pasted tab lines from joining the tab.
function! s:put_lines(block, rows, before, count) abort
  let l:rows = []
  for l:i in range(max([a:count, 1]))
    call extend(l:rows, a:rows)
  endfor
  if empty(l:rows)
    return
  endif
  if a:before
    if songwriter#grammar#IsTabLine(l:rows[-1])
      call add(l:rows, '')
    endif
    let l:at = a:block.start - 1
    let l:first = l:at + 1
  else
    if songwriter#grammar#IsTabLine(l:rows[0])
      call insert(l:rows, '')
    endif
    let l:at = a:block.end
    let l:first = l:at + 1 + (l:rows[0] ==# '' ? 1 : 0)
  endif
  call append(l:at, l:rows)
  call cursor(l:first, 1)
endfunction

" Spec 6.13: `>>` (dir +1) / `<<` (dir -1), `count` times.
function! songwriter#tab#operator#Shift(dir, count) abort
  let l:block = songwriter#tab#edit#LintAndFollow(songwriter#tab#model#Read())
  if empty(l:block)
    return
  endif
  let l:done = 0
  for l:i in range(max([a:count, 1]))
    let l:res = songwriter#tab#columns#ShiftColumn(l:block.lines, songwriter#tab#model#CursorLin(l:block), col('.'), a:dir)
    if empty(l:res)
      break
    endif
    let l:block = songwriter#tab#edit#Commit(l:block, l:res)
    let l:done = 1
  endfor
  if l:done
    call songwriter#tab#repeat#Record('songwriter#tab#operator#Shift(' . a:dir . ', %d)', a:count)
  endif
endfunction

" Spec 6.14: `gp`, overlay a column register onto the cursor's column.
function! songwriter#tab#operator#Overlay(reg) abort
  call songwriter#tab#edit#Run(function('s:overlay', [a:reg]))
endfunction

function! s:overlay(reg, ctx) abort
  let l:rows = songwriter#tab#register#BlockRows(a:reg)
  if empty(l:rows)
    return {'error': 'songwriter: gp pastes a column register'}
  endif
  return songwriter#tab#columns#Overlay(a:ctx.block.lines, a:ctx.lin, a:ctx.col,
        \ l:rows, songwriter#tab#register#Names(a:reg))
endfunction

