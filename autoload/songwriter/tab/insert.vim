" autoload/songwriter/tab/insert.vim - the insert state of tablature mode
" (spec [Tablature][[Editing]] 3, 3.1.4-3.1.6).
"
" Tablature mode has a normal state, where moving never changes the file, and
" an insert state, where moving across notes opens slots for new ones. The
" insert state is kept in tab/state.vim, so it holds only while the buffer is
" unchanged: the edits that keep it (opening, filling or closing a slot) record
" it again with Keep(), and any other change ends it.

function! songwriter#tab#insert#Active() abort
  return !empty(songwriter#tab#state#Get('insert'))
endfunction

" Enter the insert state (or stay in it), showing it when it was not active.
function! songwriter#tab#insert#Enter() abort
  let l:was = songwriter#tab#insert#Active()
  call songwriter#tab#insert#Keep()
  if !l:was
    call songwriter#tab#insert#Show('-- TAB INSERT --')
  endif
endfunction

" Record the insert state at the buffer's current version, after an edit made
" in it.
function! songwriter#tab#insert#Keep() abort
  call songwriter#tab#state#Set('insert', {})
endfunction

function! songwriter#tab#insert#Leave() abort
  if songwriter#tab#insert#Active()
    call songwriter#tab#insert#Show('')
  endif
  call songwriter#tab#state#Clear('insert')
endfunction

" Spec 3.1.5: `<Esc>` closes the open slot (4.3) and leaves the insert state.
function! songwriter#tab#insert#Escape() abort
  call songwriter#tab#slots#Abandon()
  call songwriter#tab#insert#Leave()
endfunction

" Show `msg` in place of the previous message, as Vim's own mode message, so
" that repeated changes of state never pile up into a hit-enter prompt.
function! songwriter#tab#insert#Show(msg) abort
  redraw
  echo a:msg
endfunction
