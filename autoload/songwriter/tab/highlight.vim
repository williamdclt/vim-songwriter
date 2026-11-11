" autoload/songwriter/tab/highlight.vim - the time column under the cursor,
" highlighted in tablature mode (spec [Tablature][[Rendering]] 4), so that it
" is clear which notes column-wise operations act on. Highlighting only (a
" window match on the group songwriterTimeColumn): the file is unchanged.

" Pure. The positions [[lnum, col, len], ...] of the time column under the
" cursor at column `col` of line `lin` of `block`: the notes starting where the
" note under the cursor starts (on the cursor's column when it is on no note),
" on every string. [] when there is none.
function! songwriter#tab#highlight#Positions(block, lin, col) abort
  let l:note = songwriter#tab#model#NoteAt(a:block.lines[a:lin], a:col)
  let l:c = empty(l:note) ? a:col : l:note.col
  let l:res = []
  for l:i in range(len(a:block.strings))
    for l:n in a:block.strings[l:i].notes
      if l:n.col == l:c
        call add(l:res, [a:block.start + l:i, l:n.col, l:n.len])
      endif
    endfor
  endfor
  return l:res
endfunction

" Highlight the time column under the cursor in the current window, or
" nothing outside tablature mode or off a tab line. Run on every cursor move,
" so it changes the window's match only when the column does.
function! songwriter#tab#highlight#Update() abort
  let l:pos = []
  if songwriter#keys#InTabMode()
    let l:c = songwriter#tab#model#Cursor()
    if !empty(l:c)
      let l:pos = songwriter#tab#highlight#Positions(l:c.block, l:c.lin, l:c.col)
    endif
  endif
  if l:pos ==# get(w:, 'songwriter_column_pos', [])
    return
  endif
  call songwriter#tab#highlight#Clear()
  if !empty(l:pos)
    let w:songwriter_column_match = matchaddpos('songwriterTimeColumn', l:pos)
    let w:songwriter_column_pos = l:pos
  endif
endfunction

" Remove the highlight from the current window.
function! songwriter#tab#highlight#Clear() abort
  if exists('w:songwriter_column_match')
    silent! call matchdelete(w:songwriter_column_match)
  endif
  unlet! w:songwriter_column_match w:songwriter_column_pos
endfunction
