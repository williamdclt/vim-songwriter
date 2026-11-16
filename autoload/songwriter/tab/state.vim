" autoload/songwriter/tab/state.vim - the buffer's named states, and how long
" each holds.
"
" A state is a value recorded under a name for the keys that follow (the open
" slot, the action `.` repeats, the insert state...). How long it holds is
" declared once per name in s:lifetimes; Get returns it only while it holds,
" so no reader writes the rule out again. Values are stored as
" b:songwriter_{name} with the b:changedtick they were set at.
"
" The states kept elsewhere are those Vim forces elsewhere: the pending
" operator (tab/operator.vim: 'operatorfunc' takes no arguments) and the
" string names of a register (tab/register.vim: registers are global).

" The lifetime of each state:
"   change        until the buffer changes;
"   continuation  straight after an action: the buffer unchanged and the
"                 cursor where the action left it (the value's 'line' and
"                 'col', which edit#Do records with every state);
"   on-note       while the cursor is on a note of a tab line, in tablature
"                 mode (OnNote), edits included;
"   selection     while visual mode and the selection are the ones recorded
"                 (the value's 'mode' and 'sel', [l1, c1, l2, c2]), edits
"                 included;
"   read-once     until read: Get takes it.
let s:lifetimes = {
      \ 'slot': 'change',
      \ 'insert': 'change',
      \ 'repeat': 'change',
      \ 'upward': 'change',
      \ 'typing': 'continuation',
      \ 'carry': 'continuation',
      \ 'voicing': 'continuation',
      \ 'naming': 'continuation',
      \ 'move': 'on-note',
      \ 'vobj': 'selection',
      \ 'annotating': 'read-once',
      \ }

function! s:lifetime(name) abort
  if !has_key(s:lifetimes, a:name)
    throw 'songwriter: no lifetime for state ' . a:name
  endif
  return s:lifetimes[a:name]
endfunction

" Record `value` (a dict) under `name`.
function! songwriter#tab#state#Set(name, value) abort
  call s:lifetime(a:name)
  let b:songwriter_{a:name} = extend(copy(a:value), {'tick': b:changedtick})
endfunction

" The value recorded under `name` while it holds, else {}. A 'read-once'
" state is taken.
function! songwriter#tab#state#Get(name) abort
  let l:lifetime = s:lifetime(a:name)
  let l:value = get(b:, 'songwriter_' . a:name, {})
  if empty(l:value) || !s:holds(l:lifetime, l:value)
    return {}
  endif
  if l:lifetime ==# 'read-once'
    call songwriter#tab#state#Clear(a:name)
  endif
  return l:value
endfunction

function! songwriter#tab#state#Clear(name) abort
  unlet! b:songwriter_{a:name}
endfunction

" Drop the value recorded under `name` when it no longer holds. Returns 1 when
" it did, so the caller can show the state has ended.
function! songwriter#tab#state#Expire(name) abort
  let l:value = get(b:, 'songwriter_' . a:name, {})
  if empty(l:value) || s:holds(s:lifetime(a:name), l:value)
    return 0
  endif
  call songwriter#tab#state#Clear(a:name)
  return 1
endfunction

" Whether the cursor is on a note of a tab line, in tablature mode: where an
" 'on-note' state holds, and where the move state can be entered.
function! songwriter#tab#state#OnNote() abort
  return songwriter#keys#InTabMode() && songwriter#grammar#IsTabLine(getline('.'))
        \ && !empty(songwriter#tab#model#NoteAt(getline('.'), col('.')))
endfunction

" Whether `value`, recorded with its tick, still holds under `lifetime`.
function! s:holds(lifetime, value) abort
  if a:lifetime ==# 'change'
    return a:value.tick == b:changedtick
  elseif a:lifetime ==# 'continuation'
    return a:value.tick == b:changedtick && get(a:value, 'line', 0) == line('.')
          \ && get(a:value, 'col', 0) == col('.')
  elseif a:lifetime ==# 'on-note'
    return songwriter#tab#state#OnNote()
  elseif a:lifetime ==# 'selection'
    return mode() ==# a:value.mode && [line('v'), col('v'), line('.'), col('.')] ==# a:value.sel
  endif
  return a:lifetime ==# 'read-once'
endfunction
