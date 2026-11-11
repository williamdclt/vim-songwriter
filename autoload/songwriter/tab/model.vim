" autoload/songwriter/tab/model.vim - the tablature block model.
"
" A block is the contiguous run of tab lines around a line. It is parsed once
" into a dict, and features query it instead of re-scanning raw strings:
"
"   block = {
"     'start':   first buffer line number of the block,
"     'end':     last buffer line number of the block,
"     'lines':   the raw line strings,
"     'strings': one entry per line: {
"        'text':  the raw line,
"        'notes': [{'col': 1-indexed start column, 'len': width, 'text': '12'}],
"        'pipes': [1-indexed columns of every `|`],
"     },
"   }
"
" All columns are 1-indexed byte columns (tab lines are ASCII), as col() gives.
" Everything here is pure except Read() and Write(), the buffer edges.

" The string name of a tab line.
function! songwriter#tab#model#Name(line) abort
  return a:line[0]
endfunction

" The string names of tab lines.
function! songwriter#tab#model#Names(lines) abort
  return map(copy(a:lines), 'songwriter#tab#model#Name(v:val)')
endfunction

" Bytes before a tab line's body: the string name and the first pipe. Also the
" column of that first pipe.
function! songwriter#tab#model#BodyOffset() abort
  return 2
endfunction

" Notes of a tab line, left to right, skipping the string name.
function! songwriter#tab#model#Notes(line) abort
  return s:matches(a:line, songwriter#grammar#Note(), songwriter#tab#model#BodyOffset())
endfunction

" The note of `line` covering column `col`, or {}.
function! songwriter#tab#model#NoteAt(line, col) abort
  for l:n in songwriter#tab#model#Notes(a:line)
    if a:col >= l:n.col && a:col < l:n.col + l:n.len
      return l:n
    endif
  endfor
  return {}
endfunction

" Chains of a tab line (see grammar), left to right, same shape as Notes().
function! songwriter#tab#model#Chains(line) abort
  return s:matches(a:line, songwriter#grammar#Chain(), songwriter#tab#model#BodyOffset())
endfunction

" The chain of `line` covering column `col`, or {}.
function! songwriter#tab#model#ChainAt(line, col) abort
  for l:ch in songwriter#tab#model#Chains(a:line)
    if a:col >= l:ch.col && a:col < l:ch.col + l:ch.len
      return l:ch
    endif
  endfor
  return {}
endfunction

" Words of a tab line (spec [Tablature][[Editing]] 3.2): its chains holding at
" least one note, left to right, as {'start', 'end' (the chain's first and last
" columns), 'first', 'last' (the start columns of its first and last notes)}.
function! songwriter#tab#model#Words(line) abort
  let l:notes = songwriter#tab#model#Notes(a:line)
  let l:words = []
  for l:ch in songwriter#tab#model#Chains(a:line)
    let l:end = l:ch.col + l:ch.len - 1
    let l:in = filter(copy(l:notes), 'v:val.col >= l:ch.col && v:val.col <= l:end')
    if !empty(l:in)
      call add(l:words, {'start': l:ch.col, 'end': l:end,
            \ 'first': l:in[0].col, 'last': l:in[-1].col})
    endif
  endfor
  return l:words
endfunction

" Notes of a row: a bar region or a register row, with no string name.
function! songwriter#tab#model#RowNotes(row) abort
  return s:matches(a:row, songwriter#grammar#Note(), 0)
endfunction

" Separators of a row, same shape as RowNotes().
function! songwriter#tab#model#RowSeparators(row) abort
  return s:matches(a:row, songwriter#grammar#Separator(), 0)
endfunction

" Chains of a row, same shape as RowNotes().
function! songwriter#tab#model#RowChains(row) abort
  return s:matches(a:row, songwriter#grammar#Chain(), 0)
endfunction

function! s:matches(text, pat, start) abort
  let l:res = []
  let l:m = matchstrpos(a:text, a:pat, a:start)
  while l:m[1] >= 0
    call add(l:res, {'col': l:m[1] + 1, 'len': len(l:m[0]), 'text': l:m[0]})
    let l:m = matchstrpos(a:text, a:pat, l:m[2])
  endwhile
  return l:res
endfunction

" Columns of every `|` on a line.
function! songwriter#tab#model#Pipes(text) abort
  let l:res = []
  let l:m = stridx(a:text, '|')
  while l:m >= 0
    call add(l:res, l:m + 1)
    let l:m = stridx(a:text, '|', l:m + 1)
  endwhile
  return l:res
endfunction

function! songwriter#tab#model#Parse(start, lines) abort
  let l:strings = []
  for l:text in a:lines
    call add(l:strings, {
          \ 'text': l:text,
          \ 'notes': songwriter#tab#model#Notes(l:text),
          \ 'pipes': songwriter#tab#model#Pipes(l:text),
          \ })
  endfor
  return {'start': a:start, 'end': a:start + len(a:lines) - 1,
        \ 'lines': copy(a:lines), 'strings': l:strings}
endfunction

" The block around buffer line `lnum` (default: the cursor line), or {} when
" that line is not a tab line.
function! songwriter#tab#model#Read(...) abort
  let l:lnum = a:0 ? a:1 : line('.')
  if !songwriter#grammar#IsTabLine(getline(l:lnum))
    return {}
  endif
  let l:start = l:lnum
  while l:start > 1 && songwriter#grammar#IsTabLine(getline(l:start - 1))
    let l:start -= 1
  endwhile
  let l:end = l:lnum
  while l:end < line('$') && songwriter#grammar#IsTabLine(getline(l:end + 1))
    let l:end += 1
  endwhile
  return songwriter#tab#model#Parse(l:start, getline(l:start, l:end))
endfunction

" The cursor in `block` (default: the block around it): {'block', 'lin': its
" 0-indexed line in the block, 'col', 'line': the text of its line}, or {} off
" a tab line.
function! songwriter#tab#model#Cursor(...) abort
  let l:block = a:0 ? a:1 : songwriter#tab#model#Read()
  if empty(l:block)
    return {}
  endif
  let l:lin = songwriter#tab#model#CursorLin(l:block)
  return {'block': l:block, 'lin': l:lin, 'col': col('.'), 'line': l:block.lines[l:lin]}
endfunction

" The cursor's 0-indexed line in `block`.
function! songwriter#tab#model#CursorLin(block) abort
  return line('.') - a:block.start
endfunction

" Write `lines` (one per block string) back over the block in the buffer.
" Only the lines that differ are set, so writing what is already there makes
" no change (no undo step, b:changedtick unchanged).
function! songwriter#tab#model#Write(block, lines) abort
  for l:i in range(len(a:lines))
    if getline(a:block.start + l:i) !=# a:lines[l:i]
      call setline(a:block.start + l:i, a:lines[l:i])
    endif
  endfor
endfunction

" Start columns of every note on any string of the block, sorted, unique.
function! songwriter#tab#model#NoteColumns(block) abort
  let l:cols = []
  for l:s in a:block.strings
    call extend(l:cols, map(copy(l:s.notes), 'v:val.col'))
  endfor
  return uniq(sort(l:cols, 'n'))
endfunction

" The last column of a note.
function! songwriter#tab#model#NoteEnd(note) abort
  return a:note.col + a:note.len - 1
endfunction

" The last column of time column `c` of `tab` (a parsed block): the end of its
" longest note.
function! songwriter#tab#model#ColumnEnd(tab, c) abort
  let l:e = a:c
  for l:s in a:tab.strings
    for l:n in l:s.notes
      if l:n.col == a:c
        let l:e = max([l:e, songwriter#tab#model#NoteEnd(l:n)])
      endif
    endfor
  endfor
  return l:e
endfunction

" True when another string than line `lin` of `tab` has a note starting at
" column `c`.
function! songwriter#tab#model#IsShared(tab, lin, c) abort
  for l:i in range(len(a:tab.strings))
    if l:i != a:lin && !empty(filter(copy(a:tab.strings[l:i].notes), 'v:val.col == a:c'))
      return 1
    endif
  endfor
  return 0
endfunction

" The bar around column `col` of line `lin` of `tab` (see BarAt) and its time
" columns: {'bar', 'cols'}.
function! songwriter#tab#model#BarColumns(tab, lin, col) abort
  let l:bar = songwriter#tab#model#BarAt(a:tab.lines[a:lin], a:col)
  return {'bar': l:bar, 'cols': filter(songwriter#tab#model#NoteColumns(a:tab),
        \ 'songwriter#tab#model#InBar(v:val, l:bar)')}
endfunction

" The notes of `tab` starting inside `bar` (see BarAt), on any string, each
" with its string's 0-indexed `lin`.
function! songwriter#tab#model#BarNotes(tab, bar) abort
  let l:res = []
  for l:lin in range(len(a:tab.strings))
    for l:n in a:tab.strings[l:lin].notes
      if songwriter#tab#model#InBar(l:n.col, a:bar)
        call add(l:res, extend(copy(l:n), {'lin': l:lin}))
      endif
    endfor
  endfor
  return l:res
endfunction

" The end of the gap after time column `c` of the bar `bc` (from BarColumns,
" for line `lin`): the bar's next column, or its closing pipe (the line's end
" when unbounded), minus one.
function! songwriter#tab#model#GapEnd(tab, lin, bc, c) abort
  let l:next = filter(copy(a:bc.cols), 'v:val > a:c')
  if !empty(l:next)
    return l:next[0] - 1
  endif
  return a:bc.bar.end > 0 ? a:bc.bar.end - 1 : len(a:tab.lines[a:lin])
endfunction

" The time column for the cursor at `col`, among a bar's columns `cols`: the
" nearest one at or left of `col`, else the first one right of it; 0 when there
" is none.
function! songwriter#tab#model#ColumnFor(cols, col) abort
  let l:left = filter(copy(a:cols), 'v:val <= a:col')
  if !empty(l:left)
    return l:left[-1]
  endif
  let l:right = filter(copy(a:cols), 'v:val > a:col')
  return empty(l:right) ? 0 : l:right[0]
endfunction

" The bar around `col` on a line: {'start': column of the nearest pipe strictly
" left of col, 'end': column of the nearest pipe strictly right}. A side with no
" pipe is 0, meaning unbounded.
function! songwriter#tab#model#BarAt(text, col) abort
  let l:bar = {'start': 0, 'end': 0}
  for l:p in songwriter#tab#model#Pipes(a:text)
    if l:p < a:col
      let l:bar.start = l:p
    elseif l:p > a:col
      let l:bar.end = l:p
      break
    endif
  endfor
  return l:bar
endfunction

" True when column `col` lies strictly inside `bar` (see BarAt).
function! songwriter#tab#model#InBar(col, bar) abort
  return (a:bar.start == 0 || a:col > a:bar.start)
        \ && (a:bar.end == 0 || a:col < a:bar.end)
endfunction

" `line` padded with dashes to `width` bytes.
function! songwriter#tab#model#Pad(line, width) abort
  return len(a:line) < a:width ? a:line . repeat('-', a:width - len(a:line)) : a:line
endfunction

" `line` with the `len` bytes from column `col` replaced by `text` (with `len`
" 0, `text` is inserted before column `col`).
function! songwriter#tab#model#Splice(line, col, len, text) abort
  return strpart(a:line, 0, a:col - 1) . a:text . strpart(a:line, a:col - 1 + a:len)
endfunction

" `line` with `note` (as Notes() gives it) turned into dashes of its width.
function! songwriter#tab#model#Blank(line, note) abort
  return songwriter#tab#model#Splice(a:line, a:note.col, a:note.len, repeat('-', a:note.len))
endfunction

" The column-insertion primitive: insert `n` copies of `char` after byte offset
" `offset` (0 = line start) on every line, padding shorter lines with dashes up
" to `offset` first. Returns the new lines; padding happens even when n is 0.
function! songwriter#tab#model#InsertColumns(lines, offset, n, char) abort
  let l:out = []
  for l:l in a:lines
    if len(l:l) < a:offset
      let l:l .= repeat('-', a:offset - len(l:l))
    endif
    call add(l:out, strpart(l:l, 0, a:offset) . repeat(a:char, a:n) . strpart(l:l, a:offset))
  endfor
  return l:out
endfunction
