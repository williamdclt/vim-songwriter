" autoload/songwriter/tab/state.vim - buffer state tied to one buffer version.
"
" The open slot, the digit being typed and the action `.` repeats each hold
" only while the buffer is unchanged since they were recorded. They are stored
" as b:songwriter_{name} with the b:changedtick they were set at.

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
