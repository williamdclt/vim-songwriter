" autoload/songwriter/tab/chordname.vim - naming the chord on a time column
" (spec [Tablature][[Editing]] 13). Message() is pure (block lines in, the
" message out); Show() is the entry point, `<leader>?`.

" Spec 13.1, 13.4: the message naming the chord on the time column at column
" `col` of line `lin` (0-indexed) of `lines`: {'msg'}, or {'error'}.
function! songwriter#tab#chordname#Message(lines, lin, col) abort
  let l:open = songwriter#tab#play#OpenPitches(songwriter#tab#model#Names(a:lines))
  if has_key(l:open, 'error')
    return l:open
  endif
  let l:note = songwriter#tab#model#NoteAt(a:lines[a:lin], a:col)
  let l:c = empty(l:note) ? a:col : l:note.col
  let l:steps = songwriter#tab#play#Steps(a:lines, l:open.midi, range(len(a:lines)), l:c, l:c)
  if empty(l:steps)
    return {'error': 'songwriter: no note on this time column'}
  endif
  let l:midis = sort(map(copy(l:steps[0]), 'v:val.midi'), 'n')
  let l:names = songwriter#chord#Identify(l:midis)
  if !empty(l:names)
    return {'msg': join(l:names, ' | ')}
  endif
  let l:pcs = []
  for l:m in l:midis
    if index(l:pcs, l:m % 12) < 0
      call add(l:pcs, l:m % 12)
    endif
  endfor
  let l:spelled = join(map(l:pcs, 'songwriter#pitch#Name(v:val)'))
  return {'msg': (len(l:pcs) == 1 ? 'songwriter: one note, ' : 'songwriter: no chord for ') . l:spelled}
endfunction

" Spec 13: `<leader>?`, echo the chord on the cursor's time column. Off a tab
" line it does nothing.
function! songwriter#tab#chordname#Show() abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:r = songwriter#tab#chordname#Message(l:block.lines,
        \ songwriter#tab#model#CursorLin(l:block), col('.'))
  if has_key(l:r, 'error')
    call songwriter#tab#edit#Error(l:r.error)
  else
    echo l:r.msg
  endif
endfunction
