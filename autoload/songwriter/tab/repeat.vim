" autoload/songwriter/tab/repeat.vim - `.` in tablature mode (spec
" [Tablature][[Editing]] 6.10), for actions that are not operators.

" Remember an action that is not an operator for `.` (see Repeat): `fmt` is a
" call, with a %d for the count when the action takes one.
function! songwriter#tab#repeat#Record(fmt, count) abort
  call songwriter#tab#state#Set('repeat', {'fmt': a:fmt, 'count': a:count})
endfunction

" `.` in tablature mode. Operators repeat natively (g@ records itself; note
" that this includes a yank, which native `y` does not). Actions that are not
" operators (x, p, P, >>, <<, the string moves) record themselves in b:songwriter_repeat with the
" changedtick they left; while the buffer is unchanged since, `.` runs that
" action again, with the new count if one is given.
function! songwriter#tab#repeat#Repeat() abort
  let l:r = songwriter#tab#state#Get('repeat')
  if !empty(l:r)
    let l:call = l:r.fmt =~# '%d' ? printf(l:r.fmt, v:count ? v:count : l:r.count) : l:r.fmt
    return printf("\<Cmd>call %s\<CR>", l:call)
  endif
  return '.'
endfunction
