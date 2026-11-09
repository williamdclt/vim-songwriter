" autoload/songwriter/tab.vim - tablature operations (spec [Tablature]).
"
" Public functions are the buffer entry points: they read the block with
" songwriter#tab#model#Read(), call a pure helper that returns new lines and/or
" a cursor column, and apply the result. Parsing and column arithmetic live in
" the model (tab/model.vim); the linter in tab/lint.vim.

" Apply a pure result {'lines'?: [...], 'col'?: n} to the block / cursor line.
function! s:apply(block, result) abort
  if has_key(a:result, 'lines')
    call songwriter#tab#model#Write(a:block, a:result.lines)
  endif
  if has_key(a:result, 'col')
    call cursor(line('.'), a:result.col)
  endif
endfunction

" === Editing ===

" Append `--` to every string of the block.
function! songwriter#tab#AddDashes() abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call songwriter#tab#model#Write(l:block, map(copy(l:block.lines), "v:val . '--'"))
endfunction

" Spec [Tablature][[Editing]] 2: insert a dash after the cursor column on
" every string of the block.
function! songwriter#tab#AddDash() abort
  call s:insert_after_cursor('-')
endfunction

" Insert a bar pipe after the cursor column on every string of the block.
function! songwriter#tab#AddBar() abort
  call s:insert_after_cursor('|')
endfunction

function! s:insert_after_cursor(char) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call songwriter#tab#model#Write(l:block,
        \ songwriter#tab#model#InsertColumns(l:block.lines, col('.'), 1, a:char))
endfunction

" Spec [Tablature][[Editing]] 1: lint the block around the cursor.
function! songwriter#tab#Lint() abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call songwriter#tab#model#Write(l:block, songwriter#tab#lint#Lint(l:block.lines).lines)
endfunction

" Insert `chord` on a new line above the block, aligned to the cursor column.
function! songwriter#tab#TabChord(chord) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call append(l:block.start - 1, repeat(' ', col('.') - 1) . a:chord)
endfunction

" Spec [Tablature][[Editing]] 3.4: put `digit` in the cell under the cursor. On
" a dash it replaces it; on a digit it is appended to its right, so two-digit
" frets can be typed one key at a time. Then lint the block, keeping the cursor
" on the digit (4.1); this fills any open slot. No-op off a tab line.
function! songwriter#tab#EnterNote(digit) abort
  let l:line = getline('.')
  if !songwriter#grammar#IsTabLine(l:line)
    return
  endif
  let l:digit = a:digit . ''
  let l:col = col('.')
  let l:ch = (l:col <= len(l:line)) ? l:line[l:col - 1] : ''
  if songwriter#grammar#IsNoteChar(l:ch)
    call setline('.', l:line[0 : l:col - 1] . l:digit . l:line[l:col :])
    call cursor(line('.'), l:col + 1)
  else
    call setline('.', l:line[0 : l:col - 2] . l:digit . l:line[l:col :])
    call cursor(line('.'), l:col)
  endif
  call s:lint_and_follow(songwriter#tab#model#Read())
  unlet! b:songwriter_slot
endfunction

" Spec [Tablature][[Editing]] 3.1: open room for a new note on every string,
" to the right of the current note (side +1, `a`) or to its left (side -1,
" `i`), and land the cursor on the new slot. The block is linted first (4.2),
" and the slot is remembered until a note fills it or it is abandoned (4.3).
function! songwriter#tab#AddNote(side) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  unlet! b:songwriter_slot
  let l:block = s:lint_and_follow(l:block)
  let l:line = getline('.')
  let l:result = a:side > 0
        \ ? songwriter#tab#AppendSlot(l:block, l:line, col('.'))
        \ : songwriter#tab#PrependSlot(l:block, col('.'))
  call s:apply(l:block, l:result)
  if !empty(l:result)
    let b:songwriter_slot = {'line': line('.'), 'tick': b:changedtick}
  endif
endfunction

" Pure. The `a` slot: the anchor note is the rightmost note end, on any string,
" among notes starting at or before the cursor and inside the cursor's bar
" (bounded by the bar's closing pipe, so appending at the end of a non-final bar
" stays in that bar). Dashes are inserted after the anchor so that the slot sits
" one dash from it and the next pipe keeps a 2-dash gap (a next note, 1 dash).
" Returns {'lines', 'col'}, or {} when there is no anchor note.
function! songwriter#tab#AppendSlot(block, line, col) abort
  let l:bar = songwriter#tab#model#BarAt(a:line, a:col)
  let l:bound = l:bar.end > 0 ? l:bar.end - 1 : a:col
  let l:e = 0
  let l:ref = 0
  for l:i in range(len(a:block.strings))
    for l:n in a:block.strings[l:i].notes
      if l:n.col <= l:bound && l:n.col - 1 + l:n.len > l:e
        let l:e = l:n.col - 1 + l:n.len
        let l:ref = l:i
      endif
    endfor
  endfor
  if l:e == 0
    return {}
  endif
  " Columns needed between the anchor's end (offset e) and the next note/pipe.
  let l:rest = strpart(a:block.lines[l:ref], l:e)
  let l:m = match(l:rest, '[0-9|]')
  let l:n = 0
  if l:m >= 0
    let l:next = l:e + 1 + l:m
    let l:want = (l:rest[l:m] ==# '|') ? l:e + 5 : l:e + 4
    let l:n = max([0, l:want - l:next])
  endif
  return {
        \ 'lines': songwriter#tab#model#InsertColumns(a:block.lines, l:e, l:n, '-'),
        \ 'col': l:e + 2}
endfunction

" Pure. The `i` slot, mirror of AppendSlot: the anchor is the leftmost note, on
" any string, starting at or after the cursor; dashes are inserted before it so
" the slot sits one dash left of it and the preceding pipe keeps a 2-dash gap.
" Returns {'lines', 'col'}, or {} when there is no anchor note.
function! songwriter#tab#PrependSlot(block, col) abort
  let l:s = 0
  let l:ref = 0
  for l:i in range(len(a:block.strings))
    for l:n in a:block.strings[l:i].notes
      if l:n.col >= a:col && (l:s == 0 || l:n.col < l:s)
        let l:s = l:n.col
        let l:ref = l:i
      endif
    endfor
  endfor
  if l:s == 0
    return {}
  endif
  let l:pipe = 0
  for l:p in a:block.strings[l:ref].pipes
    if l:p <= l:s - 2
      let l:pipe = l:p
    endif
  endfor
  let l:n = (l:pipe == 0) ? 0 : max([0, l:pipe + 5 - l:s])
  return {
        \ 'lines': songwriter#tab#model#InsertColumns(a:block.lines, l:s - 1, l:n, '-'),
        \ 'col': l:s + l:n - 2}
endfunction

" === Linting after edits (spec [Tablature][[Editing]] 4) ===

" Lint `block`, write it back and keep the cursor on the same note (or in the
" same gap between notes) when it is inside the block. Returns the re-read
" block, or {} when `block` is empty.
function! s:lint_and_follow(block) abort
  if empty(a:block)
    return {}
  endif
  let l:result = songwriter#tab#lint#Lint(a:block.lines)
  call songwriter#tab#model#Write(a:block, l:result.lines)
  let l:lin = line('.') - a:block.start
  if l:lin >= 0 && l:lin < len(a:block.lines)
    call cursor(line('.'),
          \ songwriter#tab#lint#FollowColumn(a:block.lines, l:result, l:lin, col('.')))
  endif
  return songwriter#tab#model#Read(a:block.start)
endfunction

" Spec 4.3: if the slot opened by `a`/`i` (or `l`, 3.3.2) is still open and
" empty (the buffer has not changed since, e.g. only `j`/`k` were pressed),
" lint its block. Called by the tablature-mode keys that abandon a slot.
function! songwriter#tab#LintAbandonedSlot() abort
  let l:slot = get(b:, 'songwriter_slot', {})
  unlet! b:songwriter_slot
  if empty(l:slot) || l:slot.tick != b:changedtick
    return
  endif
  call s:lint_and_follow(songwriter#tab#model#Read(l:slot.line))
endfunction

" === Motions ===

" Spec [Tablature][[Editing]] 3.2: move to the next (dir +1) / previous (-1)
" note on the current line. No-op off a tab line or with no note that way.
" An open slot is abandoned first (4.3).
function! songwriter#tab#MoveNote(dir) abort
  call songwriter#tab#LintAbandonedSlot()
  let l:line = getline('.')
  if !songwriter#grammar#IsTabLine(l:line)
    return
  endif
  let l:cols = map(songwriter#tab#model#Notes(l:line), 'v:val.col')
  let l:target = s:nearest(l:cols, col('.'), a:dir)
  if l:target > 0
    call cursor(line('.'), l:target)
  endif
endfunction

" Spec [Tablature][[Editing]] 3.3: `l` (dir +1) / `h` (dir -1) move to the
" next/previous column where any string of the block has a note, crossing bar
" pipes. Exception (3.3.2): `l` on the last note column of the cursor's bar
" opens a slot as `a` does (linting first, 4.2); `l` with no note further
" right does the same. `h` never opens a slot and is a no-op before the first
" note (3.3.3). An open slot is abandoned first (4.3).
function! songwriter#tab#MoveColumn(dir) abort
  call songwriter#tab#LintAbandonedSlot()
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:line = getline('.')
  let l:col = col('.')
  let l:cols = songwriter#tab#model#NoteColumns(l:block)

  if a:dir < 0
    let l:target = s:nearest(l:cols, l:col, -1)
    if l:target > 0
      call cursor(line('.'), l:target)
    endif
    return
  endif

  let l:bar = songwriter#tab#model#BarAt(l:line, l:col)
  let l:in_bar = filter(copy(l:cols), 'songwriter#tab#model#InBar(v:val, l:bar)')
  let l:last_in_bar = empty(l:in_bar) ? 0 : max(l:in_bar)
  let l:target = s:nearest(l:cols, l:col, 1)
  if l:col == l:last_in_bar || l:target == 0
    call songwriter#tab#AddNote(1)
  else
    call cursor(line('.'), min([l:target, len(l:line)]))
  endif
endfunction

" The nearest value in `cols` strictly after (dir > 0) or before (dir < 0)
" `col`; 0 when none.
function! s:nearest(cols, col, dir) abort
  let l:cands = filter(copy(a:cols), a:dir > 0 ? 'v:val > a:col' : 'v:val < a:col')
  return empty(l:cands) ? 0 : (a:dir > 0 ? min(l:cands) : max(l:cands))
endfunction
