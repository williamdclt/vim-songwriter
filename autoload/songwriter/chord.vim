" autoload/songwriter/chord.vim - chord parsing / transposition and the
" chord-editing operations (transpose, quality, minor/major toggle).

" === Chord model (constants + private helpers) ===

let s:Chromatic = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
let s:FlatToSharp = {'Eb': 'D#', 'Gb': 'F#', 'Ab': 'G#', 'Bb': 'A#', 'Db': 'C#'}
" A chord root: a note letter with an optional sharp/flat accidental.
let s:RootPat = '[A-G][#b]\='
function! s:chord_parse(name)
  let l:root = matchstr(a:name, s:RootPat)
  let l:quality = (l:root ==# '') ? '' : strpart(a:name, len(l:root))
  return {'name': a:name, 'root': l:root, 'quality': l:quality}
endfunction
function! s:chord_build(root, quality)
  return a:root . a:quality
endfunction
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

" === Public chord operations ===

function! songwriter#chord#TransposeChord(direction)
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

function! songwriter#chord#ChordAbove(chord)
   " Insert chord above cursor with alignment for lyrics
  let l:col = col('.')
  let l:spaces = repeat(' ', l:col - 1)
  call append(line('.') - 1, l:spaces . a:chord)
endfunction

function! songwriter#chord#ChordQuality(quality)
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

function! songwriter#chord#ToggleMinorMajor()
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
