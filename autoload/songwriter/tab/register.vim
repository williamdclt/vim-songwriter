" autoload/songwriter/tab/register.vim - tab registers (spec [Tablature][[Editing]]
" 6.4): plain Vim registers, with the string names of their source tab
" remembered alongside while the register still holds what was written.

" Set register `reg` and remember the string names of its source tab, so a
" paste can match strings by name (6.5.3) while the register is unchanged.
function! songwriter#tab#register#Set(reg, rows, type, names) abort
  call setreg(a:reg, a:rows, a:type)
  if !exists('g:songwriter_register_names')
    let g:songwriter_register_names = {}
  endif
  let g:songwriter_register_names[a:reg] = {'names': a:names, 'rows': getreg(a:reg, 1, 1)}
endfunction

" The string names recorded for register `reg`, or [] when unknown or stale.
function! songwriter#tab#register#Names(reg) abort
  let l:r = get(get(g:, 'songwriter_register_names', {}), a:reg, {})
  return !empty(l:r) && l:r.rows ==# getreg(a:reg, 1, 1) ? l:r.names : []
endfunction

" The rows of register `reg` when it is a non-empty blockwise one, else [].
function! songwriter#tab#register#BlockRows(reg) abort
  return getregtype(a:reg)[0] ==# "\<C-V>" ? getreg(a:reg, 1, 1) : []
endfunction
