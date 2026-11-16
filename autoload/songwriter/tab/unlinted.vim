" autoload/songwriter/tab/unlinted.vim - the string names of every tab with
" no time columns, highlighted (spec [Tablature][[Rendering]] 5), so that it
" is clear why edits of it are refused ([[Editing]] 4.5) before trying one.
" Highlighting only (window matches on the group songwriterUnlinted): the file
" is unchanged.

" Pure. The positions [[lnum, 1], ...] of the string names of the tabs of
" `lines` (a buffer's lines, from its line 1) that have no time columns
" (model#Timed).
function! songwriter#tab#unlinted#Positions(lines) abort
  let l:pos = []
  let l:lnum = 0
  while l:lnum < len(a:lines)
    if !songwriter#grammar#IsTabLine(a:lines[l:lnum])
      let l:lnum += 1
      continue
    endif
    let l:end = l:lnum
    while l:end + 1 < len(a:lines) && songwriter#grammar#IsTabLine(a:lines[l:end + 1])
      let l:end += 1
    endwhile
    if !songwriter#tab#model#Timed(a:lines[l:lnum : l:end])
      call extend(l:pos, map(range(l:lnum + 1, l:end + 1), {_, n -> [n, 1]}))
    endif
    let l:lnum = l:end + 1
  endwhile
  return l:pos
endfunction

" Highlight the string names of the tabs with no time columns in the current
" window. Run on every change, so it changes the window's match only when the
" positions do.
function! songwriter#tab#unlinted#Update() abort
  let l:pos = songwriter#tab#unlinted#Positions(getline(1, '$'))
  if l:pos ==# get(w:, 'songwriter_unlinted_shown', [])
    return
  endif
  call songwriter#tab#unlinted#Clear()
  if !empty(l:pos)
    " Vim 8.2 takes at most 8 positions per match.
    let w:songwriter_unlinted_match = map(range(0, len(l:pos) - 1, 8),
          \ {_, i -> matchaddpos('songwriterUnlinted', l:pos[i : i + 7])})
    let w:songwriter_unlinted_shown = l:pos
  endif
endfunction

" Remove the highlight from the current window.
function! songwriter#tab#unlinted#Clear() abort
  for l:id in get(w:, 'songwriter_unlinted_match', [])
    silent! call matchdelete(l:id)
  endfor
  unlet! w:songwriter_unlinted_match w:songwriter_unlinted_shown
endfunction
