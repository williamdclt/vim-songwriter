" autoload/songwriter/chord.vim - chord parsing / transposition and the
" chord-editing operations (transpose, quality, minor/major toggle).

" === Chord model (constants + private helpers) ===

" {name, root, quality, bass} for a whole chord token, or {} when the token is
" not a chord (grammar ParseChord). `bass` is '' for a chord without `/bass`.
function! s:chord_parse(name) abort
  let l:m = songwriter#grammar#ParseChord(a:name)
  if empty(l:m)
    return {}
  endif
  return {'name': a:name, 'root': l:m[0], 'quality': l:m[1], 'bass': l:m[2]}
endfunction
function! s:chord_build(root, quality, bass) abort
  return a:root . a:quality . (empty(a:bass) ? '' : '/' . a:bass)
endfunction
" `root` moved by `semitones`, spelled with sharps.
function! s:root_transpose(root, semitones) abort
  let l:pc = songwriter#pitch#Class(a:root)
  return l:pc < 0 ? a:root : songwriter#pitch#Name(l:pc + a:semitones)
endfunction
" The chord with its root and bass moved by `semitones`.
function! s:chord_transpose(parsed, semitones) abort
  return s:chord_build(
        \ s:root_transpose(a:parsed.root, a:semitones),
        \ a:parsed.quality,
        \ empty(a:parsed.bass) ? '' : s:root_transpose(a:parsed.bass, a:semitones))
endfunction
function! s:splice_chord(line, found, newc) abort
  return strpart(a:line, 0, a:found.start) . a:newc . strpart(a:line, a:found.end + 1)
endfunction
" The chord under 0-indexed column `col` of `line`: {'start', 'end' (0-indexed,
" inclusive), 'chord' (parsed)}, or {} when the token of chord characters under
" the cursor is not a whole chord. Tab lines hold no chords.
function! s:find_chord_at_cursor(line, col) abort
  if songwriter#grammar#IsTabLine(a:line)
    return {}
  endif
  let l:tokchar = songwriter#grammar#ChordTokenChar()
  if a:col >= len(a:line) || a:line[a:col] !~# l:tokchar
    return {}
  endif
  let l:start = a:col
  while l:start > 0 && a:line[l:start - 1] =~# l:tokchar
    let l:start -= 1
  endwhile
  let l:end = a:col
  while l:end < len(a:line) - 1 && a:line[l:end + 1] =~# l:tokchar
    let l:end += 1
  endwhile
  let l:parsed = s:chord_parse(strpart(a:line, l:start, l:end - l:start + 1))
  return empty(l:parsed) ? {} : {'start': l:start, 'end': l:end, 'chord': l:parsed}
endfunction

" === Public chord operations ===

" Transpose the chord under the cursor by `semitones` (spec [Chords][[Editing]],
" <Ctrl-A>/<Ctrl-X> with their count). Off a chord, including on a tab line,
" fall back to Vim's own <Ctrl-A>/<Ctrl-X> on the next number of the line.
function! songwriter#chord#TransposeChord(semitones) abort
  let l:n = str2nr(a:semitones)
  let l:line = getline('.')
  let l:found = s:find_chord_at_cursor(l:line, col('.') - 1)
  if empty(l:found)
    call s:native_increment(l:n, songwriter#grammar#IsTabLine(l:line))
    return
  endif
  call setline('.', s:splice_chord(l:line, l:found, s:chord_transpose(l:found.chord, l:n)))
endfunction

" Vim's own <Ctrl-A> (n > 0) / <Ctrl-X> (n < 0), |n| times. On a tab line the
" dashes are not minus signs (`--3` is fret 3, not -3), so numbers are read as
" unsigned there.
function! s:native_increment(n, unsigned) abort
  if a:n == 0
    return
  endif
  let l:saved = &l:nrformats
  if a:unsigned
    setlocal nrformats+=unsigned
  endif
  try
    execute 'normal! ' . abs(a:n) . (a:n > 0 ? "\<C-A>" : "\<C-X>")
  finally
    let &l:nrformats = l:saved
  endtry
endfunction

function! songwriter#chord#ChordAbove(chord) abort
   " Insert chord above cursor with alignment for lyrics
  let l:col = col('.')
  let l:spaces = repeat(' ', l:col - 1)
  call append(line('.') - 1, l:spaces . a:chord)
endfunction

" Change the quality of the chord under the cursor (e.g. Am7 -> Amaj7), keeping
" its root and bass. No-op off a chord.
function! songwriter#chord#ChordQuality(quality) abort
  let l:line = getline('.')
  let l:found = s:find_chord_at_cursor(l:line, col('.') - 1)
  if empty(l:found)
    return
  endif
  let l:c = l:found.chord
  call setline('.', s:splice_chord(l:line, l:found, s:chord_build(l:c.root, a:quality, l:c.bass)))
endfunction

" Toggle the chord under the cursor between major and minor (A <-> Am, D/F# <->
" Dm/F#), leaving the rest of the quality (7, m7 -> 7, maj7 -> mmaj7) and the
" bass intact. No-op off a chord.
function! songwriter#chord#ToggleMinorMajor() abort
  let l:line = getline('.')
  let l:found = s:find_chord_at_cursor(l:line, col('.') - 1)
  if empty(l:found)
    return
  endif
  let l:c = l:found.chord
  let l:minor = matchstr(l:c.quality, '^\%(min\|m\%(aj\)\@!\)')
  let l:q = empty(l:minor) ? 'm' . l:c.quality : strpart(l:c.quality, len(l:minor))
  call setline('.', s:splice_chord(l:line, l:found, s:chord_build(l:c.root, l:q, l:c.bass)))
endfunction
