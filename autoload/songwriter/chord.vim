" autoload/songwriter/chord.vim - chord parsing / transposition and the
" chord-editing operations (transpose, quality, minor/major toggle).

" === Chord model (constants + private helpers) ===

" The column Vim reports and accepts for "to the end of the line".
let s:eol = 2147483647

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
" Every whole chord among the tokens of chord characters on `line`, left to
" right: [{'start', 'end' (0-indexed, inclusive), 'chord' (parsed)}]. Tab lines
" hold no chords.
function! s:chord_tokens(line) abort
  if songwriter#grammar#IsTabLine(a:line)
    return []
  endif
  let l:tokens = []
  let l:pat = songwriter#grammar#ChordTokenChar() . '\+'
  let l:start = match(a:line, l:pat)
  while l:start >= 0
    let l:end = matchend(a:line, l:pat, l:start) - 1
    let l:parsed = s:chord_parse(strpart(a:line, l:start, l:end - l:start + 1))
    if !empty(l:parsed)
      call add(l:tokens, {'start': l:start, 'end': l:end, 'chord': l:parsed})
    endif
    let l:start = match(a:line, l:pat, l:end + 1)
  endwhile
  return l:tokens
endfunction

" The chord token over 0-indexed column `col` of `line`, or {}.
function! s:find_chord_at_cursor(line, col) abort
  for l:token in s:chord_tokens(a:line)
    if l:token.start <= a:col && a:col <= l:token.end
      return l:token
    endif
  endfor
  return {}
endfunction

" Replace the chord under the cursor by Transform(parsed chord). Returns whether
" there was one.
function! s:edit_at_cursor(Transform) abort
  let l:line = getline('.')
  let l:found = s:find_chord_at_cursor(l:line, col('.') - 1)
  if empty(l:found)
    return 0
  endif
  call setline('.', s:splice_chord(l:line, l:found, a:Transform(l:found.chord)))
  return 1
endfunction

" === Public chord operations ===

" Transpose the chord under the cursor by `semitones` (spec [Chords][[Editing]],
" <Ctrl-A>/<Ctrl-X> with their count). On a tab line in tablature mode, change
" a fret instead (spec [Tablature][[Editing]] 11). Off a chord, fall back to
" Vim's own <Ctrl-A>/<Ctrl-X> on the next number of the line.
function! songwriter#chord#TransposeChord(semitones) abort
  let l:n = str2nr(a:semitones)
  if songwriter#keys#InTabMode() && songwriter#grammar#IsTabLine(getline('.'))
    call songwriter#tab#frets#Increment(l:n)
  elseif !s:edit_at_cursor({chord -> s:chord_transpose(chord, l:n)})
    call s:native_increment('', l:n, songwriter#grammar#IsTabLine(getline('.')))
  endif
endfunction

" Run `prefix` (normal-mode keys, such as a visual selection) then Vim's own
" <Ctrl-A> (n > 0) / <Ctrl-X> (n < 0), |n| times. On a tab line the dashes are
" not minus signs (`--3` is fret 3, not -3), so numbers are read as unsigned
" there.
function! s:native_increment(prefix, n, unsigned) abort
  if a:n == 0
    return
  endif
  let l:saved = &l:nrformats
  if a:unsigned
    setlocal nrformats+=unsigned
  endif
  try
    execute 'normal! ' . a:prefix . abs(a:n) . (a:n > 0 ? "\<C-A>" : "\<C-X>")
  finally
    let &l:nrformats = l:saved
  endtry
endfunction

" `line` with every chord token that overlaps 0-indexed columns [first, last]
" transposed by `semitones`. Tab lines hold no chords and are returned as is.
function! songwriter#chord#TransposeChordsIn(line, first, last, semitones) abort
  let l:tokens = filter(s:chord_tokens(a:line), 'v:val.end >= a:first && v:val.start <= a:last')
  let l:out = a:line
  " Right to left, so a wider chord (A -> A#) leaves the others' columns intact.
  for l:found in reverse(l:tokens)
    let l:out = s:splice_chord(l:out, l:found, s:chord_transpose(l:found.chord, a:semitones))
  endfor
  return l:out
endfunction

" Visual <Ctrl-A>/<Ctrl-X> (spec [Chords][[Editing]]), run from visual mode with
" a <Cmd> map. On each selected line, the chords the selection touches are
" transposed by `semitones`; a line where it touches none gets Vim's own visual
" increment on its selected part (frets unsigned on tab lines), except a tab
" line in tablature mode, where the first fret it touches changes as the
" others keep their time columns (spec [Tablature][[Editing]] 11.5). The
" selection is kept (same corners and cursor end), so <Ctrl-A> can be pressed
" again.
function! songwriter#chord#TransposeVisual(semitones) abort
  let l:n = str2nr(a:semitones)
  let l:mode = mode()
  let l:to_eol = winsaveview().curswant >= s:eol
  let [l:p, l:q] = [getpos('v'), getpos('.')]
  let [l:anchor, l:cursor] = [l:p, getcurpos()]
  execute "normal! \<Esc>"
  if l:p[1] > l:q[1] || (l:p[1] == l:q[1] && l:p[2] > l:q[2])
    let [l:p, l:q] = [l:q, l:p]
  endif
  let [l:lcol, l:rcol] = [min([l:p[2], l:q[2]]) - 1, max([l:p[2], l:q[2]]) - 1]
  let l:tabmode = songwriter#keys#InTabMode()
  let l:frets = []
  for l:lnum in range(l:p[1], l:q[1])
    if l:mode ==# 'V'
      let [l:first, l:last] = [0, s:eol]
    elseif l:mode ==# 'v'
      let l:first = l:lnum == l:p[1] ? l:p[2] - 1 : 0
      let l:last = l:lnum == l:q[1] ? l:q[2] - 1 : s:eol
    else
      let [l:first, l:last] = [l:lcol, l:to_eol ? s:eol : l:rcol]
    endif
    let l:line = getline(l:lnum)
    if l:first >= len(l:line)
      continue
    endif
    if l:tabmode && songwriter#grammar#IsTabLine(l:line)
      call add(l:frets, [l:lnum, l:first + 1, min([l:last, len(l:line) - 1]) + 1])
      continue
    endif
    let l:new = songwriter#chord#TransposeChordsIn(l:line, l:first, l:last, l:n)
    if l:new !=# l:line
      call setline(l:lnum, l:new)
    else
      call s:native_visual_increment(l:lnum, l:first, min([l:last, len(l:line) - 1]), l:n)
    endif
  endfor
  call songwriter#tab#frets#IncrementIn(l:frets, l:n)
  call s:reselect(l:mode, l:anchor, l:cursor, l:to_eol)
endfunction

" Start visual mode `mode` from position `anchor` (getpos()) to `cursor`
" (getcurpos(), whose curswant sets a blockwise selection's right edge);
" `to_eol` extends a blockwise selection to the end of every line (`$`).
function! s:reselect(mode, anchor, cursor, to_eol) abort
  call setpos('.', a:anchor)
  execute 'normal! ' . a:mode
  call setpos('.', a:cursor)
  if a:to_eol
    normal! $
  endif
endfunction

" Vim's own visual <Ctrl-A>/<Ctrl-X> by |n| on 0-indexed columns [first, last]
" of line `lnum`; on a tab line, numbers are unsigned (see s:native_increment).
function! s:native_visual_increment(lnum, first, last, n) abort
  if a:n == 0
    return
  endif
  call cursor(a:lnum, a:first + 1)
  call s:native_increment('v' . (a:last - a:first > 0 ? (a:last - a:first) . 'l' : ''),
        \ a:n, songwriter#grammar#IsTabLine(getline(a:lnum)))
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
  call s:edit_at_cursor({chord -> s:chord_build(chord.root, a:quality, chord.bass)})
endfunction

" Toggle the chord under the cursor between major and minor (A <-> Am, D/F# <->
" Dm/F#), leaving the rest of the quality (7, m7 -> 7, maj7 -> mmaj7) and the
" bass intact. No-op off a chord.
function! songwriter#chord#ToggleMinorMajor() abort
  call s:edit_at_cursor(function('s:toggle_minor'))
endfunction

function! s:toggle_minor(chord) abort
  let l:minor = matchstr(a:chord.quality, songwriter#grammar#MinorPrefix())
  let l:q = empty(l:minor) ? 'm' . a:chord.quality : strpart(a:chord.quality, len(l:minor))
  return s:chord_build(a:chord.root, l:q, a:chord.bass)
endfunction
