" autoload/songwriter/tab/chordname.vim - naming the chord on a time column
" (spec [Tablature][[Editing]] 13), and writing it as the column's chord label
" (10.10). Names() and Message() are pure (block lines in); Show(), `<leader>?`,
" and Name() / NextName(), `=<CR>` / `==`, are the entry points.

" Spec 13.1, 13.4: the chords on the time column at column `col` of line `lin`
" (0-indexed) of `lines`: {'names', 'col' (the column)}; {'msg'} when its
" notes are one note or fit no chord; {'error'} when it has no fretted note or
" a string name is not a note.
function! songwriter#tab#chordname#Names(lines, lin, col) abort
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
    return {'names': l:names, 'col': l:c}
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

" Spec 13: the message `<leader>?` shows for the time column at column `col`
" of line `lin` of `lines`: {'msg'}, or {'error'}.
function! songwriter#tab#chordname#Message(lines, lin, col) abort
  let l:r = songwriter#tab#chordname#Names(a:lines, a:lin, a:col)
  return has_key(l:r, 'names') ? {'msg': join(l:r.names, ' | ')} : l:r
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

" Spec 10.10: `=<CR>` on a string, write the first name of the chord on the
" cursor's time column as its chord label, without changing the notes.
function! songwriter#tab#chordname#Name() abort
  call songwriter#tab#edit#Do(function('s:label', [0]), {'prelint': 0, 'lint': 0})
endfunction

" Spec 10.10: `==` after `=<CR>`, the next name, in the same undo step.
function! songwriter#tab#chordname#NextName() abort
  let l:last = songwriter#tab#state#Get('naming')
  call songwriter#tab#edit#Do(function('s:label', [l:last.index + 1]),
        \ {'prelint': 0, 'lint': 0, 'join': 1})
endfunction

" True straight after `=<CR>` or `==` wrote a name, the cursor where it was.
function! songwriter#tab#chordname#Naming() abort
  let l:last = songwriter#tab#state#Get('naming')
  return !empty(l:last) && l:last.line == line('.') && l:last.col == col('.')
endfunction

" The edit writing name `index` (wrapping around) of the chord on the cursor's
" column as its chord label (edit#Do).
function! s:label(index, ctx) abort
  let l:r = songwriter#tab#chordname#Names(a:ctx.block.lines, a:ctx.lin, a:ctx.col)
  if !has_key(l:r, 'names')
    return {'error': get(l:r, 'error', get(l:r, 'msg', ''))}
  endif
  let l:i = a:index % len(l:r.names)
  let l:shown = copy(l:r.names)
  let l:shown[l:i] = '[' . l:shown[l:i] . ']'
  return {'lines': a:ctx.block.lines, 'map': [],
        \ 'label': {'col': l:r.col, 'text': l:r.names[l:i], 'add': 1},
        \ 'msg': join(l:shown, ' | '), 'state': {'naming': {'index': l:i}}}
endfunction
