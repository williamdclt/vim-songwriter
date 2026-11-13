" autoload/songwriter/tab/frets.vim - changing frets with <C-A> / <C-X> in
" tablature mode (spec [Tablature][[Editing]] 11). Add() is pure (block lines
" in, lines and cursor out); Increment() and IncrementIn() are the buffer entry
" points, for normal and visual mode.
"
" Block lines are 0-indexed (`lin`), columns 1-indexed, as in tab/columns.vim.

" Spec 11.1, 11.5: the frets of `line` that end at or after column `from` and
" start at or before column `to`, left to right (as model#Notes() gives them).
" A muted note is not a fret.
function! songwriter#tab#frets#Targets(line, from, to) abort
  return filter(songwriter#tab#model#Notes(a:line), {_, n ->
        \ songwriter#tab#model#NoteEnd(n) >= a:from && n.col <= a:to
        \ && n.text =~# '^' . songwriter#grammar#Fret() . '$'})
endfunction

" Spec 11: the note starting at column `c` of line `lin`, `n` frets up (n > 0)
" or down, every note keeping its time column (11.2, columns#SetNote). Returns
" {'lines', 'lin', 'col' (the cursor on the note), 'map'}, or {'error':
" message} (11.3).
function! songwriter#tab#frets#Add(lines, lin, c, n) abort
  let l:note = songwriter#tab#model#NoteAt(a:lines[a:lin], a:c)
  let l:fret = str2nr(l:note.text, 10) + a:n
  if l:fret < 0
    return {'error': 'the fret would go below 0'}
  endif
  let l:max = get(g:, 'songwriter_max_fret', 24)
  if l:fret > l:max
    return {'error': printf('the fret would go above %d', l:max)}
  endif
  let l:res = songwriter#tab#columns#SetNote(a:lines, a:lin, a:c, string(l:fret))
  return has_key(l:res, 'error') ? l:res : extend(l:res, {'lin': a:lin})
endfunction

" Spec 11: <C-A> (n > 0) / <C-X> by |n| frets on the note under the cursor, or
" the next fret after it on its string (11.1). The cursor stays on the same
" digit of the note (its last one when that digit is gone), or goes to the
" start of the next fret. Lints first (closing any open slot), lints again with
" the cursor on the note, and records itself for `.` (11.4). A refusal is
" echoed.
function! songwriter#tab#frets#Increment(n) abort
  let l:sign = a:n < 0 ? '-' : ''
  call songwriter#tab#edit#Do(function('s:increment', [a:n]), {
        \ 'slot': 'close',
        \ 'repeat': 'songwriter#tab#frets#Increment(' . l:sign . '%d)', 'count': abs(a:n)})
endfunction

function! s:increment(n, ctx) abort
  let l:notes = songwriter#tab#frets#Targets(a:ctx.line, a:ctx.col, len(a:ctx.line))
  if empty(l:notes)
    return {'error': 'songwriter: no fret under or after the cursor'}
  endif
  let l:note = l:notes[0]
  let l:res = songwriter#tab#frets#Add(a:ctx.block.lines, a:ctx.lin, l:note.col, a:n)
  if has_key(l:res, 'error')
    return {'error': 'songwriter: ' . l:res.error}
  endif
  let l:width = songwriter#tab#model#NoteAt(l:res.lines[a:ctx.lin], l:note.col).len
  let l:res.col = l:note.col + min([max([a:ctx.col - l:note.col, 0]), l:width - 1])
  return l:res
endfunction

" Spec 11.5: visual <C-A> / <C-X>, `ranges` being [lnum, first, last] (byte
" columns, 1-indexed) of selected tab lines: every fret a range touches changes
" by `n` as in Add(). The notes of a block change right to left, so that the
" room one makes, or a chain closing up, does not move the others before they
" are found; frets that would go out of range are left as they are. Each block
" is linted once.
function! songwriter#tab#frets#IncrementIn(ranges, n) abort
  let l:done = {}
  for [l:lnum, l:first, l:last] in a:ranges
    let l:block = songwriter#tab#model#Read(l:lnum)
    if empty(l:block) || has_key(l:done, l:block.start)
      continue
    endif
    let l:done[l:block.start] = 1
    let l:targets = []
    for [l:l, l:f, l:e] in a:ranges
      if l:l >= l:block.start && l:l <= l:block.end
        for l:note in songwriter#tab#frets#Targets(l:block.lines[l:l - l:block.start], l:f, l:e)
          call add(l:targets, [l:note.col, l:l - l:block.start])
        endfor
      endif
    endfor
    let l:lines = l:block.lines
    let l:map = []
    for [l:c, l:lin] in reverse(sort(l:targets, {a, b -> a[0] - b[0]}))
      let l:res = songwriter#tab#frets#Add(l:lines, l:lin, l:c, a:n)
      if !has_key(l:res, 'error')
        let l:lines = l:res.lines
        let l:map = songwriter#tab#colmap#Then(l:map, l:res.map)
      endif
    endfor
    if l:lines !=# l:block.lines
      let l:lint = songwriter#tab#lint#Lint(l:lines)
      call songwriter#tab#edit#Write(l:block, {'lines': l:lint.lines,
            \ 'map': songwriter#tab#colmap#Then(l:map, l:lint.map)})
    endif
  endfor
endfunction
