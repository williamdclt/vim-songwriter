" autoload/songwriter/tab/state.vim - buffer state tied to one buffer version.
"
" The open slot, the insert state, the digit being typed, the notes being
" carried and the action `.` repeats each hold only while the buffer is
" unchanged since they were recorded. They are stored as b:songwriter_{name}
" with the b:changedtick they were set at.
"
" A continuation (Continuing) also needs the cursor where the last step left
" it: the carry run, the digit being typed, `==` cycling voicings or names.
" Its value records the cursor as 'line' and 'col' (edit#Do adds them to every
" state an edit records).

function! songwriter#tab#state#Set(name, value) abort
  let b:songwriter_{a:name} = extend(copy(a:value), {'tick': b:changedtick})
endfunction

" The value recorded under `name`, or {} when none or the buffer has changed.
function! songwriter#tab#state#Get(name) abort
  let l:value = get(b:, 'songwriter_' . a:name, {})
  return !empty(l:value) && l:value.tick == b:changedtick ? l:value : {}
endfunction

function! songwriter#tab#state#Clear(name) abort
  unlet! b:songwriter_{a:name}
endfunction

" The value recorded under `name` when the buffer is unchanged since and the
" cursor is where it was recorded ('line', 'col'), else {}: what a feature
" carries on from when its key is pressed again straight after it.
function! songwriter#tab#state#Continuing(name) abort
  let l:value = songwriter#tab#state#Get(a:name)
  return !empty(l:value) && get(l:value, 'line', 0) == line('.')
        \ && get(l:value, 'col', 0) == col('.') ? l:value : {}
endfunction
