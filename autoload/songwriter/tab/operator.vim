" autoload/songwriter/tab/operator.vim - tablature-mode operators and text
" objects (spec [Tablature][[Editing]] 6): the buffer entry points
" around the pure column model (tab/columns.vim). Visual mode is tab/visual.vim,
" the actions that are not operators (`x`, `p`/`P`, `>>`/`<<`, `gp`)
" tab/actions.vim, registers tab/register.vim, `.` tab/repeat.vim. See design.md "Operators and
" text objects".
"
" d/y/c, and `play` (12, which only reads the tab), run through 'operatorfunc' and g@, so counts, motions and `.` work as
" for native operators. The operator, register, whether the target was one of
" our text objects or string motions (exact: no snapping) and its reach
" (`note`, see ApplyRange) are kept in s:pending, since v:register is not
" reliable inside 'operatorfunc'.
"
" s:pending is a script variable rather than a state of tab/state.vim
" because Vim puts it there: 'operatorfunc' takes no arguments, so what the
" operator key decided reaches Opfunc only through the script. It holds from
" one operator key to the next (Start replaces it; Opfunc resets what its
" target set), whatever the buffer.
"
" Each operator on columns or notes is a pure function of the block (edit#Do's
" Fn) returning one result: the lines, linted, the register, the cursor and,
" for `c`, the slot to open ('open'); edit#Do sets the register and the cursor.

let s:pending = {'op': 'd', 'reg': '"', 'exact': 0, 'note': 0, 'across': {}, 'cancel': 0, 'tick': -1}

" === Operators ===

" The pending operator and its register: {'op', 'reg'} (for the annotation
" objects, tab/annotate.vim).
function! songwriter#tab#operator#Pending() abort
  return {'op': s:pending.op, 'reg': s:pending.reg}
endfunction

" `d`/`y`/`c` in tablature mode: lint first (own undo step, joined to the
" operation's), then g@. The <Cmd> that lints consumes the count, so it is
" given again after g@ (`3dw` runs as `g@3w`). `play` (spec 12) changes
" nothing, not even with a lint: just g@.
function! songwriter#tab#operator#Start(op) abort
  let s:pending = {'op': a:op, 'reg': v:register, 'exact': 0, 'note': 0, 'across': {}, 'cancel': 0, 'tick': -1}
  set operatorfunc=songwriter#tab#operator#Opfunc
  if a:op ==# 'play'
    return 'g@'
  endif
  return "\<Cmd>call songwriter#tab#operator#Prelint()\<CR>g@"
        \ . (v:count ? v:count : '')
endfunction

" `Y` (target "column": the column, as `yy`), `D`, `C` (target "bar-end": to
" the end of the bar, as `dW`/`cW`) and `<leader>P` (target "note": the note,
" as `in`, spec 12.1): the operator, then its target as a <Cmd> (a returned
" key would not be remapped).
function! songwriter#tab#operator#StartOn(op, target) abort
  let l:keys = songwriter#tab#operator#Start(a:op)
  return l:keys . {
        \ 'column': "\<Cmd>call songwriter#tab#operator#Object('c', 1)\<CR>",
        \ 'bar-end': "\<Cmd>call songwriter#keys#JumpBarLine(1)\<CR>",
        \ 'note': "\<Cmd>call songwriter#tab#operator#StringObject('n', 0)\<CR>",
        \ }[a:target]
endfunction

" Spec 6.8, 12.1: the second key of `dd`/`yy`/`cc`/`<leader>pp` (after the
" operator, so `d3d` takes a count): the column and its gap, as `ac`. Another
" operator key (`dy`) cancels.
function! songwriter#tab#operator#Doubled(key) abort
  if s:pending.op ==# get({'p': 'play'}, a:key, a:key)
    call songwriter#tab#operator#Object('c', 1)
  else
    let s:pending.cancel = 1
  endif
endfunction

" The lint before g@ (Start). On a tab with no time columns, the operator is
" refused (spec [Tablature][[Editing]] 4.5): g@ still takes its target, then
" does nothing.
function! songwriter#tab#operator#Prelint() abort
  let l:block = songwriter#tab#model#Around(line('.'))
  if !empty(l:block) && songwriter#tab#edit#Untimed(l:block)
    let s:pending.cancel = 1
    return
  endif
  let l:tick = b:changedtick
  call songwriter#tab#edit#Do({_ -> {}})
  let s:pending.tick = b:changedtick != l:tick ? b:changedtick : -1
endfunction

function! songwriter#tab#operator#Opfunc(type) abort
  let l:p = copy(s:pending)
  let s:pending.exact = 0
  let s:pending.note = 0
  let s:pending.across = {}
  let s:pending.cancel = 0
  if l:p.cancel
    return
  endif
  " The edit joins the undo step of the lint before g@ (Start).
  call s:apply(a:type, l:p, l:p.tick == b:changedtick)
endfunction

" Apply the pending operator `p` to the marks of g@ ('operatorfunc' `type`),
" joining the previous undo step when `join` is set.
function! s:apply(type, p, join) abort
  let l:p = a:p
  if a:type ==# 'line'
    if a:join
      call songwriter#tab#edit#JoinUndo()
    endif
    call songwriter#tab#operator#ApplyLines(l:p.op, l:p.reg, line("'["), line("']"))
    return
  endif
  let l:lnum = line("'[")
  let l:block = songwriter#tab#model#Read(l:lnum)
  if empty(l:block)
    return
  endif
  let l:s = col("'[")
  let l:e = col("']")
  if a:type ==# 'block' || line("'[") != line("']")
    let [l:s, l:e] = [min([l:s, l:e]), max([l:s, l:e])]
  endif
  if !l:p.exact
    let [l:s, l:e] = songwriter#tab#objects#Snap(l:block.lines, l:lnum - l:block.start, l:s, l:e)
  endif
  if l:s > l:e
    return
  endif
  if !empty(l:p.across)
    call s:apply_across(l:p.op, l:p.reg, l:lnum, l:p.across, a:join)
  else
    call songwriter#tab#operator#ApplyRange(l:p.op, l:p.reg, l:lnum, l:s, l:e, l:p.note, a:join)
  endif
endfunction

" Apply `op` to columns [s, e] of the block of line `lnum`, as an edit of that
" line (edit#Do) joining the previous undo step when `join` (optional) is set.
" `note` is the reach: 0 the time columns (6.2.3), 1 the notes of that string,
" a string object (6.1.4, 6.1.5), 2 the notes of that string, a string motion
" (6.2.2). `play` plays the notes of that reach (12.1), the cursor on s.
function! songwriter#tab#operator#ApplyRange(op, reg, lnum, s, e, note, ...) abort
  if a:op ==# 'play'
    let l:block = songwriter#tab#model#Read(a:lnum)
    call cursor(a:lnum, a:s)
    call songwriter#tab#play#Play([[l:block.lines,
          \ a:note ? [a:lnum - l:block.start] : range(len(l:block.lines)), a:s, a:e]])
    return
  endif
  call s:edit(a:op, a:lnum, a:0 && a:1, a:note
        \ ? function('s:noteop', [a:op, a:reg, a:lnum, a:s, a:e, a:note == 1])
        \ : function('s:columnwise', [a:op, a:reg, a:lnum, a:s, a:e]))
endfunction

" Spec 6.2.4: apply `op` to the notes starting on time column `a.col` of the
" strings `a.lins` ([first, last], 0-indexed) of the block of line `lnum`.
function! s:apply_across(op, reg, lnum, a, join) abort
  if a:op ==# 'play'
    let l:block = songwriter#tab#model#Read(a:lnum)
    call cursor(a:lnum, a:a.col)
    call songwriter#tab#play#Play([[l:block.lines, range(a:a.lins[0], a:a.lins[1]), a:a.col, a:a.col]])
    return
  endif
  call s:edit(a:op, a:lnum, a:join, function('s:across', [a:op, a:reg, a:lnum, a:a]))
endfunction

" Fn(ctx), the edit of operator `op` (s:columnwise, s:noteop, s:across),
" applied to the block of line `lnum` as it is: it lints its own result, and
" a yank changes nothing.
function! s:edit(op, lnum, join, Fn) abort
  call songwriter#tab#edit#Do(a:Fn, {'lnum': a:lnum, 'prelint': 0, 'lint': 0, 'join': a:join})
endfunction

" Pure. Spec 6.2.3, 6.4, 6.6: `op` on columns [s, e] of `ctx.block`, the
" cursor on line `lnum`: the columns go into register `reg`, and, but for `y`,
" are deleted (s:deleted).
function! s:columnwise(op, reg, lnum, s, e, ctx) abort
  let l:block = a:ctx.block
  let l:lin = a:lnum - l:block.start
  let l:res = songwriter#tab#columns#DeleteRange(l:block.lines, a:s, a:e)
  let l:register = s:register(a:reg, l:block, l:res.rows, l:res.map, a:s)
  if a:op ==# 'y'
    return {'register': l:register, 'lin': l:lin, 'col': a:s}
  endif
  return extend(s:deleted(a:op, l:res, l:lin, a:s), {'register': l:register})
endfunction

" Pure. Register `reg` set to the column rows `rows` taken from `block` from
" column `col`, with the annotations above them ([[Annotations]] 5.1): those
" that the edit of map `map` deletes (or, for a yank, would delete). As a
" result's 'register' (edit.vim).
function! s:register(reg, block, rows, map, col) abort
  let l:above = songwriter#tab#annotations#Rows(songwriter#tab#annotations#Cut(a:block.above, a:map), a:col)
  return {'name': a:reg, 'rows': l:above + a:rows, 'type': 'b',
        \ 'names': songwriter#tab#model#Names(a:block.lines), 'above': len(l:above)}
endfunction

" Pure. The result of `op` (`d` or `c`) whose edit `res` ({'lines', 'map',
" 'erased' (optional)}) removed columns at `s`, the cursor on line `lin`:
" linted, then for `c` a slot opened where they were (6.6), else the cursor
" on the next note column (6.11).
function! s:deleted(op, res, lin, s) abort
  if a:op !=# 'c'
    let l:r = s:linted(a:res, a:lin, a:s)
    let l:line = l:r.lines[a:lin]
    let l:r.col = songwriter#tab#columns#NextColumn(l:r.lines, max([1, min([l:r.col, len(l:line)])]))
    return l:r
  endif
  let l:anchor = s:slot_anchor(a:res.lines, a:lin, a:s)
  let l:r = s:linted(a:res, a:lin, l:anchor[0])
  let l:len = len(l:r.lines[a:lin])
  let l:r.col = max([1, min([l:r.col, l:len])])
  if l:anchor[1] == 0
    " The anchor is the bar's left pipe: the slot is in the bar after it.
    let l:r.col = min([l:r.col + 1, l:len])
  endif
  return extend(l:r, {'open': l:anchor[1]})
endfunction

" Pure. The edit `res` ({'lines', 'map', 'erased' (optional)}) linted, with
" the cursor on line `lin` at column `col` of its lines following the music:
" a result (edit.vim).
function! s:linted(res, lin, col) abort
  let l:linted = songwriter#tab#edit#Linted(a:res.lines, a:lin,
        \ max([1, min([a:col, len(a:res.lines[a:lin])])]))
  return {'lines': l:linted.lines, 'map': songwriter#tab#colmap#Then(a:res.map, l:linted.map),
        \ 'erased': get(a:res, 'erased', []), 'lin': a:lin, 'col': l:linted.col}
endfunction

" Pure. Spec 6.1.4, 6.1.5, 6.2.2: `op` on the notes in columns [s, e] of the
" string of line `lnum`. The register holds, with the other strings as
" dashes, those columns (`exact`, an object) or what `x` writes for each note
" (a motion, so `dl` fills it as `x`). `d`/`c` erase the notes as `x` does
" (6.7), and `c` opens a slot if a column went.
function! s:noteop(op, reg, lnum, s, e, exact, ctx) abort
  let l:block = a:ctx.block
  let l:lin = a:lnum - l:block.start
  let l:res = songwriter#tab#columns#EraseNotes(l:block.lines, l:lin, a:s, a:e)
  if empty(l:res)
    return {'lin': l:lin, 'col': a:s}
  endif
  if a:exact
    let l:rows = songwriter#tab#columns#Extract(l:block.lines, a:s, a:e)
    call map(l:rows, 'v:key == l:lin ? v:val : repeat("-", len(v:val))')
  else
    let l:rows = l:res.rows
  endif
  return s:erased(a:op, s:register(a:reg, l:block, l:rows, l:res.map, a:s), l:res, l:lin, a:s)
endfunction

" Pure. Spec 6.2.4: `op` on the notes starting on time column `a.col` of the
" strings `a.lins` ([first, last], 0-indexed), each erased as `x` does, the
" cursor on line `lnum`. The register holds that column and its gap, the
" other strings as dashes; `c` opens a slot if the column went.
function! s:across(op, reg, lnum, a, ctx) abort
  let l:block = a:ctx.block
  let l:lin = a:lnum - l:block.start
  let l:notes = []
  for l:l in range(a:a.lins[0], a:a.lins[1])
    if !empty(filter(copy(l:block.strings[l:l].notes), 'v:val.col == a:a.col'))
      call add(l:notes, {'lin': l:l, 'col': a:a.col})
    endif
  endfor
  if empty(l:notes)
    return {'lin': l:lin, 'col': a:a.col}
  endif
  let l:e = songwriter#tab#model#GapEnd(l:block, l:lin,
        \ songwriter#tab#model#BarColumns(l:block, l:lin, a:a.col), a:a.col)
  let l:lins = map(copy(l:notes), 'v:val.lin')
  let l:rows = map(songwriter#tab#columns#Extract(l:block.lines, a:a.col, l:e),
        \ {i, r -> index(l:lins, i) >= 0 ? r : repeat('-', len(r))})
  let l:res = songwriter#tab#columns#EraseSet(l:block.lines, l:notes)
  return s:erased(a:op, s:register(a:reg, l:block, l:rows, l:res.map, a:a.col), l:res, l:lin, a:a.col)
endfunction

" Pure. The result of `op` once notes are erased (`res`, as
" columns#EraseSet gives it) from the range starting at `s`, with register
" `register`, the cursor on line `lin`: for `y`, the register alone; else the
" erasure, as a deletion (s:deleted) when a column went.
function! s:erased(op, register, res, lin, s) abort
  if a:op ==# 'y'
    return {'register': a:register, 'lin': a:lin, 'col': a:s}
  endif
  let l:r = a:res.removed ? s:deleted(a:op, a:res, a:lin, a:res.col)
        \ : s:linted(a:res, a:lin, a:res.col)
  return extend(l:r, {'register': a:register})
endfunction

" Where `c` opens its slot once `lines` (just deleted from column s) are
" linted: [column to follow through the lint, side] with side -1 for before
" the next note of the bar, +1 for after the previous one, 0 for an empty bar
" (then the column is the bar's left pipe).
function! s:slot_anchor(lines, lin, s) abort
  let l:pipes = songwriter#tab#model#Pipes(a:lines[a:lin])
  let l:left = max([0] + filter(copy(l:pipes), 'v:val < a:s'))
  let l:right = get(filter(copy(l:pipes), 'v:val >= a:s'), 0, 0)
  let l:cols = filter(songwriter#tab#model#NoteColumns(songwriter#tab#model#Parse(0, a:lines)),
        \ 'v:val > l:left && (l:right == 0 || v:val < l:right)')
  let l:next = filter(copy(l:cols), 'v:val >= a:s')
  let l:prev = filter(copy(l:cols), 'v:val < a:s')
  return !empty(l:next) ? [l:next[0], -1] : !empty(l:prev) ? [l:prev[-1], 1] : [l:left, 0]
endfunction

" Spec 6.3: line-wise targets cover every tab they touch, whole, annotations
" included ([[Annotations]] 2.1). `play` plays them one after the other
" (12.1).
function! songwriter#tab#operator#ApplyLines(op, reg, l1, l2) abort
  if a:op ==# 'play'
    call songwriter#tab#play#Play(s:tabs_in(a:l1, a:l2))
    return
  endif
  let l:l1 = a:l1
  let l:l2 = a:l2
  if songwriter#grammar#IsTabLine(getline(l:l1))
    let l:l1 = songwriter#tab#model#Read(l:l1).top
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
    " 6.3.1: clear every note of each tab, and its annotations ([[Annotations]]
    " 2.1), open a slot. Lint then drops the emptied bars at the end (1.4),
    " leaving the first one. The cursor stays on its string.
    let l:cur = line('.')
    let l:first = 0
    let l:lnum = l:l1
    while l:lnum <= l:l2
      let l:block = songwriter#tab#model#Read(l:lnum)
      if empty(l:block)
        let l:lnum += 1
        continue
      endif
      let l:new = songwriter#tab#edit#Do({ctx -> {'lines': songwriter#tab#columns#ClearNotes(ctx.block.lines),
            \ 'map': [], 'annotations': [{'op': 'clear'}],
            \ 'erased': songwriter#tab#check#Notes(ctx.block.lines)}}, {'lnum': l:lnum, 'prelint': 0})
      let l:shift = l:new.end - l:block.end
      if l:cur >= l:block.start
        let l:cur += l:shift
      endif
      let l:first = l:first ? l:first : l:new.start
      let [l:l2, l:lnum] = [l:l2 + l:shift, l:new.end + 1]
    endwhile
    if !songwriter#grammar#IsTabLine(getline(l:cur))
      let l:cur = l:first ? l:first : l:l1
    endif
    let l:col = songwriter#tab#model#BodyOffset() + 1
    if !l:first
      call cursor(l:cur, l:col)
      return
    endif
    call songwriter#tab#edit#Do({ctx -> {'lin': l:cur - ctx.block.start, 'col': l:col, 'open': 0}},
          \ {'lnum': l:cur, 'prelint': 0, 'lint': 0})
  endif
endfunction

" The tabs with a line in [l1, l2], whole, as [lines, every string, first
" column, last column] (see songwriter#tab#play#Play).
function! s:tabs_in(l1, l2) abort
  let l:tabs = []
  let l:lnum = a:l1
  while l:lnum <= a:l2
    let l:block = songwriter#tab#model#Read(l:lnum)
    if empty(l:block)
      let l:lnum += 1
      continue
    endif
    call add(l:tabs, [l:block.lines, range(len(l:block.lines)), 1, max(map(copy(l:block.lines), 'len(v:val)'))])
    let l:lnum = l:block.end + 1
  endwhile
  return l:tabs
endfunction

" === Operator-pending targets ===

" Spec 6.2.1 / 6.2.2: the string motions after an operator (`l`, `h`, `w`,
" `b`, `e`, `ge`). Pure: no slot, no lint. They select the notes they cover on
" the cursor's string, which the operator erases as `x` does; covering no
" note cancels the operator.
function! songwriter#tab#operator#Motion(key) abort
  let l:c = songwriter#tab#model#Cursor()
  call s:select_exact(empty(l:c) ? [] : songwriter#tab#stops#StringMotion(l:c.block.lines,
        \ l:c.line, l:c.col, a:key, v:count1), 2)
endfunction

" Spec 6.2.4: `j`/`k` after an operator: the time column under the cursor
" (as `ic` finds it), on the cursor's string and `count` more below / above;
" `J`/`K` down to the bottom / up to the top string. With no string that way
" or no column, the operator is cancelled.
function! songwriter#tab#operator#Across(key) abort
  let l:c = songwriter#tab#model#Cursor()
  if empty(l:c) || songwriter#tab#columns#OnPipeOrName(l:c.line, l:c.col)
    let s:pending.cancel = 1
    return
  endif
  let l:last = len(l:c.block.lines) - 1
  if a:key ==# 'j' && l:c.lin == l:last || a:key ==# 'k' && l:c.lin == 0
    let s:pending.cancel = 1
    return
  endif
  let l:to = {'j': l:c.lin + v:count1, 'k': l:c.lin - v:count1, 'J': l:last, 'K': 0}[a:key]
  let l:to = max([0, min([l:to, l:last])])
  let l:col = songwriter#tab#model#ColumnFor(
        \ songwriter#tab#model#BarColumns(l:c.block, l:c.lin, l:c.col).cols, l:c.col)
  if l:col == 0
    let s:pending.cancel = 1
    return
  endif
  call s:select_exact([l:col, l:col], 0)
  let s:pending.across = {'col': l:col, 'lins': [min([l:c.lin, l:to]), max([l:c.lin, l:to])]}
endfunction

" Spec 6.1: `ic`/`ac` (kind 'c') and `i|`/`a|` (kind '|'), with a count.
" Selects the range on the cursor line; the operator widens it to every string
" without snapping. Off a column / bar, the operator is cancelled.
function! songwriter#tab#operator#Object(kind, around) abort
  let l:c = songwriter#tab#model#Cursor()
  call s:select_exact(empty(l:c) ? [] : songwriter#tab#objects#Object(a:kind, l:c.block.lines,
        \ l:c.lin, l:c.col, v:count1, a:around), 0)
endfunction

" Spec 6.1.4 / 6.1.5: `in`/`an` (kind 'n') and `iw`/`aw` (kind 'w'), the note
" or word under the cursor on its string.
function! songwriter#tab#operator#StringObject(kind, around) abort
  let l:c = songwriter#tab#model#Cursor()
  call s:select_exact(empty(l:c) ? [] : songwriter#tab#objects#StringObject(a:kind,
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
