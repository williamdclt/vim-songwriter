" autoload/songwriter/tab/mode.vim - the states of tablature mode (spec
" [Tablature][[Editing]] 3, 3.1.4-3.1.6, 3.8), its modes.
"
" Tablature mode is in one of three states, which the user sees (a message,
" Status() for a status line) and enters and leaves explicitly; keys.vim picks
" its key tables from the current one:
"   normal  moving never changes the file;
"   insert  moving across notes opens slots for new ones (3.1). It holds while
"           the buffer is unchanged: the edits made in it record it again
"           (Keep), and any other change ends it without the other code
"           having to know about it. Leaving it closes the open slot (4.3).
"   move    keys act on the note under the cursor (3.8). It holds while the
"           cursor is on a note of a tab line, edits included.
" The insert and move states are recorded in tab/state.vim, under their names,
" which declares how long each holds; Current() says which one does.
" Continuations, valid only straight after an action (the carry run, the digit
" being typed...), are not states of the mode, though tab/state.vim keeps them
" too.

" The message each state shows when entered, and its name for a status line.
let s:modes = {
      \ 'normal': {'msg': '', 'status': ''},
      \ 'insert': {'msg': '-- TAB INSERT --', 'status': 'TAB INSERT'},
      \ 'move': {'msg': '-- TAB MOVE --', 'status': 'TAB MOVE'},
      \ }

" The current state: 'normal', 'insert' or 'move'.
function! songwriter#tab#mode#Current() abort
  for l:name in ['insert', 'move']
    if !empty(songwriter#tab#state#Get(l:name))
      return l:name
    endif
  endfor
  return 'normal'
endfunction

" Record state `name` ('normal' for none), the other states dropped.
function! s:record(name) abort
  for l:name in ['insert', 'move']
    if l:name ==# a:name
      call songwriter#tab#state#Set(l:name, {})
    else
      call songwriter#tab#state#Clear(l:name)
    endif
  endfor
endfunction

" Enter state `name`, leaving the current one first (leaving the insert state
" closes its slot, 4.3), and show it (its message, and the color of 3.8.5). Entering the insert state while in it
" records it at the buffer's current version, as Keep.
function! songwriter#tab#mode#Enter(name) abort
  let l:from = songwriter#tab#mode#Current()
  if l:from ==# 'insert'
    call songwriter#tab#slots#Abandon()
  endif
  call s:record(a:name)
  if l:from !=# a:name
    call songwriter#tab#highlight#Update()
    call songwriter#tab#mode#Show(s:modes[a:name].msg)
  endif
endfunction

" Record the insert state at the buffer's current version, after an edit made
" in it.
function! songwriter#tab#mode#Keep() abort
  call s:record('insert')
endfunction

" Spec 3.1.6, 3.8: the state for a status line: 'TAB INSERT', 'TAB MOVE', or ''
" in the normal state.
function! songwriter#tab#mode#Status() abort
  return s:modes[songwriter#tab#mode#Current()].status
endfunction

" Spec 3.8: the keys for `m` in tablature mode: on a note, enter the move
" state; elsewhere, Vim's own `m`.
function! songwriter#tab#mode#MoveKey() abort
  return songwriter#tab#state#OnNote() ? "\<Cmd>call songwriter#tab#mode#Enter('move')\<CR>" : 'm'
endfunction

" Spec 3.8.4: the move state ends once the cursor has left the notes (run when
" the cursor moves or the text changes): its message goes.
function! songwriter#tab#mode#Check() abort
  if songwriter#tab#state#Expire('move')
    call songwriter#tab#mode#Show(s:modes.normal.msg)
  endif
endfunction

" Show `msg` in place of the previous message, as Vim's own mode message, so
" that repeated changes of state never pile up into a hit-enter prompt.
function! songwriter#tab#mode#Show(msg) abort
  redraw
  echo a:msg
endfunction
