" songwriter.vim - Vim plugin for guitar tablatures, chords, lyrics, notes
" Maintainer:
" License: MIT

if exists('g:loaded_songwriter')
  finish
endif
let g:loaded_songwriter = 1

" A tab line starts with a string name immediately followed by a bar pipe.
" This is the single source of truth for "what is a tab line" (see design.md).
let s:TabLinePat = '^\a[|]'

" Return [start, end, lines] for the contiguous block of tab lines surrounding
" the cursor, or [0, 0, []] when the cursor is not on a tab line. Callers guard
" with `if empty(l:block[2]) | return | endif` and use l:block[0] (the block's
" start line) and l:block[2] (its lines) as needed.
function! s:find_tab_block()
  if getline('.') !~# s:TabLinePat
    return [0, 0, []]
  endif
  let l:start = line('.')
  while l:start > 1 && (getline(l:start - 1) =~# s:TabLinePat)
    let l:start -= 1
  endwhile
  let l:end = line('.')
  while l:end < line('$') && (getline(l:end + 1) =~# s:TabLinePat)
    let l:end += 1
  endwhile
  let l:lines = []
  for l:ln in range(l:start, l:end)
    call add(l:lines, getline(l:ln))
  endfor
  return [l:start, l:end, l:lines]
endfunction

" Insert one character at the cursor column on every string of the tab block,
" padding short lines with dashes first. The char lands *after* the character at
" the cursor column (i.e. col+1 in 1-indexed terms), matching the original
" AddBar/AddDash behaviour. Returns 0 when the cursor is not on a tab line.
function! s:insert_char_at_col(char)
  let l:block = s:find_tab_block()
  if empty(l:block[2])
    return 0
  endif
  let l:col = col('.')
  for l:i in range(len(l:block[2]))
    let l:line = l:block[2][l:i]
    while len(l:line) < l:col
      let l:line .= '-'
    endwhile
    call setline(l:block[0] + l:i, strpart(l:line, 0, l:col) . a:char . strpart(l:line, l:col))
  endfor
  return 1
endfunction

function! SongwriterAddDashes()
  let l:block = s:find_tab_block()
  if empty(l:block[2])
    return
  endif
  for l:i in range(len(l:block[2]))
    call setline(l:block[0] + l:i, l:block[2][l:i] . '--')
  endfor
endfunction

function! SongwriterAddDash()
  call s:insert_char_at_col('-')
endfunction

function! SongwriterAddBar()
  call s:insert_char_at_col('|')
endfunction

" Return atoms (maximal runs of digits) of a bar-region string as a list of
" [c0, num] where c0 is the 0-based column of the first digit.
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

" Lint a block of tab lines: align bar pipes across all strings and normalise
" dashes so that each bar's first note sits 2 dashes after the left pipe and
" its last note 2 dashes before the right pipe. A digit that would overlap a
" note on another string without being aligned is pushed right (spec 1.3).
"
function! s:lint_block(lines)
   " Parse each line into a list of bar-region strings (content between pipes).
   " split on '|' keeps empty middle fields so regions line up across strings.
  let l:regions = []
  let l:P = 0
  for l:ln in a:lines
    let l:parts = split(l:ln, '[|]', 1)
    call remove(l:parts, 0)            " drop the string-name prefix
    call remove(l:parts, len(l:parts) - 1) " drop anything after the final pipe
    call add(l:regions, l:parts)
    if len(l:parts) > l:P
      let l:P = len(l:parts)
    endif
  endfor

  let l:NL = len(a:lines)

   " For each bar index, collect the digit atoms ([lin, c0, num]) across all
   " lines, the bar's min column, and whether it contains any note at all.
  let l:bar_atoms = []
  let l:mincol = []
  let l:has = []
  for l:j in range(0, l:P - 1)
    let l:lst = []
    let l:mn = 0
    let l:mnset = 0
    let l:h = 0
    for l:lin in range(0, l:NL - 1)
      if l:j >= len(l:regions[l:lin])
        continue
      endif
      for l:at in s:extract_atoms(l:regions[l:lin][l:j])
        call add(l:lst, [l:lin, l:at[0], l:at[1]])
        let l:h = 1
        if !l:mnset || l:at[0] < l:mn
          let l:mn = l:at[0]
          let l:mnset = 1
        endif
      endfor
    endfor
    call add(l:bar_atoms, l:lst)
    call add(l:mincol, l:mn)
    call add(l:has, l:h)
  endfor

   " Rebuild each line, one bar at a time.
  let l:lineparts = []
  for l:i in range(0, l:NL - 1)
    call add(l:lineparts, [])
  endfor
  for l:j in range(0, l:P - 1)
    if l:has[l:j] == 0
         " Empty bar -> exactly two dashes on every string.
      for l:lin in range(0, l:NL - 1)
        call add(l:lineparts[l:lin], '--')
      endfor
      continue
    endif

     " Working atoms with a natural output column of c0 - mincol + 2: a note
     " sits two dashes after the bar's left pipe. len is the number of digits.
    let l:work = []
    for l:a in l:bar_atoms[l:j]
      call add(l:work, {
             \ 'lin': l:a[0],
             \ 'c0': l:a[1],
             \ 'num': l:a[2],
             \ 'len': len(l:a[2]),
             \ 'start': l:a[1] - l:mincol[l:j] + 2})
    endfor

     " Fixed-point relaxation enforcing two invariants:
     "   same-string   : keep each string's original relative note spacing, so
     "                  sequential notes are never collapsed onto one column.
     "   cross-string : (spec 1.3) when a note starts strictly after a note on a
     "                  different line but still inside that note's column span,
     "                  the two numbers overlap without being aligned, so push
     "                  the later one right so exactly one dash separates them.
     " A single-column note can never satisfy "start < other.start AND start <=
     " other.end", so aligned single digits are always left untouched.
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

     " Bar width: content columns [2 .. maxend] plus two trailing dashes.
    let l:maxend = 2
    for l:a in l:work
      let l:e = l:a['start'] + l:a['len'] - 1
      if l:e > l:maxend
        let l:maxend = l:e
      endif
    endfor
    let l:W = l:maxend + 3

     " Group the final atoms by line and render each string's region.
    let l:bylin = {}
    for l:a in l:work
      if !has_key(l:bylin, l:a['lin'])
        let l:bylin[l:a['lin']] = []
      endif
      call add(l:bylin[l:a['lin']], l:a)
    endfor
    for l:lin in range(0, l:NL - 1)
      if has_key(l:bylin, l:lin)
        let l:arr = []
        for l:idx in range(0, l:W - 1)
          call add(l:arr, '-')
        endfor
        for l:a in l:bylin[l:lin]
          for l:k in range(0, l:a['len'] - 1)
            let l:arr[l:a['start'] + l:k] = l:a['num'][l:k]
          endfor
        endfor
        call add(l:lineparts[l:lin], join(l:arr, ''))
      else
           " String with no note in this bar -> padded so its pipes line up.
        call add(l:lineparts[l:lin], repeat('-', l:W))
      endif
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

function! SongwriterLint()
  let l:block = s:find_tab_block()
  if empty(l:block[2])
    return
  endif
  let l:newlines = s:lint_block(l:block[2])
  for l:i in range(len(l:newlines))
    call setline(l:block[0] + l:i, l:newlines[l:i])
  endfor
endfunction

function! SongwriterTabChord(chord)
  let l:block = s:find_tab_block()
  if empty(l:block[2])
    return
  endif
  call append(l:block[0] - 1, repeat(' ', col('.') - 1) . a:chord)
endfunction

function! s:chromatic_index(note)
   " Returns 0-11 for note name. Handles sharps and flats.
  let l:flat_map = {'Eb': 'D#', 'Gb': 'F#', 'Ab': 'G#', 'Bb': 'A#', 'Db': 'C#'}
  let l:n = a:note
  if has_key(l:flat_map, l:n)
    let l:n = l:flat_map[l:n]
  endif
  let l:chromatic = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
  let l:idx = index(l:chromatic, l:n)
  if l:idx < 0
    return -1
  endif
  return l:idx
endfunction

function! s:transpose_chord_name(chord_name, semitones)
   " Parse chord name into root + quality and transpose root by semitones
   " Handles: C, C#, Db, D, D#, Eb, etc. + optional quality (maj7, m7, 7, sus4, dim, aug, m, maj, etc.)
  let l:chromatic = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
  let l:name = a:chord_name

   " Match root (1-2 chars: letter + optional # or b)
  let l:root_pat = '^\(\<[A-G][#b]\=\)'
  if l:name =~# l:root_pat
    let l:root = matchstr(l:name, '[A-G][#b]\=')
    let l:quality = strpart(l:name, len(l:root))
  else
    return l:name
  endif

  let l:idx = s:chromatic_index(l:root)
  if l:idx < 0
    return l:name
  endif

   " Wrap around with proper modulo for negative numbers
  let l:new_idx = (l:idx + a:semitones) % 12
  if l:new_idx < 0
    let l:new_idx += 12
  endif

  return l:chromatic[l:new_idx] . l:quality
endfunction

function! s:find_chord_at_cursor(line, col)
   " Find chord name at cursor column (0-indexed) in line string
   " Returns list [start, end, chord] or [-1, -1, '']
  let l:c = a:col
  let l:ln = a:line
  let l:lnlen = len(l:ln)

   " Check if cursor is on a chord char
  if l:c >= l:lnlen || !(l:ln[l:c] =~# '[A-Ga-g]')
     " Cursor might be on quality part (#, b, m, 7, etc.) — scan left to find root
    let l:scan = l:c
    while l:scan > 0
      let l:scan -= 1
      if l:ln[l:scan] =~# '[A-Ga-g]'
        let l:c = l:scan
        break
      endif
       " If we hit a non-chord char before finding root, no chord here
      if !(l:ln[l:scan] =~# '[A-Za-z0-9#b]')
        return [-1, -1, '']
      endif
    endwhile
     " Check if we found a root at start of string
    if l:c == 0 && !(l:ln[0] =~# '[A-Ga-g]')
      return [-1, -1, '']
    endif
  endif

   " Now l:c points to root letter. Find chord start (scan left for word boundary)
  let l:start = l:c
  while l:start > 0 && l:ln[l:start - 1] =~# '[A-Za-z0-9#b]'
    let l:start -= 1
  endwhile

   " Find chord end (scan right for word boundary)
  let l:end = l:c
  while l:end < l:lnlen - 1 && l:ln[l:end + 1] =~# '[A-Za-z0-9#b]'
    let l:end += 1
  endwhile

  let l:chord = strpart(l:ln, l:start, l:end - l:start + 1)
  return [l:start, l:end, l:chord]
endfunction

function! SongwriterTransposeChord(direction)
   " Transpose chord under cursor up (1) or down (-1) chromatically
  let l:line = getline('.')
  let l:c = col('.') - 1

  let l:result = s:find_chord_at_cursor(l:line, l:c)
  let l:start = l:result[0]
  let l:end = l:result[1]
  let l:chord = l:result[2]

  if empty(l:chord)
    return
  endif

  let l:new_chord = s:transpose_chord_name(l:chord, a:direction)
  if l:new_chord ==# l:chord
    return
  endif

   " Replace chord in line
  let l:new_line = strpart(l:line, 0, l:start) . l:new_chord . strpart(l:line, l:end + 1)
  call setline('.', l:new_line)
endfunction

function! SongwriterChordAbove(chord)
   " Insert chord above cursor with alignment for lyrics
  let l:col = col('.')
  let l:spaces = repeat(' ', l:col - 1)
  call append(line('.') - 1, l:spaces . a:chord)
endfunction

function! SongwriterChordQuality(quality)
   " Change quality of chord under cursor (e.g. Am7 -> Amaj7)
  let l:line = getline('.')
  let l:c = col('.') - 1

  let l:result = s:find_chord_at_cursor(l:line, l:c)
  let l:start = l:result[0]
  let l:end = l:result[1]
  let l:chord = l:result[2]

  if empty(l:chord)
    return
  endif

  let l:root = matchstr(l:chord, '[A-G][#b]\=')
  if empty(l:root)
    return
  endif

  let l:new_chord = l:root . a:quality
  let l:new_line = strpart(l:line, 0, l:start) . l:new_chord . strpart(l:line, l:end + 1)
  call setline('.', l:new_line)
endfunction

function! SongwriterToggleMinorMajor()
   " Toggle chord between major and minor (A <-> Am)
  let l:line = getline('.')
  let l:c = col('.') - 1

  let l:result = s:find_chord_at_cursor(l:line, l:c)
  let l:start = l:result[0]
  let l:end = l:result[1]
  let l:chord = l:result[2]

  if empty(l:chord)
    return
  endif

  let l:root = matchstr(l:chord, '[A-G][#b]\=')
  if empty(l:root)
    return
  endif

  let l:quality = strpart(l:chord, len(l:root))
  if strpart(l:quality, 0, 1) ==# 'm'
    let l:new_quality = strpart(l:quality, 1)
  else
    let l:new_quality = 'm' . l:quality
  endif

  let l:new_chord = l:root . l:new_quality
  let l:new_line = strpart(l:line, 0, l:start) . l:new_chord . strpart(l:line, l:end + 1)
  call setline('.', l:new_line)
endfunction

" === Ex commands ===

command! -nargs=0 SongwriterAddBar call SongwriterAddBar()
command! -nargs=0 SongwriterAddDash call SongwriterAddDash()
command! -nargs=0 SongwriterAddDashes call SongwriterAddDashes()
command! -nargs=0 SongwriterLint call SongwriterLint()
command! -nargs=1 SongwriterTabChord call SongwriterTabChord(<q-args>)
command! -nargs=1 SongwriterChordAbove call SongwriterChordAbove(<q-args>)
command! -nargs=1 SongwriterChordQuality call SongwriterChordQuality(<q-args>)
command! -nargs=1 SongwriterTransposeChord call SongwriterTransposeChord(<q-args>)
command! -nargs=0 SongwriterToggleMinorMajor call SongwriterToggleMinorMajor()
