" autoload/songwriter/tab/operator.vim - tablature-mode operators, text objects
" and their registers (spec [Tablature][[Editing]] 6): the buffer entry points
" around the pure column model (tab/columns.vim). See design.md "Operators and
" text objects".
"
" d/y/c run through 'operatorfunc' and g@, so counts, motions and `.` work as
" for native operators. The operator, register and whether the target was one
" of our text objects (exact: no snapping) are kept in s:pending, since
" v:register is not reliable inside 'operatorfunc'.

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
" "bar-end": to the end of the bar, as `dL`/`cL`): the operator, then its
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
    call s:linewise(l:p.op, l:p.reg, line("'["), line("']"))
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
    if l:p.note
      call s:noteop(l:p.op, l:p.reg, l:block, l:s, l:e)
    else
      call s:columnwise(l:p.op, l:p.reg, l:block, l:s, l:e)
    endif
  endif
endfunction

" Apply `op` to columns [s, e] of `block`, cursor on its line.
function! s:columnwise(op, reg, block, s, e) abort
  let l:names = s:names(a:block.lines)
  if a:op ==# 'y'
    call s:setreg(a:reg, songwriter#tab#columns#Extract(a:block.lines, a:s, a:e), 'b', l:names)
    return
  endif
  let l:res = songwriter#tab#columns#DeleteRange(a:block.lines, a:s, a:e)
  call s:setreg(a:reg, l:res.rows, 'b', l:names)
  call s:write_deleted(a:op, a:block, l:res.lines, a:s)
endfunction

" Write `lines`, from which columns were removed at `s`, lint, then for `c`
" open a slot where they were (6.6), else go to the next note column (6.11).
function! s:write_deleted(op, block, lines, s) abort
  let l:anchor = s:slot_anchor(a:lines, line('.') - a:block.start, a:s)
  if a:op ==# 'c'
    call songwriter#tab#edit#Commit(a:block, {'lines': a:lines, 'col': l:anchor[0]})
    if l:anchor[1] == 0
      call cursor(line('.'), col('.') + 1)
    endif
    call s:open_slot(l:anchor[1])
  else
    call songwriter#tab#edit#Commit(a:block, {'lines': a:lines})
    call s:to_next_column()
  endif
endfunction

" Spec 6.1.4: `op` on the note at columns [s, e] of the cursor's string: the
" register holds those columns with the other strings as dashes; `d`/`c`
" erase the note as `x` does (6.7), and `c` opens a slot if its column went.
function! s:noteop(op, reg, block, s, e) abort
  let l:lin = line('.') - a:block.start
  let l:rows = songwriter#tab#columns#Extract(a:block.lines, a:s, a:e)
  call map(l:rows, 'v:key == l:lin ? v:val : repeat("-", len(v:val))')
  call s:setreg(a:reg, l:rows, 'b', s:names(a:block.lines))
  if a:op ==# 'y'
    return
  endif
  let l:res = songwriter#tab#columns#EraseNote(a:block.lines, l:lin, a:s)
  if empty(l:res)
    return
  endif
  if len(l:res.lines[l:lin]) < len(a:block.lines[l:lin])
    call s:write_deleted(a:op, a:block, l:res.lines, a:s)
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
function! s:linewise(op, reg, l1, l2) abort
  let l:l1 = a:l1
  let l:l2 = a:l2
  if songwriter#grammar#IsTabLine(getline(l:l1))
    let l:l1 = songwriter#tab#model#Read(l:l1).start
  endif
  if songwriter#grammar#IsTabLine(getline(l:l2))
    let l:b = songwriter#tab#model#Read(l:l2)
    let l:l2 = l:b.start + len(l:b.lines) - 1
  endif
  if a:op ==# 'y'
    call s:setreg(a:reg, getline(l:l1, l:l2), 'l', [])
  elseif a:op ==# 'd'
    call s:setreg(a:reg, getline(l:l1, l:l2), 'l', [])
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
      let l:lnum = l:block.start + len(l:block.lines)
    endwhile
    if !songwriter#grammar#IsTabLine(getline(l:cur))
      let l:cur = l:l1
    endif
    call cursor(l:cur, 3)
    call s:open_slot(0)
  endif
endfunction

" Spec 6.6: open a slot at the cursor: before its note (side -1, as `i`),
" after it (+1, as `a`), or, side 0, in the cursor's empty bar.
function! s:open_slot(side) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:line = getline('.')
  if a:side < 0
    let l:res = songwriter#tab#PrependSlot(l:block, l:line, col('.'))
  elseif a:side > 0
    let l:res = songwriter#tab#AppendSlot(l:block, l:line, col('.'))
  else
    let l:res = songwriter#tab#columns#EmptyBarSlot(l:block.lines, line('.') - l:block.start, col('.'))
  endif
  if empty(l:res)
    return
  endif
  call songwriter#tab#edit#Apply(l:block, l:res)
  let b:songwriter_slot = {'line': line('.'), 'tick': b:changedtick}
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

" === Registers (spec 6.4) ===

" Set register `reg` and remember the string names of its source tab, so a
" paste can match strings by name (6.5.3) while the register is unchanged.
function! s:setreg(reg, rows, type, names) abort
  call setreg(a:reg, a:rows, a:type)
  if !exists('g:songwriter_register_names')
    let g:songwriter_register_names = {}
  endif
  let g:songwriter_register_names[a:reg] = {'names': a:names, 'rows': getreg(a:reg, 1, 1)}
endfunction

" The string names recorded for register `reg`, or [] when unknown or stale.
function! songwriter#tab#operator#RegisterNames(reg) abort
  let l:r = get(get(g:, 'songwriter_register_names', {}), a:reg, {})
  return !empty(l:r) && l:r.rows ==# getreg(a:reg, 1, 1) ? l:r.names : []
endfunction

function! s:names(lines) abort
  return map(copy(a:lines), 'v:val[0]')
endfunction

" === Operator-pending targets ===

" Spec 6.2.1: tablature-mode motions after an operator. Pure: no slot, no lint.
" `w`/`b`: note starts on this string; `l`/`h`: note columns of the block.
" Forward motions also stop at pipes, backward ones at a bar's first column, so
" a count-less motion never crosses a bar line.
function! songwriter#tab#operator#Motion(key) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:line = getline('.')
  if a:key =~# '[wb]'
    let l:stops = map(songwriter#tab#columns#Atoms(l:line), 'v:val.col')
  else
    let l:stops = songwriter#tab#columns#Columns(l:block.lines)
  endif
  let l:pipes = songwriter#tab#model#Pipes(l:line)
  let l:fwd = a:key =~# '[wl]'
  let l:stops += l:fwd ? l:pipes : map(copy(l:pipes), 'v:val + 1')
  let l:stops = uniq(sort(l:stops, 'n'))
  let l:col = col('.')
  for l:i in range(v:count1)
    let l:c = filter(copy(l:stops), l:fwd ? 'v:val > l:col' : 'v:val < l:col')
    if empty(l:c)
      break
    endif
    let l:col = l:fwd ? l:c[0] : l:c[-1]
  endfor
  call cursor(line('.'), l:col)
endfunction

" Spec 6.1: `ic`/`ac` (kind 'c') and `i|`/`a|` (kind '|'), with a count.
" Selects the range on the cursor line; the operator widens it to every string
" without snapping. Off a column / bar, the operator is cancelled.
function! songwriter#tab#operator#Object(kind, around) abort
  let l:block = songwriter#tab#model#Read()
  let l:range = []
  if !empty(l:block)
    let l:lin = line('.') - l:block.start
    let l:range = a:kind ==# 'c'
          \ ? songwriter#tab#columns#ColumnObject(l:block.lines, l:lin, col('.'), v:count1, a:around)
          \ : songwriter#tab#columns#BarObject(l:block.lines, l:lin, col('.'), v:count1, a:around)
  endif
  if empty(l:range)
    let s:pending.cancel = 1
    return
  endif
  let s:pending.exact = 1
  call cursor(line('.'), l:range[0])
  normal! v
  call cursor(line('.'), l:range[1])
endfunction

" Spec 6.1.4: the note under the cursor on its string: `in`, or `an` with its
" gap. On a dash, the nearest note of the string to the left in the bar.
" Returns [s, e] or [].
function! s:note_range(around) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return []
  endif
  let l:line = getline('.')
  let l:bar = songwriter#tab#model#BarAt(l:line, col('.'))
  let l:notes = filter(songwriter#tab#columns#Atoms(l:line),
        \ 'v:val.col <= col(".") && songwriter#tab#model#InBar(v:val.col, l:bar)')
  if empty(l:notes)
    return []
  endif
  let l:n = l:notes[-1]
  if !a:around
    return [l:n.col, l:n.col + l:n.len - 1]
  endif
  let l:col = songwriter#tab#columns#ColumnObject(l:block.lines, line('.') - l:block.start, l:n.col, 1, 1)
  return [l:n.col, max([l:col[1], l:n.col + l:n.len - 1])]
endfunction

function! songwriter#tab#operator#NoteObject(around) abort
  let l:range = s:note_range(a:around)
  if empty(l:range)
    let s:pending.cancel = 1
    return
  endif
  let s:pending.exact = 1
  let s:pending.note = 1
  call cursor(line('.'), l:range[0])
  normal! v
  call cursor(line('.'), l:range[1])
endfunction

" === Erase and paste (spec 6.5, 6.7) ===

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
    let l:lin = line('.') - l:block.start
    if l:i > 0 && !s:on_note(getline('.'), col('.'))
      let l:next = filter(map(songwriter#tab#columns#Atoms(getline('.')), 'v:val.col'), 'v:val > col(".")')
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
  call s:setreg(a:reg, l:rows, 'b', s:names(l:block.lines))
  if l:lone
    call s:to_next_column()
  endif
  call songwriter#tab#operator#Record("songwriter#tab#operator#Erase(%d, '" . a:reg . "')", a:count)
endfunction

function! s:on_note(line, col) abort
  return !empty(filter(songwriter#tab#columns#Atoms(a:line),
        \ 'v:val.col <= a:col && a:col < v:val.col + v:val.len'))
endfunction

" Spec 6.5 / 6.3.2: `p` (before 0) / `P` (before 1) from register `reg`.
function! songwriter#tab#operator#Put(before, count, reg) abort
  let l:block = songwriter#tab#edit#LintAndFollow(songwriter#tab#model#Read())
  if empty(l:block)
    return
  endif
  let l:type = getregtype(a:reg)
  let l:rows = getreg(a:reg, 1, 1)
  if l:type ==# 'V'
    call s:put_lines(l:block, l:rows, a:before, a:count)
  elseif l:type[0] ==# "\<C-V>" && !empty(l:rows)
    let l:res = songwriter#tab#columns#Paste(l:block.lines, line('.') - l:block.start,
          \ col('.'), l:rows, songwriter#tab#operator#RegisterNames(a:reg), a:before, a:count)
    if empty(songwriter#tab#edit#Commit(l:block, l:res))
      return
    endif
  else
    call songwriter#tab#edit#Error('songwriter: cannot paste a character-wise register into a tab')
    return
  endif
  call songwriter#tab#operator#Record(printf("songwriter#tab#operator#Put(%d, %%d, '%s')", a:before, a:reg), a:count)
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
    let l:at = a:block.start + len(a:block.lines) - 1
    let l:first = l:at + 1 + (l:rows[0] ==# '' ? 1 : 0)
  endif
  call append(l:at, l:rows)
  call cursor(l:first, 1)
endfunction

" Remember an action that is not an operator for `.` (see Repeat): `fmt` is a
" call, with a %d for the count when the action takes one.
function! songwriter#tab#operator#Record(fmt, count) abort
  let b:songwriter_repeat = {'fmt': a:fmt, 'count': a:count, 'tick': b:changedtick}
endfunction

" Spec 6.13: `>>` (dir +1) / `<<` (dir -1), `count` times.
function! songwriter#tab#operator#Shift(dir, count) abort
  let l:block = songwriter#tab#edit#LintAndFollow(songwriter#tab#model#Read())
  if empty(l:block)
    return
  endif
  let l:done = 0
  for l:i in range(max([a:count, 1]))
    let l:res = songwriter#tab#columns#ShiftColumn(l:block.lines, line('.') - l:block.start, col('.'), a:dir)
    if empty(l:res)
      break
    endif
    let l:block = songwriter#tab#edit#Commit(l:block, l:res)
    let l:done = 1
  endfor
  if l:done
    call songwriter#tab#operator#Record('songwriter#tab#operator#Shift(' . a:dir . ', %d)', a:count)
  endif
endfunction

" Spec 6.14: `gp`, overlay a column register onto the cursor's column.
function! songwriter#tab#operator#Overlay(reg) abort
  call songwriter#tab#edit#Run(function('s:overlay', [a:reg]))
endfunction

function! s:overlay(reg, ctx) abort
  let l:rows = getreg(a:reg, 1, 1)
  if getregtype(a:reg)[0] !=# "\<C-V>" || empty(l:rows)
    return {'error': 'songwriter: gp pastes a column register'}
  endif
  return songwriter#tab#columns#Overlay(a:ctx.block.lines, a:ctx.lin, a:ctx.col,
        \ l:rows, songwriter#tab#operator#RegisterNames(a:reg))
endfunction

" === Visual mode (spec 6.9) ===

" The last selection made by VisualObject: while it is still the current one,
" the selection is exact (no snapping) and the same object extends it.
let s:vobj = {}

function! s:selection() abort
  return [line('v'), col('v'), line('.'), col('.')]
endfunction

function! s:is_vobj() abort
  return !empty(s:vobj) && mode() ==# get(s:vobj, 'mode', "\<C-V>") && s:selection() ==# s:vobj.sel
endfunction

" Spec 6.9.6: `in`/`an` in visual mode select the note on its string.
function! songwriter#tab#operator#VisualNoteObject(around) abort
  let l:range = s:note_range(a:around)
  if empty(l:range)
    return
  endif
  execute "normal! \<Esc>"
  call cursor(line('.'), l:range[0])
  normal! v
  call cursor(line('.'), l:range[1])
  let s:vobj = {'kind': 'n', 'mode': 'v', 'sel': [line('.'), l:range[0], line('.'), l:range[1]]}
endfunction

" Spec 6.9.1: select the object as a blockwise rectangle over every string,
" cursor on the bottom string. Again on our own selection: one more column /
" bar, counted from where the first one started.
function! songwriter#tab#operator#VisualObject(kind, around) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  if s:is_vobj() && s:vobj.kind ==# a:kind && s:vobj.around == a:around
    let l:o = s:vobj
    let l:o.count += 1
  else
    let l:o = {'kind': a:kind, 'around': a:around, 'count': v:count1,
          \ 'lin': line('.') - l:block.start, 'col': col('.')}
  endif
  let l:range = a:kind ==# 'c'
        \ ? songwriter#tab#columns#ColumnObject(l:block.lines, l:o.lin, l:o.col, l:o.count, a:around)
        \ : songwriter#tab#columns#BarObject(l:block.lines, l:o.lin, l:o.col, l:o.count, a:around)
  if empty(l:range)
    return
  endif
  let l:last = l:block.start + len(l:block.lines) - 1
  execute "normal! \<Esc>"
  call cursor(l:block.start, l:range[0])
  execute "normal! \<C-V>"
  call cursor(l:last, l:range[1])
  let l:o.sel = [l:block.start, l:range[0], l:last, l:range[1]]
  let s:vobj = l:o
endfunction

" Spec 6.9.3: `V` starts a blockwise selection of the cursor's column over
" every string of the tab, cursor on the bottom string. Motions then extend it
" by columns; an operator snaps it as in 6.9.2.
function! songwriter#tab#operator#VisualColumn() abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:col = col('.')
  call cursor(l:block.start, l:col)
  execute "normal! \<C-V>"
  call cursor(l:block.start + len(l:block.lines) - 1, l:col)
endfunction

" Spec 6.9.3: in a character-wise or blockwise selection, `j`/`k` stop at the
" tab's top and bottom strings (a count is clamped), so the selection never
" leaves the tab. Line-wise (`VV`), they are native.
function! songwriter#tab#operator#VisualVertical(key) abort
  let l:block = songwriter#tab#model#Read()
  if mode() ==# 'V' || empty(l:block)
    return a:key
  endif
  let l:edge = a:key ==# 'j' ? l:block.start + len(l:block.lines) - 1 : l:block.start
  let l:target = line('.') + (a:key ==# 'j' ? v:count1 : -v:count1)
  if a:key ==# 'j' ? l:target <= l:edge : l:target >= l:edge
    return a:key
  endif
  return printf("\<Cmd>call cursor(%d, %d)\<CR>", l:edge, col('.'))
endfunction

" Spec 6.9.5: tablature-mode motions in visual mode, without side effects:
" `w`/`b` to the next/previous note of the string, `l`/`h` to the next/previous
" note column of the block.
function! songwriter#tab#operator#VisualMotion(key) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:stops = a:key =~# '[wb]'
        \ ? map(songwriter#tab#columns#Atoms(getline('.')), 'v:val.col')
        \ : songwriter#tab#columns#Columns(l:block.lines)
  let l:col = col('.')
  for l:i in range(v:count1)
    let l:c = filter(copy(l:stops), a:key =~# '[wl]' ? 'v:val > l:col' : 'v:val < l:col')
    if empty(l:c)
      break
    endif
    let l:col = a:key =~# '[wl]' ? l:c[0] : l:c[-1]
  endfor
  call cursor(line('.'), l:col)
endfunction

" The current selection as [lnum, s, e, exact] for a column operation (lnum:
" a line of the block), or [l1, l2] in line-wise visual mode. Leaves visual.
function! s:take_selection() abort
  let l:mode = mode()
  let [l:l1, l:c1, l:l2, l:c2] = s:selection()
  let l:exact = s:is_vobj()
  let l:note = l:exact && s:vobj.kind ==# 'n'
  let s:vobj = {}
  execute "normal! \<Esc>"
  if l:mode ==# 'V'
    return [min([l:l1, l:l2]), max([l:l1, l:l2])]
  endif
  return [l:l2, min([l:c1, l:c2]), max([l:c1, l:c2]), l:exact, l:note]
endfunction

" Spec 6.9.2 / 6.9.3: d, y, c (and x as d) on a selection: widened to every
" string, snapped unless it is one of our objects; a line-wise selection
" (`VV`) covers whole tabs.
function! songwriter#tab#operator#VisualOp(op, reg) abort
  let l:sel = s:take_selection()
  if len(l:sel) == 2
    call s:linewise(a:op, a:reg, l:sel[0], l:sel[1])
    return
  endif
  let [l:lnum, l:s, l:e, l:exact, l:note] = l:sel
  let l:block = songwriter#tab#model#Read(l:lnum)
  if empty(l:block)
    return
  endif
  if !l:exact
    let [l:s, l:e] = songwriter#tab#columns#Snap(l:block.lines, l:lnum - l:block.start, l:s, l:e)
  endif
  call cursor(l:lnum, l:s)
  if l:note
    call s:noteop(a:op, a:reg, l:block, l:s, l:e)
  else
    call s:columnwise(a:op, a:reg, l:block, l:s, l:e)
  endif
endfunction

" Spec 6.9.4: replace the selected columns with a blockwise register (rows
" matched as for p), or the selected tabs (`VV`) with a line-wise register.
function! songwriter#tab#operator#VisualPut(reg) abort
  let l:type = getregtype(a:reg)
  let l:rows = getreg(a:reg, 1, 1)
  let l:names = songwriter#tab#operator#RegisterNames(a:reg)
  let l:sel = s:take_selection()
  if len(l:sel) == 2
    if l:type !=# 'V'
      return songwriter#tab#edit#Error('songwriter: only a line-wise register can replace whole tabs')
    endif
    call s:linewise('d', '_', l:sel[0], l:sel[1])
    call append(line('.') - (line('.') >= l:sel[0] ? 1 : 0), l:rows)
    return
  endif
  if l:type[0] !=# "\<C-V>" || empty(l:rows)
    return songwriter#tab#edit#Error('songwriter: cannot paste a character-wise register into a tab')
  endif
  let [l:lnum, l:s, l:e, l:exact, l:note] = l:sel
  let l:block = songwriter#tab#model#Read(l:lnum)
  if empty(l:block)
    return
  endif
  if !l:exact || l:note
    let [l:s, l:e] = songwriter#tab#columns#Snap(l:block.lines, l:lnum - l:block.start, l:s, l:e)
  endif
  let l:lines = songwriter#tab#columns#DeleteRange(l:block.lines, l:s, l:e).lines
  let l:res = songwriter#tab#columns#PasteAt(l:lines, l:s - 1, l:rows, l:names)
  let l:res.lin = l:lnum - l:block.start
  call songwriter#tab#edit#Commit(l:block, l:res)
endfunction

" === Repeat (spec 6.10) ===

" `.` in tablature mode. Operators repeat natively (g@ records itself; note
" that this includes a yank, which native `y` does not). Actions that are not
" operators (x, X, p, P) record themselves in b:songwriter_repeat with the
" changedtick they left; while the buffer is unchanged since, `.` runs that
" action again, with the new count if one is given.
function! songwriter#tab#operator#Repeat() abort
  let l:r = get(b:, 'songwriter_repeat', {})
  if !empty(l:r) && l:r.tick == b:changedtick
    let l:call = l:r.fmt =~# '%d' ? printf(l:r.fmt, v:count ? v:count : l:r.count) : l:r.fmt
    return printf("\<Cmd>call %s\<CR>", l:call)
  endif
  return '.'
endfunction
