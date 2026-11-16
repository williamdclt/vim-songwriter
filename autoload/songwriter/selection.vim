" autoload/songwriter/selection.vim - the visual selection, for the actions
" run from visual mode with a <Cmd> map that change the text and keep the
" selection (visual <Ctrl-A>/<Ctrl-X>, visual <leader>k/<leader>j).

" A column past the end of any line: the right edge of a selection extended to
" the end of every line (`$`).
let s:eol = 2147483647

" The current selection, read in visual mode: {'mode', 'anchor' (getpos('v')),
" 'cursor' (getcurpos(), whose curswant sets a blockwise selection's right
" edge), 'to_eol' (a blockwise selection extended to the end of every line)}.
function! songwriter#selection#Get() abort
  return {'mode': mode(), 'anchor': getpos('v'), 'cursor': getcurpos(),
        \ 'to_eol': winsaveview().curswant >= s:eol}
endfunction

" The part of each line `sel` covers: [[lnum, first, last]], 0-indexed byte
" columns, `last` possibly past the end of the line.
function! songwriter#selection#Spans(sel) abort
  let [l:p, l:q] = [a:sel.anchor, a:sel.cursor]
  if l:p[1] > l:q[1] || (l:p[1] == l:q[1] && l:p[2] > l:q[2])
    let [l:p, l:q] = [l:q, l:p]
  endif
  let [l:lcol, l:rcol] = [min([l:p[2], l:q[2]]) - 1, max([l:p[2], l:q[2]]) - 1]
  let l:spans = []
  for l:lnum in range(l:p[1], l:q[1])
    if a:sel.mode ==# 'V'
      let [l:first, l:last] = [0, s:eol]
    elseif a:sel.mode ==# 'v'
      let l:first = l:lnum == l:p[1] ? l:p[2] - 1 : 0
      let l:last = l:lnum == l:q[1] ? l:q[2] - 1 : s:eol
    else
      let [l:first, l:last] = [l:lcol, a:sel.to_eol ? s:eol : l:rcol]
    endif
    call add(l:spans, [l:lnum, l:first, l:last])
  endfor
  return l:spans
endfunction

" Start visual mode `sel.mode` again, from `sel.anchor` to `sel.cursor`, as
" Get() read them.
function! songwriter#selection#Select(sel) abort
  call setpos('.', a:sel.anchor)
  execute 'normal! ' . a:sel.mode
  call setpos('.', a:sel.cursor)
  if a:sel.to_eol
    normal! $
  endif
endfunction
