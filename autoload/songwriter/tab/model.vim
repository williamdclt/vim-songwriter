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

" Chains of a tab line (see grammar), left to right, same shape as Notes().
function! songwriter#tab#model#Chains(line) abort
  return s:matches(a:line, songwriter#grammar#Chain(), songwriter#tab#model#BodyOffset())
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
function! songwriter#tab#model#Write(block, lines) abort
  for l:i in range(len(a:lines))
    call setline(a:block.start + l:i, a:lines[l:i])
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

" `col` moved `count` stops forward (dir > 0) or backward (dir < 0) through the
" sorted list `stops`, stopping at the last one reached; `col` when there is none.
function! songwriter#tab#model#Advance(stops, col, dir, count) abort
  let l:col = a:col
  for l:i in range(a:count)
    let l:c = filter(copy(a:stops), a:dir > 0 ? 'v:val > l:col' : 'v:val < l:col')
    if empty(l:c)
      break
    endif
    let l:col = a:dir > 0 ? l:c[0] : l:c[-1]
  endfor
  return l:col
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
