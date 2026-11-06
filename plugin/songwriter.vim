" songwriter.vim - Vim plugin for guitar tablatures, chords, lyrics, notes
" Maintainer:
" License: MIT

if exists('g:loaded_songwriter')
  finish
endif
let g:loaded_songwriter = 1

function! SongwriterAddDashes()
  " A tab line: starts with a letter immediately followed by |
  let l:tab_pat = '^\a[|]'

  " Check if current line is a tab line
  if !(getline('.') =~# tab_pat)
    return
  endif

  " Find start of contiguous tab block (scan up)
  let l:start = line('.')
  while l:start > 1 && (getline(l:start - 1) =~# tab_pat)
    let l:start -= 1
  endwhile

  " Find end of contiguous tab block (scan down)
  let l:end = line('.')
  while l:end < line('$') && (getline(l:end + 1) =~# tab_pat)
    let l:end += 1
  endwhile

  " Append -- to each tab line in the block
  for l:ln in range(l:start, l:end)
    let l:line = getline(l:ln)
    call setline(l:ln, l:line . '--')
  endfor
endfunction

function! SongwriterAddBar()
  " A tab line: starts with a letter immediately followed by |
  let l:tab_pat = '^\a[|]'

  " Check if current line is a tab line
  if !(getline('.') =~# tab_pat)
    return
  endif

  " Find start of contiguous tab block (scan up)
  let l:start = line('.')
  while l:start > 1 && (getline(l:start - 1) =~# tab_pat)
    let l:start -= 1
  endwhile

  " Find end of contiguous tab block (scan down)
  let l:end = line('.')
  while l:end < line('$') && (getline(l:end + 1) =~# tab_pat)
    let l:end += 1
  endwhile

  " Get cursor column (1-indexed)
  let l:col = col('.')

  " Insert | at cursor column on each tab line in the block
  for l:ln in range(l:start, l:end)
    let l:line = getline(l:ln)
    " Ensure line is long enough; pad with dashes if needed
    while len(l:line) < l:col
      let l:line .= '-'
    endwhile
    " Insert | at cursor column (col is 1-indexed, string is 0-indexed)
    let l:newline = strpart(l:line, 0, l:col) . '|' . strpart(l:line, l:col)
    call setline(l:ln, l:newline)
  endfor
endfunction

" Lint a block of tab lines: align bar pipes across all strings and normalise
" dashes so that each bar's first note sits 2 dashes after the left pipe and
" its last note 2 dashes before the right pipe. Note order is preserved.
"
function! s:lint_block(lines)
  " Parse each line into letter + list of bar-region strings.
  " A bar region is the content strictly between two consecutive pipes.
  " split on '|' keeps empty middle fields so regions line up.
  let l:regions = []
  let l:P = 0
  for l:ln in a:lines
    let l:parts = split(l:ln, '[|]', 1)
    call remove(l:parts, 0)   " drop the string-name prefix
    call remove(l:parts, len(l:parts) - 1)  " drop anything after the final pipe
    call add(l:regions, l:parts)
    if len(l:parts) > l:P
      let l:P = len(l:parts)
    endif
  endfor

  " For each bar index, find min/max note columns across all lines and whether
  " it contains any note at all.
  let l:has = []
  let l:mincol = []
  let l:maxcol = []
  for l:j in range(0, l:P - 1)
    let l:h = 0
    let l:mn = 0
    let l:mx = 0
    for l:reg in l:regions
      if l:j >= len(l:reg)
        continue
      endif
      let l:r = l:reg[l:j]
      let l:i = 0
      while l:i < len(l:r)
        let l:c = l:r[l:i]
        if l:c !=# '-'
          if l:h == 0
           " first note seen in this bar - seed min and max columns
            let l:mn = l:i
            let l:mx = l:i
            let l:h = 1
          else
           " scan is per-line, so take a true min and max column
            if l:i < l:mn
              let l:mn = l:i
            endif
            if l:i > l:mx
              let l:mx = l:i
            endif
          endif
        endif
        let l:i += 1
      endwhile
    endfor
    call add(l:has, l:h)
    call add(l:mincol, l:mn)
    call add(l:maxcol, l:mx)
  endfor

  " Rebuild each line.
  let l:out = []
  for l:k in range(0, len(a:lines) - 1)
    let l:letter = strpart(a:lines[l:k], 0, 1)
    let l:reg = l:regions[l:k]
    let l:newregs = []
    for l:j in range(0, l:P - 1)
      if l:has[l:j] == 0
         " Empty bar -> exactly two dashes.
        call add(l:newregs, '--')
        continue
      endif
      let l:r = (l:j < len(l:reg)) ? l:reg[l:j] : ''
      let l:W = l:maxcol[l:j] - l:mincol[l:j] + 5
      let l:res = repeat('-', l:W)
      let l:i = 0
      while l:i < len(l:r)
        let l:c = l:r[l:i]
        if l:c !=# '-'
          let l:pos = l:i - l:mincol[l:j] + 2
          let l:res = strpart(l:res, 0, l:pos) . l:c . strpart(l:res, l:pos + 1)
        endif
        let l:i += 1
      endwhile
      call add(l:newregs, l:res)
    endfor
    call add(l:out, l:letter . '|' . join(l:newregs, '|') . '|')
  endfor
  return l:out
endfunction

function! SongwriterLint()
  " A tab line: starts with a letter immediately followed by |
  let l:tab_pat = '^\a[|]'

  if getline('.') !~# l:tab_pat
    return
  endif

  " Find the contiguous tab block around the cursor.
  let l:start = line('.')
  while l:start > 1 && getline(l:start - 1) =~# l:tab_pat
    let l:start -= 1
  endwhile
  let l:end = line('.')
  while l:end < line('$') && getline(l:end + 1) =~# l:tab_pat
    let l:end += 1
  endwhile

  let l:lines = []
  for l:ln in range(l:start, l:end)
    call add(l:lines, getline(l:ln))
  endfor

  let l:newlines = s:lint_block(l:lines)
  for l:i in range(len(l:newlines))
    call setline(l:start + l:i, l:newlines[l:i])
  endfor
endfunction

function! SongwriterTabChord(chord)
  " A tab line: starts with a letter immediately followed by |
  let l:tab_pat = '^\a[|]'

  " Check if current line is a tab line
  if !(getline('.') =~# tab_pat)
    return
  endif

  " Find start of contiguous tab block (scan up)
  let l:start = line('.')
  while l:start > 1 && (getline(l:start - 1) =~# tab_pat)
    let l:start -= 1
  endwhile

  " Get cursor column (1-indexed)
  let l:col = col('.')

  " Build chord line: spaces to align chord start at cursor column, then chord name
  let l:spaces = repeat(' ', l:col - 1)
  let l:chord_line = l:spaces . a:chord

  " Insert chord line above the tab block
  call append(l:start - 1, l:chord_line)
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
command! -nargs=0 SongwriterAddDashes call SongwriterAddDashes()
command! -nargs=0 SongwriterLint call SongwriterLint()
command! -nargs=1 SongwriterTabChord call SongwriterTabChord(<q-args>)
command! -nargs=1 SongwriterChordAbove call SongwriterChordAbove(<q-args>)
command! -nargs=1 SongwriterChordQuality call SongwriterChordQuality(<q-args>)
command! -nargs=1 SongwriterTransposeChord call SongwriterTransposeChord(<q-args>)
command! -nargs=0 SongwriterToggleMinorMajor call SongwriterToggleMinorMajor()
