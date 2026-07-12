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
