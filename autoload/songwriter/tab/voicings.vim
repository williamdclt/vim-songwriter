" autoload/songwriter/tab/voicings.vim - a whole chord on a time column (spec
" [Tablature][[Editing]] 10). Voicings() and Place() are pure (string names
" or block lines in, voicings or lines out); Prompt(), Enter() and Next() are
" the buffer entry points.
"
" Block lines are 0-indexed (`lin`), top string first; columns 1-indexed. A
" voicing is {'lin': its root's line, 'fret': its root's fret, 'shape',
" 'frets': one fret per line, -1 where the string is not played}.

" Spec 10.2: the CAGED shapes in standard tuning. `root` counts the string the
" root is on from the bottom (0 low E, 1 A, 2 D); a quality's frets go from
" that string upwards, relative to the root's fret. A shape with `at` exists
" only with its root on that fret (open position). Open-position shapes come
" first, so that they come first among voicings on the same fret.
let s:shapes = [
      \ {'name': 'C', 'root': 1, 'at': 3, 'q': {
      \   'maj': [0, -1, -3, -2, -3], '7': [0, -1, 0, -2, -3], 'maj7': [0, -1, -3, -3, -3]}},
      \ {'name': 'G', 'root': 0, 'at': 3, 'q': {
      \   'maj': [0, -1, -3, -3, -3, 0], '7': [0, -1, -3, -3, -3, -2],
      \   'maj7': [0, -1, -3, -3, -3, -1]}},
      \ {'name': 'E', 'root': 0, 'q': {
      \   'maj': [0, 2, 2, 1, 0, 0], 'm': [0, 2, 2, 0, 0, 0], '7': [0, 2, 0, 1, 0, 0],
      \   'm7': [0, 2, 0, 0, 0, 0], 'maj7': [0, 2, 1, 1, 0, 0], 'sus4': [0, 2, 2, 2, 0, 0]}},
      \ {'name': 'A', 'root': 1, 'q': {
      \   'maj': [0, 2, 2, 2, 0], 'm': [0, 2, 2, 1, 0], '7': [0, 2, 0, 2, 0],
      \   'm7': [0, 2, 0, 1, 0], 'maj7': [0, 2, 1, 2, 0], 'sus2': [0, 2, 2, 0, 0],
      \   'sus4': [0, 2, 2, 3, 0]}},
      \ {'name': 'D', 'root': 2, 'q': {
      \   'maj': [0, 2, 3, 2], 'm': [0, 2, 3, 1], '7': [0, 2, 1, 2], 'm7': [0, 2, 1, 1],
      \   'maj7': [0, 2, 2, 2], 'sus2': [0, 2, 3, 0], 'sus4': [0, 2, 3, 3]}},
      \ ]

" Spec 10.2, 10.3: the qualities a voicing exists for, by spelling.
let s:qualities = {
      \ '': 'maj', 'M': 'maj', 'maj': 'maj', 'm': 'm', 'min': 'm',
      \ '7': '7', 'm7': 'm7', 'min7': 'm7', 'maj7': 'maj7', 'M7': 'maj7',
      \ 'sus2': 'sus2', 'sus4': 'sus4', 'sus': 'sus4', '5': '5',
      \ }

let s:standard = ['e', 'b', 'g', 'd', 'a', 'e']

" Spec 10.2-10.4, 10.6: the voicings of `chord` on strings `names` (top
" first), in the order `==` goes through them from line `lin`: by root string,
" `lin` first, then each lower string, then each higher one; on a string, by
" fret (open-position shapes first on the same fret); the voicings at the 12th
" fret after all the others. The root's letter may be lowercase (10.1).
" {'error'} when there is none.
function! songwriter#tab#voicings#Voicings(names, chord, lin) abort
  let l:parsed = songwriter#grammar#ParseChord(songwriter#tab#voicings#Name(a:chord))
  if empty(l:parsed)
    return {'error': printf('songwriter: %s is not a chord', a:chord)}
  endif
  let [l:root, l:spelling, l:bass] = l:parsed
  if !empty(l:bass)
    return {'error': printf('songwriter: no voicing for a slash chord (%s)', a:chord)}
  endif
  let l:quality = get(s:qualities, l:spelling, '')
  if empty(l:quality)
    return {'error': printf('songwriter: no chord shape for %s', a:chord)}
  endif
  let l:pc = songwriter#pitch#Class(l:root)
  if l:quality ==# '5'
    let l:all = s:power(a:names, l:pc)
  elseif map(copy(a:names), 'tolower(v:val)') ==# s:standard
    let l:all = s:shaped(a:names, l:pc, l:quality)
  else
    return {'error': 'songwriter: chord shapes need standard tuning (eBGDAE); power chords follow any tuning'}
  endif
  let l:n = len(a:names)
  let l:order = [a:lin] + range(a:lin + 1, l:n - 1) + reverse(range(0, a:lin - 1))
  let l:result = []
  for l:high in [0, 1]
    for l:lin in l:order
      let l:here = filter(copy(l:all), 'v:val.lin == l:lin && (v:val.fret >= 12) == l:high')
      call extend(l:result, sort(l:here, {a, b -> a.fret - b.fret}))
    endfor
  endfor
  if empty(l:result)
    return {'error': printf('songwriter: no voicing of %s on these strings', a:chord)}
  endif
  return l:result
endfunction

" Spec 10.1: `chord` with its root's letter in uppercase (`am` -> `Am`, `bb5`
" -> `Bb5`). The quality keeps its case: `M7` and `m7` differ.
function! songwriter#tab#voicings#Name(chord) abort
  return toupper(a:chord[0 : 0]) . a:chord[1 :]
endfunction

" Spec 10.2: the shaped voicings of the chord with root pitch class `pc` and
" quality `quality`, on a standard 6-string tuning `names`.
function! s:shaped(names, pc, quality) abort
  let l:all = []
  for l:shape in s:shapes
    if !has_key(l:shape.q, a:quality)
      continue
    endif
    let l:lin = len(a:names) - 1 - l:shape.root
    let l:fret = (a:pc - songwriter#pitch#Class(a:names[l:lin]) + 12) % 12
    if has_key(l:shape, 'at')
      let l:frets = l:fret == l:shape.at ? [l:fret] : []
    else
      let l:frets = l:fret == 0 ? [0, 12] : [l:fret]
    endif
    for l:f in l:frets
      let l:v = repeat([-1], len(a:names))
      let l:rel = l:shape.q[a:quality]
      for l:k in range(len(l:rel))
        let l:v[l:lin - l:k] = l:f + l:rel[l:k]
      endfor
      call add(l:all, {'lin': l:lin, 'fret': l:f, 'shape': l:shape.name, 'frets': l:v})
    endfor
  endfor
  return l:all
endfunction

" Spec 10.3: power chords of root pitch class `pc` on strings `names`: on
" every string with two strings above it, the root, the fifth on the next
" string and the octave on the one after. The frets come from the intervals
" between the strings, read from their names (as spec 7.3).
function! s:power(names, pc) abort
  let l:all = []
  for l:lin in range(2, len(a:names) - 1)
    let l:pcs = map(a:names[l:lin - 2 : l:lin], 'songwriter#pitch#Class(v:val)')
    if min(l:pcs) < 0
      continue
    endif
    let l:up1 = (l:pcs[1] - l:pcs[2] + 12) % 12
    let l:up2 = l:up1 + (l:pcs[0] - l:pcs[1] + 12) % 12
    if l:up1 == 0 || l:up2 == l:up1
      continue
    endif
    let l:fret = (a:pc - l:pcs[2] + 12) % 12
    for l:f in (l:fret == 0 ? [0, 12] : [l:fret])
      let [l:fifth, l:octave] = [l:f + 7 - l:up1, l:f + 12 - l:up2]
      if l:fifth < 0 || l:octave < 0
        continue
      endif
      let l:v = repeat([-1], len(a:names))
      let [l:v[l:lin], l:v[l:lin - 1], l:v[l:lin - 2]] = [l:f, l:fifth, l:octave]
      call add(l:all, {'lin': l:lin, 'fret': l:f, 'shape': '5', 'frets': l:v})
    endfor
  endfor
  return l:all
endfunction

" Spec 10.5, 10.6: write `voicing` on the time column at column `col` of line
" `lin`: the column of the note under the cursor, or `col` itself on a dash.
" Every note starting on that column is replaced; a fret that needs room gets
" it as in spec 7.5. Returns {'lines', 'col'}, or {'error'} on a pipe or the
" string name, or when a note on another string covers the column.
function! songwriter#tab#voicings#Place(lines, lin, col, voicing) abort
  if songwriter#tab#columns#OnPipeOrName(a:lines[a:lin], a:col)
    return {'error': 'songwriter: a chord goes on a time column, not on a pipe or a string name'}
  endif
  let l:c = a:col
  for l:n in songwriter#tab#model#Notes(a:lines[a:lin])
    if a:col >= l:n.col && a:col < l:n.col + l:n.len
      let l:c = l:n.col
    endif
  endfor
  let l:lines = copy(a:lines)
  for l:i in range(len(l:lines))
    for l:n in songwriter#tab#model#Notes(l:lines[l:i])
      if l:n.col == l:c
        let l:lines[l:i] = strpart(l:lines[l:i], 0, l:c - 1) . repeat('-', l:n.len)
              \ . strpart(l:lines[l:i], l:c - 1 + l:n.len)
      endif
    endfor
  endfor
  for l:i in range(len(l:lines))
    if a:voicing.frets[l:i] < 0
      continue
    endif
    let l:text = string(a:voicing.frets[l:i])
    let l:room = songwriter#tab#columns#MakeRoom(l:lines, l:i, l:c, len(l:text))
    if has_key(l:room, 'error')
      return {'error': 'songwriter: ' . l:room.error}
    endif
    let [l:lines, l:c] = [l:room.lines, l:room.col]
    let l:t = l:lines[l:i]
    let l:lines[l:i] = strpart(l:t, 0, l:c - 1) . l:text . strpart(l:t, l:c - 1 + len(l:text))
  endfor
  return {'lines': l:lines, 'col': l:c}
endfunction

" Spec 10.4: the message for voicing `index` of `voicings` of `chord`.
function! songwriter#tab#voicings#Describe(chord, voicings, index, names) abort
  let l:v = a:voicings[a:index]
  return printf('%s: root on %s, fret %d (%d/%d)', a:chord, a:names[l:v.lin], l:v.fret,
        \ a:index + 1, len(a:voicings))
endfunction

" Spec 10.1, 10.4: `=`. Read a chord name and enter it (Enter), or, on a
" second `=`, go to the next voicing (Next). `<Esc>` or an empty name cancels.
function! songwriter#tab#voicings#Prompt() abort
  echo '='
  let l:key = getchar()
  let l:key = type(l:key) == v:t_number ? nr2char(l:key) : l:key
  if l:key ==# '='
    call songwriter#tab#voicings#Next()
    return
  endif
  let l:name = (l:key ==# "\<Esc>" || l:key ==# "\<CR>") ? '' : trim(input('=', l:key))
  redraw
  if !empty(l:name)
    call songwriter#tab#voicings#Enter(l:name)
  endif
endfunction

" Spec 10.1, 10.5: enter the first voicing of `chord` rooted from the
" cursor's string on the cursor's time column. A refusal is echoed (10.6).
function! songwriter#tab#voicings#Enter(chord) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:lin = songwriter#tab#model#CursorLin(l:block)
  let l:chord = songwriter#tab#voicings#Name(a:chord)
  let l:voicings = songwriter#tab#voicings#Voicings(
        \ songwriter#tab#model#Names(l:block.lines), l:chord, l:lin)
  if type(l:voicings) == v:t_dict
    call songwriter#tab#edit#Error(l:voicings.error)
    return
  endif
  call s:put(l:block, l:lin, col('.'), l:chord, l:voicings, 0, 0)
endfunction

" Spec 10.4: `==`, replace the chord just entered with its next voicing, in
" the same undo step.
function! songwriter#tab#voicings#Next() abort
  let l:last = songwriter#tab#state#Get('voicing')
  if empty(l:last) || l:last.line != line('.') || l:last.col != col('.')
    call songwriter#tab#edit#Error('songwriter: == follows a chord entered with =')
    return
  endif
  call s:put(songwriter#tab#model#Read(), l:last.lin, l:last.col, l:last.chord,
        \ l:last.voicings, (l:last.index + 1) % len(l:last.voicings), 1)
endfunction

" Place voicing `index` of `voicings` at column `col`, cursor line `lin`, then
" lint (10.5). It fills an open slot, joined to its undo step, as is a cycle
" (`join`). In the insert state, the next digit opens a slot after it
" (EnterNote).
function! s:put(block, lin, col, chord, voicings, index, join) abort
  let l:result = songwriter#tab#voicings#Place(a:block.lines, a:lin, a:col, a:voicings[a:index])
  if has_key(l:result, 'error')
    call songwriter#tab#edit#Error(l:result.error)
    return
  endif
  if a:join || !empty(songwriter#tab#state#Get('slot'))
    silent! undojoin
  endif
  let l:result.msg = songwriter#tab#voicings#Describe(a:chord, a:voicings, a:index,
        \ songwriter#tab#model#Names(a:block.lines))
  let l:insert = songwriter#tab#insert#Active()
  call songwriter#tab#edit#Commit(a:block, l:result)
  call songwriter#tab#slots#Forget()
  if l:insert
    call songwriter#tab#state#Set('typing', {'line': line('.'), 'col': col('.'), 'chord': 1})
    call songwriter#tab#insert#Keep()
  endif
  call songwriter#tab#state#Set('voicing', {'chord': a:chord, 'voicings': a:voicings,
        \ 'index': a:index, 'lin': a:lin, 'line': line('.'), 'col': col('.')})
endfunction
