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
" a dash it replaces the dash; on a note it replaces the whole note. Straight
" after a digit was typed (cursor still on it, buffer unchanged since), the next
" digit is appended instead, so two-digit frets are typed one key at a time
" (3.4.1). Then lint the block, keeping the cursor on the digit (4.1); this
" fills any open slot. No-op off a tab line.
function! songwriter#tab#EnterNote(digit) abort
  let l:line = getline('.')
  if !songwriter#grammar#IsTabLine(l:line)
    return
  endif
  let l:digit = a:digit . ''
  let l:col = col('.')
  let l:ch = (l:col <= len(l:line)) ? l:line[l:col - 1] : ''
  let l:typing = {'line': line('.'), 'col': l:col, 'tick': b:changedtick}
  let l:note = s:note_at(l:line, l:col)
  if get(b:, 'songwriter_typing', {}) ==# l:typing && songwriter#grammar#IsNoteChar(l:ch)
    call setline('.', l:line[0 : l:col - 1] . l:digit . l:line[l:col :])
    call cursor(line('.'), l:col + 1)
  elseif !empty(l:note)
    call setline('.', strpart(l:line, 0, l:note.col - 1) . l:digit
          \ . strpart(l:line, l:note.col - 1 + l:note.len))
    call cursor(line('.'), l:note.col)
  else
    call setline('.', l:line[0 : l:col - 2] . l:digit . l:line[l:col :])
    call cursor(line('.'), l:col)
  endif
  call s:lint_and_follow(songwriter#tab#model#Read())
  unlet! b:songwriter_slot
  let b:songwriter_typing = {'line': line('.'), 'col': col('.'), 'tick': b:changedtick}
endfunction

" The note of `line` covering column `col`, or {}.
function! s:note_at(line, col) abort
  for l:n in songwriter#tab#model#Notes(a:line)
    if a:col >= l:n.col && a:col < l:n.col + l:n.len
      return l:n
    endif
  endfor
  return {}
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
        \ : songwriter#tab#PrependSlot(l:block, l:line, col('.'))
  call s:apply(l:block, l:result)
  if !empty(l:result)
    let b:songwriter_slot = {'line': line('.'), 'tick': b:changedtick}
  endif
endfunction

" Pure. The `a` slot: the anchor is the rightmost note end, on any string,
" among notes of the cursor's bar that start at or before the cursor (so the
" anchor is the note column under or left of the cursor). Dashes are inserted
" after the anchor so that the slot sits one dash from it and the next note, on
" any string, stays one dash away (the next pipe, two dashes).
" Returns {'lines', 'col'}, or {} when there is no anchor note.
function! songwriter#tab#AppendSlot(block, line, col) abort
  let l:bar = songwriter#tab#model#BarAt(a:line, a:col)
  let l:e = 0
  for l:s in a:block.strings
    for l:n in l:s.notes
      if l:n.col <= a:col && songwriter#tab#model#InBar(l:n.col, l:bar)
        let l:e = max([l:e, l:n.col - 1 + l:n.len])
      endif
    endfor
  endfor
  if l:e == 0
    return {}
  endif
  " Wanted column of the nearest next note (e + 4) or pipe (e + 5), any string.
  let l:n = 0
  for l:s in a:block.strings
    for l:note in l:s.notes
      if l:note.col > l:e
        let l:n = max([l:n, l:e + 4 - l:note.col])
      endif
    endfor
    for l:p in l:s.pipes
      if l:p > l:e
        let l:n = max([l:n, l:e + 5 - l:p])
      endif
    endfor
  endfor
  return {
        \ 'lines': songwriter#tab#model#InsertColumns(a:block.lines, l:e, l:n, '-'),
        \ 'col': l:e + 2}
endfunction

" Pure. The `i` slot, mirror of AppendSlot: the anchor is the leftmost note
" start, on any string, among notes of the cursor's bar that end at or after
" the cursor. Dashes are inserted before it so that the slot sits one dash left
" of it and the previous note, on any string, stays one dash away (the
" previous pipe, two dashes).
" Returns {'lines', 'col'}, or {} when there is no anchor note.
function! songwriter#tab#PrependSlot(block, line, col) abort
  let l:bar = songwriter#tab#model#BarAt(a:line, a:col)
  let l:s = 0
  for l:str in a:block.strings
    for l:n in l:str.notes
      if l:n.col - 1 + l:n.len >= a:col
            \ && songwriter#tab#model#InBar(l:n.col, l:bar)
            \ && (l:s == 0 || l:n.col < l:s)
        let l:s = l:n.col
      endif
    endfor
  endfor
  if l:s == 0
    return {}
  endif
  " Dashes needed so the previous note end (s - 4) or pipe (s - 5) is far enough.
  let l:n = 0
  for l:str in a:block.strings
    for l:note in l:str.notes
      let l:end = l:note.col - 1 + l:note.len
      if l:end < l:s
        let l:n = max([l:n, l:end + 4 - l:s])
      endif
    endfor
    for l:p in l:str.pipes
      if l:p < l:s
        let l:n = max([l:n, l:p + 5 - l:s])
      endif
    endfor
  endfor
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
