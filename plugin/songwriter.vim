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
" Parse a block of tab lines into [regions, P, NL]. Each region is a per-line
" list of bar-region strings (the content between pipes); the string-name prefix
" and anything after the final pipe are dropped. NL is the number of lines.
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

" Fixed-point relax one bar's atoms (list of [lin, c0, num]) to a list of note
" dicts carrying their final output column `start`. `mincol` is the bar's minimum
" atom column, so a note starts two dashes after the bar's left pipe
" (c0 - mincol + 2). Two invariants are enforced each pass:
"   same-string     : keep each string's original relative note spacing, so
"                    sequential notes are never collapsed onto one column.
"   cross-string    : (spec 1.3) when a note starts strictly after a note on a
"                    different line but still inside that note's column span, the
"                    two numbers overlap without being aligned, so push the later
"                    one right so exactly one dash separates them.
" A single-column note can never satisfy "start < other.start AND start <=
" other.end", so aligned single digits are always left untouched.
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

" Render one bar's relaxed note dicts into a list of NL strings (one per line),
" each long enough that the pipes line up. Bar width is the content span plus two
" trailing dashes; a string with no note in this bar is that many dashes.
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

" Lint a block of tab lines: align bar pipes across all strings and normalise
" dashes so that each bar's first note sits 2 dashes after the left pipe and its
" last note 2 dashes before the right pipe. A digit that would overlap a note on
" another string without being aligned is pushed right (spec 1.3).
"
" A bar is a fixed-width grid column; the linter never moves a note to a column
" already occupied by a note on the same string - that would destroy the note
" sequence and could merge two distinct notes into one.
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

" === Chord model ===

" Chromatic scale (sharp spelling) and flat-to-sharp aliases, shared by transpose
" and the quality helpers.
let s:Chromatic = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
let s:FlatToSharp = {'Eb': 'D#', 'Gb': 'F#', 'Ab': 'G#', 'Bb': 'A#', 'Db': 'C#'}
" A chord root: a note letter with an optional sharp/flat accidental.
let s:RootPat = '[A-G][#b]\='

" Parse a chord token into {root, quality, name}. `root` is the raw spelling as
" found in the text (a flat stays a flat); `quality` is everything after it.
" When there is no root letter at all, root and quality are empty strings.
function! s:chord_parse(name)
  let l:root = matchstr(a:name, s:RootPat)
  let l:quality = (l:root ==# '') ? '' : strpart(a:name, len(l:root))
  return {'name': a:name, 'root': l:root, 'quality': l:quality}
endfunction

" Build a chord token from a (raw-spelling) root and a quality string.
function! s:chord_build(root, quality)
  return a:root . a:quality
endfunction

" Transpose the root of a parsed chord by `semitones`, preserving the quality.
" Flats in the root are normalized to sharps in the result, since s:Chromatic
" has only one spelling per pitch.
function! s:chord_transpose(parsed, semitones)
  let l:root = a:parsed['root']
  if l:root ==# ''
    return a:parsed['name']
  endif
  if has_key(s:FlatToSharp, l:root)
    let l:root = s:FlatToSharp[l:root]
  endif
  let l:idx = index(s:Chromatic, l:root)
  if l:idx < 0
    return a:parsed['name']
  endif
  let l:new_idx = (l:idx + a:semitones) % 12
  if l:new_idx < 0
    let l:new_idx += 12
  endif
  return s:Chromatic[l:new_idx] . a:parsed['quality']
endfunction

" Splice a new chord token into a line, replacing the inclusive [start, end]
" bounds (0-indexed) returned by s:find_chord_at_cursor.
function! s:splice_chord(line, bounds, newc)
  return strpart(a:line, 0, a:bounds[0]) . a:newc . strpart(a:line, a:bounds[1] + 1)
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
    " Transpose the chord under the cursor up (1) or down (-1) chromatically.
  let l:line = getline('.')
  let l:result = s:find_chord_at_cursor(l:line, col('.') - 1)
  if empty(l:result[2])
    return
  endif
  let l:new = s:chord_transpose(s:chord_parse(l:result[2]), a:direction)
  if l:new ==# l:result[2]
    return
  endif
  call setline('.', s:splice_chord(l:line, l:result, l:new))
endfunction

function! SongwriterChordAbove(chord)
   " Insert chord above cursor with alignment for lyrics
  let l:col = col('.')
  let l:spaces = repeat(' ', l:col - 1)
  call append(line('.') - 1, l:spaces . a:chord)
endfunction

function! SongwriterChordQuality(quality)
    " Change the quality of the chord under the cursor (e.g. Am7 -> Amaj7).
  let l:line = getline('.')
  let l:result = s:find_chord_at_cursor(l:line, col('.') - 1)
  if empty(l:result[2])
    return
  endif
  let l:root = s:chord_parse(l:result[2])['root']
  if empty(l:root)
    return
  endif
  call setline('.', s:splice_chord(l:line, l:result, s:chord_build(l:root, a:quality)))
endfunction

function! SongwriterToggleMinorMajor()
    " Toggle the chord under the cursor between major and minor (A <-> Am),
    " leaving any other quality (7, m7, ...) otherwise intact.
  let l:line = getline('.')
  let l:result = s:find_chord_at_cursor(l:line, col('.') - 1)
  if empty(l:result[2])
    return
  endif
  let l:parsed = s:chord_parse(l:result[2])
  if empty(l:parsed['root'])
    return
  endif
  let l:q = l:parsed['quality']
  let l:new_q = (l:q[0:0] ==# 'm') ? l:q[1:] : ('m' . l:q)
  call setline('.', s:splice_chord(l:line, l:result, s:chord_build(l:parsed['root'], l:new_q)))
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
