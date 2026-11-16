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
" The state is b:songwriter_mode, {'name', 'tick'}; Current() says which one
" holds. Continuations, valid only straight after an action (the carry run,
" the digit being typed...), are not states: see state#Continuing.

" The message each state shows when entered, and its name for a status line.
let s:modes = {
      \ 'normal': {'msg': '', 'status': ''},
      \ 'insert': {'msg': '-- TAB INSERT --', 'status': 'TAB INSERT'},
      \ 'move': {'msg': '-- TAB MOVE --', 'status': 'TAB MOVE'},
      \ }

" The current state: 'normal', 'insert' or 'move'.
function! songwriter#tab#mode#Current() abort
  let l:name = get(get(b:, 'songwriter_mode', {}), 'name', 'normal')
  if l:name ==# 'insert'
    return b:songwriter_mode.tick == b:changedtick ? 'insert' : 'normal'
  elseif l:name ==# 'move'
    return s:on_note() ? 'move' : 'normal'
  endif
  return 'normal'
endfunction

" Whether the cursor is on a note of a tab line, in tablature mode: where the
" move state holds.
function! s:on_note() abort
  return songwriter#keys#InTabMode() && songwriter#grammar#IsTabLine(getline('.'))
        \ && !empty(songwriter#tab#model#NoteAt(getline('.'), col('.')))
endfunction

" Enter state `name`, leaving the current one first (leaving the insert state
" closes its slot, 4.3), and show it (its message, and the highlight of 3.8.5). Entering the insert state while in it
" records it at the buffer's current version, as Keep.
function! songwriter#tab#mode#Enter(name) abort
  let l:from = songwriter#tab#mode#Current()
  if l:from ==# 'insert'
    call songwriter#tab#slots#Abandon()
  endif
  if a:name ==# 'normal'
    unlet! b:songwriter_mode
  else
    let b:songwriter_mode = {'name': a:name, 'tick': b:changedtick}
  endif
  if l:from !=# a:name
    call songwriter#tab#highlight#Update()
    call songwriter#tab#mode#Show(s:modes[a:name].msg)
  endif
endfunction

" Record the insert state at the buffer's current version, after an edit made
" in it.
function! songwriter#tab#mode#Keep() abort
  let b:songwriter_mode = {'name': 'insert', 'tick': b:changedtick}
endfunction

" Spec 3.1.6, 3.8: the state for a status line: 'TAB INSERT', 'TAB MOVE', or ''
" in the normal state.
function! songwriter#tab#mode#Status() abort
  return s:modes[songwriter#tab#mode#Current()].status
endfunction

" Spec 3.8: the keys for `m` in tablature mode: on a note, enter the move
" state; elsewhere, Vim's own `m`.
function! songwriter#tab#mode#MoveKey() abort
  return s:on_note() ? "\<Cmd>call songwriter#tab#mode#Enter('move')\<CR>" : 'm'
endfunction

" Spec 3.8.4: the move state ends once the cursor has left the notes (run when
" the cursor moves or the text changes): its message goes.
function! songwriter#tab#mode#Check() abort
  if get(get(b:, 'songwriter_mode', {}), 'name', '') ==# 'move' && !s:on_note()
    unlet b:songwriter_mode
    call songwriter#tab#mode#Show(s:modes.normal.msg)
  endif
endfunction

" Show `msg` in place of the previous message, as Vim's own mode message, so
" that repeated changes of state never pile up into a hit-enter prompt.
function! songwriter#tab#mode#Show(msg) abort
  redraw
  echo a:msg
endfunction
