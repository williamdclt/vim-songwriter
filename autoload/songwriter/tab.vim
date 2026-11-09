" autoload/songwriter/tab.vim - tablature editing operations: inserting
" dashes/bars, the bar-alignment linter, and placing a chord above a bar.
" Private helpers stay s:-local; the public ops delegate to
" songwriter#util for the shared block scan and column op.

" === Linter support (private) ===

function! s:extract_atoms(region) abort
  let l:res = []
  let l:i = 0
  let l:n = len(a:region)
  while l:i < l:n
    if a:region[l:i] =~# '[0-9]'
      let l:j = l:i + 1
      while l:j < l:n && a:region[l:j] =~# '[0-9]'
        let l:j += 1
      endwhile
      call add(l:res, [l:i, strpart(a:region, l:i, l:j - l:i)])
      let l:i = l:j
    else
      let l:i += 1
    endif
  endwhile
  return l:res
endfunction
function! s:parse_tab_lines(lines) abort
  let l:regions = []
  let l:P = 0
  for l:ln in a:lines
    let l:parts = split(l:ln, '[|]', 1)
    call remove(l:parts, 0)             " drop the string-name prefix
    call remove(l:parts, len(l:parts) - 1) " drop anything after the final pipe
    call add(l:regions, l:parts)
    if len(l:parts) > l:P
      let l:P = len(l:parts)
    endif
  endfor
  return [l:regions, l:P, len(a:lines)]
endfunction
function! s:relax_bar(atoms, mincol) abort
  let l:work = []
  for l:a in a:atoms
    call add(l:work, {
             \ 'lin': l:a[0],
             \ 'c0': l:a[1],
             \ 'num': l:a[2],
             \ 'len': len(l:a[2]),
             \ 'start': l:a[1] - a:mincol + 2})
  endfor

  let l:iter = 0
  while l:iter < 200
    let l:iter += 1
    let l:changed = 0
    let l:last = {}
    for l:a in l:work
      let l:need = l:a['start']
      if has_key(l:last, l:a['lin'])
        let l:gap = l:a['c0'] - l:last[l:a['lin']]['c0']
        let l:cand = l:last[l:a['lin']]['start'] + l:gap
        if l:cand > l:need
          let l:need = l:cand
        endif
      endif
      for l:b in l:work
        if l:b['lin'] !=# l:a['lin']
              \ && l:b['start'] < l:a['start']
              \ && l:a['start'] <= l:b['start'] + l:b['len'] - 1
          let l:cand = l:b['start'] + l:b['len'] + 1
          if l:cand > l:need
            let l:need = l:cand
          endif
        endif
      endfor
      if l:need > l:a['start']
        let l:a['start'] = l:need
        let l:changed = 1
      endif
      let l:last[l:a['lin']] = {'c0': l:a['c0'], 'start': l:a['start']}
    endfor
    if !l:changed
      break
    endif
  endwhile
  return l:work
endfunction
function! s:render_bar(work, NL) abort
  let l:maxend = 2
  for l:a in a:work
    let l:e = l:a['start'] + l:a['len'] - 1
    if l:e > l:maxend
      let l:maxend = l:e
    endif
  endfor
  let l:W = l:maxend + 3

  let l:bylin = {}
  for l:a in a:work
    if !has_key(l:bylin, l:a['lin'])
      let l:bylin[l:a['lin']] = []
    endif
    call add(l:bylin[l:a['lin']], l:a)
  endfor

  let l:out = []
  for l:lin in range(0, a:NL - 1)
    if has_key(l:bylin, l:lin)
      let l:arr = repeat(['-'], l:W)
      for l:a in l:bylin[l:lin]
        for l:k in range(0, l:a['len'] - 1)
          let l:arr[l:a['start'] + l:k] = l:a['num'][l:k]
        endfor
      endfor
      call add(l:out, join(l:arr, ''))
    else
      call add(l:out, repeat('-', l:W))
    endif
  endfor
  return l:out
endfunction
function! s:lint_block(lines)
  let l:parsed = s:parse_tab_lines(a:lines)
  let l:regions = l:parsed[0]
  let l:P = l:parsed[1]
  let l:NL = l:parsed[2]

  let l:lineparts = []
  for l:i in range(0, l:NL - 1)
    call add(l:lineparts, [])
  endfor

  for l:j in range(0, l:P - 1)
     " Collect this bar's digit atoms ([lin, c0, num]), its minimum column, and
     " whether any string has a note in the bar.
    let l:atoms = []
    let l:mn = 0
    let l:mnset = 0
    let l:h = 0
    for l:lin in range(0, l:NL - 1)
      if l:j >= len(l:regions[l:lin])
        continue
      endif
      for l:at in s:extract_atoms(l:regions[l:lin][l:j])
        call add(l:atoms, [l:lin, l:at[0], l:at[1]])
        let l:h = 1
        if !l:mnset || l:at[0] < l:mn
          let l:mn = l:at[0]
          let l:mnset = 1
        endif
      endfor
    endfor

    if l:h == 0
       " Empty bar -> exactly two dashes on every string.
      for l:lin in range(0, l:NL - 1)
        call add(l:lineparts[l:lin], '--')
      endfor
      continue
    endif

    let l:work = s:relax_bar(l:atoms, l:mn)
    let l:out_j = s:render_bar(l:work, l:NL)
    for l:lin in range(0, l:NL - 1)
      call add(l:lineparts[l:lin], l:out_j[l:lin])
    endfor
  endfor

   " Assemble lines.
  let l:out = []
  for l:k in range(0, l:NL - 1)
    let l:letter = strpart(a:lines[l:k], 0, 1)
    call add(l:out, l:letter . '|' . join(l:lineparts[l:k], '|') . '|')
  endfor
  return l:out
endfunction

" === Public tab operations ===

function! songwriter#tab#AddDashes()
  let l:block = songwriter#util#find_tab_block()
  if empty(l:block[2])
    return
  endif
  for l:i in range(len(l:block[2]))
    call setline(l:block[0] + l:i, l:block[2][l:i] . '--')
  endfor
endfunction

function! songwriter#tab#AddDash()
  call songwriter#util#insert_char_at_col('-')
endfunction

function! songwriter#tab#AddBar()
  call songwriter#util#insert_char_at_col('|')
endfunction

function! songwriter#tab#Lint()
  let l:block = songwriter#util#find_tab_block()
  if empty(l:block[2])
    return
  endif
  let l:newlines = s:lint_block(l:block[2])
  for l:i in range(len(l:newlines))
    call setline(l:block[0] + l:i, l:newlines[l:i])
  endfor
endfunction

" --- Tablature mode motions (spec [Editing] 3) ---

" 1-indexed start columns of every digit-run (note) in a whole tab line. Reuses
" s:extract_atoms, which already collects maximal runs of digits; the string-name
" prefix ('e') and any '|'/'-' fall between the runs and are skipped.
function! s:digit_run_starts(line) abort
  let l:res = []
  for l:a in s:extract_atoms(a:line)
    call add(l:res, l:a[0] + 1)
  endfor
  return l:res
endfunction

" 3.1: advance to the next/prev note on the CURRENT line, skipping dashes and
" pipes. `dir` is +1 (forward) or -1 (backward). A note is a digit run; the
" cursor lands on its first digit. No-op when the cursor is not on a tab line
" (e.g. prose), or when there is no note in the requested direction.
function! songwriter#tab#MoveNote(dir) abort
  if !songwriter#util#IsTablatureLine(getline('.'))
    return
  endif
  let l:col = col('.')
  let l:starts = s:digit_run_starts(getline('.'))
  let l:target = 0
  if a:dir > 0
    for l:s in l:starts
      if l:s > l:col
        let l:target = l:s
        break
      endif
    endfor
  else
    for l:s in l:starts
      if l:s < l:col
        let l:target = l:s
      endif
    endfor
  endif
  if l:target > 0
    call cursor(line('.'), l:target)
  endif
endfunction

" 3.3: move to the next/prev note column on any string of the block within the
" current bar (a horizontal playhead). dir +1 (l) or -1 (h). The search is confined
" to the current bar (the notes strictly between the pipes that bound the cursor)
" so l stops at a bar's end instead of skipping to the next bar's note:
"    - l finds the nearest in-bar note to the right; at the last note of the bar
"      (none to its right in the bar) it behaves as a, opening a slot (3.3.2).
"    - h is the mirror; at the first note of the bar it is a no-op (no i append, 3.3.3).
" A plain move lands on the note column. Spec item 4 (lint-on-edit) is out of scope,
" so a move does not run the linter; leftover dashes stay until ||. Off a tab block:
" no-op.
function! songwriter#tab#MoveColumn(dir) abort
  let l:block = songwriter#util#find_tab_block()
  if empty(l:block[2])
    return
  endif
  let l:ln = line(".")
  let l:col = col(".")
  let l:line = getline(l:ln)

     " Current bar on the current line: the last pipe strictly left of the cursor
     " (bar_start) and the first pipe strictly right (bar_end). A note lives strictly
     " between them on every (aligned) string.
  let l:bar_start = 0
  let l:m = match(l:line, "|", 0)
  while l:m >= 0
    if l:m + 1 < l:col
      let l:bar_start = l:m + 1
    else
      break
    endif
    let l:m = match(l:line, "|", l:m + 1)
  endwhile
  let l:bar_end = match(l:line, "|", l:col) + 1        " 1-indexed, strictly right

     " In-bar note columns across every string of the block.
  let l:cols = []
  for l:l in l:block[2]
    for l:s in s:digit_run_starts(l:l)
      if s:in_bar(l:s, l:bar_start, l:bar_end)
        call add(l:cols, l:s)
      endif
    endfor
  endfor

  let l:target = 0
  if a:dir > 0
         " 3.3.1 nearest in-bar note to the right; 3.3.2 append at the bar's end.
    for l:c in l:cols
      if l:c > l:col && (l:target == 0 || l:c < l:target)
        let l:target = l:c
      endif
    endfor
    if l:target > 0
      let l:line_len = len(l:line)
      if l:target > l:line_len
        let l:target = l:line_len
      endif
      call cursor(l:ln, l:target)
    else
      call s:append_note_right(l:block)
    endif
  else
         " h: nearest in-bar note to the left; a no-op at the bar's first note.
    for l:c in l:cols
      if l:c < l:col && (l:target == 0 || l:c > l:target)
        let l:target = l:c
      endif
    endfor
    if l:target > 0
      call cursor(l:ln, l:target)
    endif
  endif
endfunction

" True when 1-indexed column c sits strictly inside the bar bounded by bar_start
" /bar_end (0 means unbounded on that side, which a well-formed tab block does not
" present, but the guard stays permissive).
function! s:in_bar(c, bar_start, bar_end) abort
  if a:bar_start > 0 && a:c <= a:bar_start
    return 0
  endif
  if a:bar_end > 0 && a:c >= a:bar_end
    return 0
  endif
  return 1
endfunction

function! songwriter#tab#TabChord(chord)
  let l:block = songwriter#util#find_tab_block()
  if empty(l:block[2])
    return
  endif
  call append(l:block[0] - 1, repeat(' ', col('.') - 1) . a:chord)
endfunction

" 3.3: enter a note — put the digit in the cell under the cursor on the current
" tab line. On a dash/blank cell the digit REPLACES it (the literal spec);
" on a digit it is appended to its right so two-digit frets (10-19) can be typed
" one digit at a time (the design's de-overlap linting (1.3) then fixes spacing).
" No-op off a tab line, matching the "scoped explicitly to tablature lines"
" guidance in the spec / "Tablatures" note in design.md.
function! songwriter#tab#EnterNote(digit) abort
  let l:digit = a:digit . ''    " accept a digit as a number or a string
  if !songwriter#util#IsTablatureLine(getline('.'))
    return
  endif
  let l:ln = line('.')
  let l:col = col('.')
  let l:line = getline(l:ln)
  let l:ch = (l:col <= len(l:line)) ? l:line[l:col - 1] : ''
  if l:ch =~# '[0-9]'
      " append to the right of the fret digit the cursor is on
    call setline(l:ln, l:line[0 : l:col - 1] . l:digit . l:line[l:col :])
    call cursor(l:ln, l:col + 1)
  else
      " replace the character under the cursor with the digit
    call setline(l:ln, l:line[0 : l:col - 2] . l:digit . l:line[l:col :])
    call cursor(l:ln, l:col)
  endif
endfunction

" 3.1: open room for a new note on every string of the block, landing the cursor
" on the new slot. side +1 ('a') opens the slot to the RIGHT of the current note
" (the last digit run at/left of the cursor); side -1 ('i') mirrors to the LEFT
" of the current note. The slot sits exactly one dash from the current note and
" keeps the following/preceding pipe at a 2-dash gap, so we add as many dashes as
" needed to hold both invariants (the old "always 3 dashes" is obsolete). A line
" with no digit run in the direction asked is a no-op.
function! songwriter#tab#AddNote(side) abort
  let l:block = songwriter#util#find_tab_block()
  if empty(l:block[2])
    return
  endif
  if a:side > 0
    call s:append_note_right(l:block)
  else
    call s:prepend_note_left(l:block)
  endif
endfunction

" End column (1-indexed) of the last digit run starting at or before `col` on
" the line - the "current note" for a rightward insert. 0 when there is none.
function! s:current_note_end(line, col) abort
  let l:e = 0
  for l:a in s:extract_atoms(a:line)
    let l:start = l:a[0] + 1
    if l:start <= a:col && l:a[0] + len(l:a[1]) > l:e
      let l:e = l:a[0] + len(l:a[1])
    endif
  endfor
  return l:e
endfunction

" Start column (1-indexed) of the first digit run starting at or after `col` on
" the line - the "current note" for a leftward insert. 0 when there is none.
function! s:current_note_start(line, col) abort
  let l:s = 0
  for l:a in s:extract_atoms(a:line)
    let l:start = l:a[0] + 1
    if l:start >= a:col && (l:s == 0 || l:start < l:s)
      let l:s = l:start
    endif
  endfor
  return l:s
endfunction

" 'a': place a new-note slot one dash to the right of the current note and push
" the following pipe (or a following note) right to keep its 2-dash / 1-dash gap.
" Inserts N dashes across every string, then lands the cursor on the slot.
function! s:append_note_right(block) abort
  let l:col = col('.')
      " e = block-wide last digit-run end at or before the cursor: the note we
      " open space to the right of. Anchoring on the block (not just this line,
      " which may be empty) keeps an empty string aligned with its neighbours, so
      " a slot is opened even when the last note is on a different line (3.3.2).
  let l:e = 0
  let l:refln = 0
  for l:n in range(len(a:block[2]))
    let l:e2 = s:current_note_end(a:block[2][l:n], l:col)
    if l:e2 > l:e
      let l:e = l:e2
      let l:refln = l:n
    endif
  endfor
  if l:e == 0
    return
  endif
  let l:line = a:block[2][l:refln]
  let l:rest = strpart(l:line, l:e)        " chars strictly right of the note
  let l:m = match(l:rest, '[0-9|]')
  let l:N = 0
  if l:m >= 0
    let l:b = l:e + 1 + l:m                " column of the next note / pipe
        " 1 dash + the slot, then 2 dashes before the pipe (or 1 before a note).
    let l:want = (l:rest[l:m] ==# '|') ? l:e + 5 : l:e + 4
    let l:N = l:want - l:b
    if l:N < 0
      let l:N = 0
    endif
  endif
  for l:i in range(len(a:block[2]))
    let l:l = a:block[2][l:i]
    while len(l:l) < l:e
      let l:l .= '-'
    endwhile
    call setline(a:block[0] + l:i, strpart(l:l, 0, l:e) . repeat('-', l:N) . strpart(l:l, l:e))
  endfor
  call cursor(line('.'), l:e + 2)          " slot, one dash from the note
endfunction

" 'i': mirror of s:append_note_right. Opens the slot to the LEFT of the current
" note and pushes the note (and everything after) right to keep the preceding pipe
" 2 dashes away. Inserts N dashes across every string, then lands on the slot.
function! s:prepend_note_left(block) abort
  let l:col = col('.')
      " s = block-wide first digit-run start at or after the cursor: the note we
      " open space to the left of. Anchoring on the block (not just this line,
      " which may be empty) keeps an empty string aligned with its neighbours.
  let l:s = 0
  let l:refln = 0
  for l:n in range(len(a:block[2]))
    let l:s2 = s:current_note_start(a:block[2][l:n], l:col)
    if l:s2 > 0 && (l:s == 0 || l:s2 < l:s)
      let l:s = l:s2
      let l:refln = l:n
    endif
  endfor
  if l:s == 0
    return
  endif
  let l:line = a:block[2][l:refln]
  let l:pcol = 0
  for l:i in range(l:s - 2, 1, -1)
    if l:line[l:i - 1] ==# '|'
      let l:pcol = l:i
      break
    endif
  endfor
      " 2 dashes after the pipe + the slot: keep the note 5 columns right of it.
  let l:N = (l:pcol == 0) ? 0 : l:pcol + 5 - l:s
  if l:N < 0
    let l:N = 0
  endif
  for l:i in range(len(a:block[2]))
    let l:l = a:block[2][l:i]
    while len(l:l) < l:s - 1
      let l:l .= '-'
    endwhile
    call setline(a:block[0] + l:i, strpart(l:l, 0, l:s - 1) . repeat('-', l:N) . strpart(l:l, l:s - 1))
  endfor
  call cursor(line('.'), l:s + l:N - 2)        " slot, one dash left of the note
endfunction



