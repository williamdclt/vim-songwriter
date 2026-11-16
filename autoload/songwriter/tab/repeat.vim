" autoload/songwriter/tab/repeat.vim - `.` in tablature mode (spec
" [Tablature][[Editing]] 6.10), for actions that are not operators.

" Remember an action that is not an operator for `.` (see Repeat): `Fn`
" called with `args`; `count` (optional) is the index of the argument a count
" given to `.` replaces.
function! songwriter#tab#repeat#Record(Fn, args, ...) abort
  call songwriter#tab#state#Set('repeat', {'fn': a:Fn, 'args': a:args, 'count': a:0 ? a:1 : -1})
endfunction

" `.` in tablature mode. Operators repeat natively (g@ records itself; note
" that this includes a yank, which native `y` does not). Actions that are not
" operators (x, p, P, >>, <<, the string moves) record themselves (Record)
" with the changedtick they left; while the buffer is unchanged since, `.`
" runs that action again (Run), with the new count if one is given.
function! songwriter#tab#repeat#Repeat() abort
  if empty(songwriter#tab#state#Get('repeat'))
    return '.'
  endif
  return printf("\<Cmd>call songwriter#tab#repeat#Run(%d)\<CR>", v:count)
endfunction

" Run the action recorded for `.`, `count` (when not 0) replacing the
" argument it stands for.
function! songwriter#tab#repeat#Run(count) abort
  let l:r = songwriter#tab#state#Get('repeat')
  if empty(l:r)
    return
  endif
  let l:args = copy(l:r.args)
  if a:count && l:r.count >= 0
    let l:args[l:r.count] = a:count
  endif
  call call(l:r.fn, l:args)
endfunction
