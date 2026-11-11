" autoload/songwriter/tab/stops.vim - where tablature-mode motions stop
" (spec [Tablature][[Editing]] 3.2, 3.3, 3.5) and the ranges the string
" motions cover after an operator (6.2.2), pure. Columns are 1-indexed byte
" columns; block lines are 0-indexed (`lin`).

" Where a tablature-mode motion can stop, sorted: `w`/`b` the first notes of
" the words of `line`, `e`/`ge` their last notes (3.2), `l`/`h` the time
" columns of the block.
function! songwriter#tab#stops#KeyStops(lines, line, key) abort
  if a:key =~# '^[wb]$'
    return map(songwriter#tab#model#Words(a:line), 'v:val.first')
  elseif a:key =~# '^g\=e$'
    return map(songwriter#tab#model#Words(a:line), 'v:val.last')
  endif
  return songwriter#tab#model#NoteColumns(songwriter#tab#model#Parse(0, a:lines))
endfunction

" Spec 6.2.2: the range [s, e] on `line` that the string motion `key` covers
" from column `col`, `count` times, trimmed to the notes it covers: from the
" start of the first to the end of the last. `l`/`h` count notes of the
" string (`l` from the note under the cursor), `w`/`b`/`e`/`ge` words. []
" when it covers no note.
function! songwriter#tab#stops#StringMotion(lines, line, col, key, count) abort
  let l:notes = songwriter#tab#model#Notes(a:line)
  let l:count = max([a:count, 1])
  if a:key ==# 'l'
    let l:i = index(map(copy(l:notes), 'v:val.col <= a:col && a:col < v:val.col + v:val.len'), 1)
    if l:i < 0
      return []
    endif
    let l:range = [l:notes[l:i].col, l:notes[min([l:i + l:count, len(l:notes)]) - 1].col]
  elseif a:key ==# 'h'
    let l:at = a:col
    for l:n in l:notes
      if l:n.col <= a:col && a:col < l:n.col + l:n.len
        let l:at = l:n.col
      endif
    endfor
    let l:before = filter(copy(l:notes), 'v:val.col < l:at')
    if empty(l:before)
      return []
    endif
    let l:range = [l:before[max([len(l:before) - l:count, 0])].col, l:at - 1]
  else
    let l:stops = songwriter#tab#stops#KeyStops(a:lines, a:line, a:key)
    let l:fwd = a:key =~# '^[we]$'
    let l:to = songwriter#tab#stops#Advance(l:stops, a:col, l:fwd ? 1 : -1, l:count)
    if l:to == a:col && a:key !=# 'w'
      return []
    endif
    let l:range = a:key ==# 'w' ? [a:col, l:to == a:col ? len(a:line) : l:to - 1]
          \ : a:key ==# 'b' ? [l:to, a:col - 1]
          \ : a:key ==# 'e' ? [a:col, l:to]
          \ : [l:to, a:col]
  endif
  let l:covered = filter(l:notes, 'v:val.col <= l:range[1] && l:range[0] < v:val.col + v:val.len')
  if empty(l:covered)
    return []
  endif
  return [l:covered[0].col, l:covered[-1].col + l:covered[-1].len - 1]
endfunction

" Spec [Tablature][[Editing]] 3.5: where the bar motion `key` goes from column
" `col` of `line`, a line of the block `lines`, `count` times, stopping at the
" last bar reached:
"   W: the first time column of the next bar (the first bar starting at or
"      after `col`, so on a pipe, the bar after it);
"   B: the first time column of the cursor's bar, or of the previous bar when
"      the cursor is on it or before it;
"   E: the last time column of the cursor's bar, or of the next bar when the
"      cursor is on it or after it.
" Bars are read from `line`'s pipes, time columns from the whole block; a bar
" with no note stands for its middle dash.
function! songwriter#tab#stops#BarStop(lines, line, col, key, count) abort
  let l:bars = s:bar_stops(a:lines, a:line)
  let l:col = a:col
  for l:_ in range(a:count)
    if a:key ==# 'W'
      let l:next = filter(copy(l:bars), 'v:val.start >= l:col')
      let l:col = empty(l:next) ? l:col : l:next[0].first
    elseif a:key ==# 'B'
      let l:prev = filter(copy(l:bars), 'v:val.first < l:col')
      let l:col = empty(l:prev) ? l:col : l:prev[-1].first
    else
      let l:next = filter(copy(l:bars), 'v:val.last > l:col')
      let l:col = empty(l:next) ? l:col : l:next[0].last
    endif
  endfor
  return l:col
endfunction

" The bars of `line`, left to right: {start (its opening pipe), first, last
" (its first and last time column of the block `lines`, or both its middle
" dash when it has no note)}. A bar with nothing between its pipes is left out.
function! s:bar_stops(lines, line) abort
  let l:pipes = songwriter#tab#model#Pipes(a:line)
  let l:cols = songwriter#tab#model#NoteColumns(songwriter#tab#model#Parse(0, a:lines))
  let l:bars = []
  for l:i in range(len(l:pipes) - 1)
    let [l:s, l:e] = l:pipes[l:i : l:i + 1]
    if l:e == l:s + 1
      continue
    endif
    let l:in = filter(copy(l:cols), 'l:s < v:val && v:val < l:e')
    let l:mid = l:s + (l:e - l:s) / 2
    call add(l:bars, {'start': l:s,
          \ 'first': empty(l:in) ? l:mid : l:in[0], 'last': empty(l:in) ? l:mid : l:in[-1]})
  endfor
  return l:bars
endfunction

" Spec [Tablature][[Editing]] 3.3: the stops of `l`/`h` on `line`, one of
" `block`'s lines: the columns where any string of the block has a note
" (3.3.1), and the middle of every empty bar (3.3.4).
function! songwriter#tab#stops#Stops(block, line) abort
  let l:cols = songwriter#tab#model#NoteColumns(a:block)
  return sort(l:cols + songwriter#tab#stops#EmptyBarStops(a:line, l:cols), 'n')
endfunction

" Spec 3.3.4: the stops of the empty bars of `line` (no column of `cols`, the
" block's note columns, inside them): their middle dash. A bar with nothing
" between its pipes (`||`) has no stop.
function! songwriter#tab#stops#EmptyBarStops(line, cols) abort
  let l:pipes = songwriter#tab#model#Pipes(a:line)
  let l:stops = []
  for l:i in range(len(l:pipes) - 1)
    let l:bar = {'start': l:pipes[l:i], 'end': l:pipes[l:i + 1]}
    if l:bar.end > l:bar.start + 1
          \ && empty(filter(copy(a:cols), 'songwriter#tab#model#InBar(v:val, l:bar)'))
      call add(l:stops, l:bar.start + (l:bar.end - l:bar.start) / 2)
    endif
  endfor
  return l:stops
endfunction

" True when `col` is in the last bar of a tab line that ends with a pipe:
" the line's final pipe is the first pipe at or after `col`.
function! songwriter#tab#stops#InLastBar(line, col) abort
  let l:pipes = songwriter#tab#model#Pipes(a:line)
  if empty(l:pipes) || l:pipes[-1] != len(a:line) || a:col > l:pipes[-1]
    return 0
  endif
  return empty(filter(copy(l:pipes), 'v:val >= a:col && v:val < l:pipes[-1]'))
endfunction

" `col` moved `count` stops forward (dir > 0) or backward (dir < 0) through the
" sorted list `stops`, stopping at the last one reached; `col` when there is none.
function! songwriter#tab#stops#Advance(stops, col, dir, count) abort
  let l:col = a:col
  for l:i in range(a:count)
    let l:c = filter(copy(a:stops), a:dir > 0 ? 'v:val > l:col' : 'v:val < l:col')
    if empty(l:c)
      break
    endif
    let l:col = a:dir > 0 ? l:c[0] : l:c[-1]
  endfor
  return l:col
endfunction
