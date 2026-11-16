" autoload/songwriter/tab/highlight.vim - the time column under the cursor,
" highlighted on every string in tablature mode (spec [Tablature][[Rendering]] 4), so that it
" is clear which notes column-wise operations act on, and in the move state the
" note under the cursor (spec [Tablature][[Editing]] 3.8.5), so that the state
" shows where the eye is. Highlighting only (window matches on the groups
" songwriterTimeColumn and songwriterMovingNote): the file is unchanged.

" Pure. The positions [[lnum, col, len], ...] of the time column under the
" cursor at column `col` of line `lin` of `block`: the column where the note
" under the cursor starts (the cursor's column when it is on no note), on
" every string, notes or dashes, and on the annotation lines above them
" ([[Annotations]] 7), as wide as its widest note. [] when no note starts there
" on any string.
function! songwriter#tab#highlight#Positions(block, lin, col) abort
  let l:note = songwriter#tab#model#NoteAt(a:block.lines[a:lin], a:col)
  let l:c = empty(l:note) ? a:col : l:note.col
  if index(songwriter#tab#model#NoteColumns(a:block), l:c) < 0
    return []
  endif
  let l:width = songwriter#tab#model#ColumnEnd(a:block, l:c) - l:c + 1
  let l:pos = []
  " Annotations are placed by display column: the bytes of that column there.
  for l:i in range(len(get(a:block, 'above', [])))
    let l:range = songwriter#tab#annotations#Bytes(a:block.above[l:i], l:c, l:width)
    if !empty(l:range)
      call add(l:pos, [a:block.top + l:i] + l:range)
    endif
  endfor
  return l:pos + map(range(len(a:block.lines)), {i, _ -> [a:block.start + i, l:c, l:width]})
endfunction

" Pure. The position [[lnum, col, len]] of the note under the cursor at
" column `col` of line `lin` of `block`, [] when it is on no note.
function! songwriter#tab#highlight#NotePosition(block, lin, col) abort
  let l:note = songwriter#tab#model#NoteAt(a:block.lines[a:lin], a:col)
  return empty(l:note) ? [] : [[a:block.start + a:lin, l:note.col, len(l:note.text)]]
endfunction

" Highlight the time column under the cursor in the current window and, in the
" move state (spec [Tablature][[Editing]] 3.8.5), the note under the cursor
" over it; nothing outside tablature mode or off a tab line. Run on every
" cursor move and change of state, so it changes the window's matches only
" when what they cover does.
function! songwriter#tab#highlight#Update() abort
  let l:pos = {'column': [], 'note': []}
  if songwriter#keys#InTabMode()
    let l:c = songwriter#tab#model#Cursor()
    if !empty(l:c)
      let l:pos.column = songwriter#tab#highlight#Positions(l:c.block, l:c.lin, l:c.col)
      if songwriter#tab#mode#Current() ==# 'move'
        let l:pos.note = songwriter#tab#highlight#NotePosition(l:c.block, l:c.lin, l:c.col)
      endif
    endif
  endif
  if l:pos ==# get(w:, 'songwriter_column_pos', {'column': [], 'note': []})
    return
  endif
  call songwriter#tab#highlight#Clear()
  " Vim 8.2 takes at most 8 positions per match.
  let w:songwriter_column_match = map(range(0, len(l:pos.column) - 1, 8),
        \ {_, i -> matchaddpos('songwriterTimeColumn', l:pos.column[i : i + 7])})
  if !empty(l:pos.note)
    call add(w:songwriter_column_match, matchaddpos('songwriterMovingNote', l:pos.note, 11))
  endif
  let w:songwriter_column_pos = l:pos
endfunction

" Remove the highlight from the current window.
function! songwriter#tab#highlight#Clear() abort
  for l:id in get(w:, 'songwriter_column_match', [])
    silent! call matchdelete(l:id)
  endfor
  unlet! w:songwriter_column_match w:songwriter_column_pos
endfunction
