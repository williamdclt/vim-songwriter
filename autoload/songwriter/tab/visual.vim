" autoload/songwriter/tab/visual.vim - tablature-mode visual mode (spec
" [Tablature][[Editing]] 6.9): selections, their motions, and the operators on
" them (tab/operator.vim).

" The last selection made by VisualObject: while it is still the current one,
" the selection is exact (no snapping) and the same object extends it.
let s:vobj = {}

function! s:selection() abort
  return [line('v'), col('v'), line('.'), col('.')]
endfunction

" Replace the selection by one in visual mode `vmode` from (l1, c1) to (l2, c2).
function! s:select(vmode, l1, c1, l2, c2) abort
  execute "normal! \<Esc>"
  call cursor(a:l1, a:c1)
  execute 'normal! ' . a:vmode
  call cursor(a:l2, a:c2)
endfunction

function! s:is_vobj() abort
  return !empty(s:vobj) && mode() ==# get(s:vobj, 'mode', "\<C-V>") && s:selection() ==# s:vobj.sel
endfunction

" Spec 6.9.6: `in`/`an` in visual mode select the note on its string.
function! songwriter#tab#visual#NoteObject(around) abort
  let l:c = songwriter#tab#model#Cursor()
  if empty(l:c)
    return
  endif
  let l:range = songwriter#tab#columns#NoteObject(l:c.block.lines, l:c.lin, l:c.col, a:around)
  if empty(l:range)
    return
  endif
  let l:lnum = line('.')
  call s:select('v', l:lnum, l:range[0], l:lnum, l:range[1])
  let s:vobj = {'kind': 'n', 'mode': 'v', 'sel': [l:lnum, l:range[0], l:lnum, l:range[1]]}
endfunction

" Spec 6.9.1: select the object as a blockwise rectangle over every string,
" cursor on the bottom string. Again on our own selection: one more column /
" bar, counted from where the first one started.
function! songwriter#tab#visual#Object(kind, around) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  if s:is_vobj() && s:vobj.kind ==# a:kind && s:vobj.around == a:around
    let l:o = s:vobj
    let l:o.count += 1
  else
    let l:o = {'kind': a:kind, 'around': a:around, 'count': v:count1,
          \ 'lin': songwriter#tab#model#CursorLin(l:block), 'col': col('.')}
  endif
  let l:range = songwriter#tab#columns#Object(a:kind, l:block.lines, l:o.lin, l:o.col, l:o.count, a:around)
  if empty(l:range)
    return
  endif
  let l:last = l:block.end
  call s:select("\<C-V>", l:block.start, l:range[0], l:last, l:range[1])
  let l:o.sel = [l:block.start, l:range[0], l:last, l:range[1]]
  let s:vobj = l:o
endfunction

" Spec 6.9.3: `V` starts a blockwise selection of the cursor's column over
" every string of the tab, cursor on the bottom string. Motions then extend it
" by columns; an operator snaps it as in 6.9.2.
function! songwriter#tab#visual#Column() abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:col = col('.')
  call cursor(l:block.start, l:col)
  execute "normal! \<C-V>"
  call cursor(l:block.end, l:col)
endfunction

" Spec 6.9.3: in a character-wise or blockwise selection, `j`/`k` stop at the
" tab's top and bottom strings (a count is clamped), so the selection never
" leaves the tab. Line-wise (`VV`), they are native.
function! songwriter#tab#visual#Vertical(key) abort
  let l:block = songwriter#tab#model#Read()
  if mode() ==# 'V' || empty(l:block)
    return a:key
  endif
  let l:edge = a:key ==# 'j' ? l:block.end : l:block.start
  let l:target = line('.') + (a:key ==# 'j' ? v:count1 : -v:count1)
  if a:key ==# 'j' ? l:target <= l:edge : l:target >= l:edge
    return a:key
  endif
  return printf("\<Cmd>call cursor(%d, %d)\<CR>", l:edge, col('.'))
endfunction

" Spec 6.9.5: tablature-mode motions in visual mode, without side effects:
" `w`/`b` to the next/previous note of the string, `l`/`h` to the next/previous
" note column of the block.
function! songwriter#tab#visual#Motion(key) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:stops = songwriter#tab#columns#Stops(l:block.lines, getline('.'), a:key)
  let l:col = songwriter#tab#model#Advance(l:stops, col('.'), a:key =~# '[wl]' ? 1 : -1, v:count1)
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
function! songwriter#tab#visual#Op(op, reg) abort
  let l:sel = s:take_selection()
  if len(l:sel) == 2
    call songwriter#tab#operator#ApplyLines(a:op, a:reg, l:sel[0], l:sel[1])
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
  call songwriter#tab#operator#ApplyRange(a:op, a:reg, l:block, l:s, l:e, l:note)
endfunction

" Spec 6.9.4: replace the selected columns with a blockwise register (rows
" matched as for p), or the selected tabs (`VV`) with a line-wise register.
function! songwriter#tab#visual#Put(reg) abort
  let l:type = getregtype(a:reg)
  let l:rows = getreg(a:reg, 1, 1)
  let l:names = songwriter#tab#register#Names(a:reg)
  let l:sel = s:take_selection()
  if len(l:sel) == 2
    if l:type !=# 'V'
      return songwriter#tab#edit#Error('songwriter: only a line-wise register can replace whole tabs')
    endif
    call songwriter#tab#operator#ApplyLines('d', '_', l:sel[0], l:sel[1])
    call append(line('.') - (line('.') >= l:sel[0] ? 1 : 0), l:rows)
    return
  endif
  if empty(songwriter#tab#register#BlockRows(a:reg))
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
