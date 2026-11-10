" autoload/songwriter/tab/carry.vim - carrying a note with the arrow keys in the
" insert state (spec [Tablature][[Editing]] 3.6). Lift, Step and Render are
" pure (block lines in, lines and cursor out); Key and Move are the entry points.
"
" The first arrow lifts the note out of the tab, as `x` would erase it (6.7):
" what is left is the base, kept for the whole carry with the note's text. Where
" the note is over the base is a position:
"   {'kind': 'col', 'col': c}             on the note column c, replacing the
"                                         note of its string there
"   {'kind': 'gap', 'side': s, 'col': c}  in a slot opened after (s 1, as `a`)
"                                         or before (s -1, as `i`) column c
"   {'kind': 'bar', 'col': m}             in the empty bar whose middle is m
"   {'kind': 'newbar'}                    in a bar added after the last one
" Each arrow moves the position (or the string) and renders the base with the
" note there, so whatever the note replaced or opened on its way is back as it
" was once it moves on. Block lines are 0-indexed (`lin`), columns 1-indexed.

" Spec 3.6: lift the note covering column `col` of line `lin` out of `lines`.
" Returns the carry: {'base': the linted lines without the note, 'origin':
" `lines`, 'text': the note, 'lin', 'pos': where it is over the base, 'lin0',
" 'col0', 'pos0': where it started}, or {} off a note.
function! songwriter#tab#carry#Lift(lines, lin, col) abort
  let l:note = songwriter#tab#model#NoteAt(a:lines[a:lin], a:col)
  if empty(l:note)
    return {}
  endif
  let l:c = l:note.col
  let l:erased = songwriter#tab#columns#EraseNote(a:lines, a:lin, l:c)
  let l:lint = songwriter#tab#lint#Lint(l:erased.lines)
  let l:base = l:lint.lines
  if len(l:erased.lines[a:lin]) == len(a:lines[a:lin])
    " Shared column (6.7.1): it stays, with the note's string empty there.
    let l:pos = {'kind': 'col', 'col': songwriter#tab#lint#FollowColumn(l:erased.lines, l:lint, a:lin, l:c)}
  else
    " Lone column (6.7.2): it went, the note is in the gap it leaves.
    let l:bar = songwriter#tab#model#BarAt(a:lines[a:lin], l:c)
    let l:cols = filter(songwriter#tab#columns#Columns(a:lines),
          \ 'songwriter#tab#model#InBar(v:val, l:bar) && v:val != l:c')
    let l:prev = filter(copy(l:cols), 'v:val < l:c')
    if !empty(l:prev)
      let l:pos = {'kind': 'gap', 'side': 1,
            \ 'col': songwriter#tab#lint#FollowColumn(l:erased.lines, l:lint, a:lin, l:prev[-1])}
    elseif !empty(l:cols)
      " The next column moved onto the note's.
      let l:pos = {'kind': 'gap', 'side': -1,
            \ 'col': songwriter#tab#lint#FollowColumn(l:erased.lines, l:lint, a:lin, l:c)}
    else
      let l:pos = s:emptied_bar(a:lines[a:lin], l:base[a:lin], l:c)
    endif
  endif
  let l:pos = s:canonical(l:base, a:lin, l:pos)
  return {'base': l:base, 'origin': copy(a:lines), 'text': l:note.text,
        \ 'lin': a:lin, 'pos': l:pos, 'lin0': a:lin, 'col0': l:c, 'pos0': l:pos}
endfunction

" The position of a note lifted from column `col` of `line`, alone in its bar,
" over `base`, that line in the base: that bar, empty, or a new bar when lint
" dropped it (it was the last one, 1.4).
function! s:emptied_bar(line, base, col) abort
  let l:k = len(filter(songwriter#tab#model#Pipes(a:line), 'v:val < a:col')) - 1
  let l:pipes = songwriter#tab#model#Pipes(a:base)
  if l:k < 0 || l:k + 1 >= len(l:pipes)
    return {'kind': 'newbar'}
  endif
  return {'kind': 'bar', 'col': l:pipes[l:k] + (l:pipes[l:k + 1] - l:pipes[l:k]) / 2}
endfunction

" A gap between two columns of a bar is the same whichever side it was opened
" from: it is named after the column before it.
function! s:canonical(base, lin, pos) abort
  if a:pos.kind !=# 'gap' || a:pos.side > 0
    return a:pos
  endif
  let l:bar = songwriter#tab#model#BarAt(a:base[a:lin], a:pos.col)
  let l:prev = filter(songwriter#tab#columns#Columns(a:base),
        \ 'v:val < a:pos.col && songwriter#tab#model#InBar(v:val, l:bar)')
  return empty(l:prev) ? a:pos : {'kind': 'gap', 'side': 1, 'col': l:prev[-1]}
endfunction

" Spec 3.6: the position after `pos` (over `base`, on line `lin`) in direction
" `dir`, through the stops of `l`/`h` in the insert state (3.3.3): from a
" column into the gap on that side of it, from a gap onto the column it was
" opened from or on to the next stop, an empty bar being one (3.3.4). Past the
" last stop of the tab's last bar, a new bar (5); back from it, the last stop.
" `pos` itself when there is nowhere to go.
function! songwriter#tab#carry#Step(base, lin, pos, dir) abort
  let l:block = songwriter#tab#model#Parse(0, a:base)
  let l:line = a:base[a:lin]
  let l:stops = songwriter#tab#model#Stops(l:block, l:line)
  if a:pos.kind ==# 'col'
    return s:canonical(a:base, a:lin, {'kind': 'gap', 'side': a:dir, 'col': a:pos.col})
  elseif a:pos.kind ==# 'newbar'
    return a:dir < 0 && !empty(l:stops) ? s:stop(l:block, l:line, l:stops[-1]) : a:pos
  elseif a:pos.kind ==# 'gap' && a:pos.side == -a:dir
    return {'kind': 'col', 'col': a:pos.col}
  endif
  let l:target = songwriter#tab#model#Advance(l:stops, a:pos.col, a:dir, 1)
  if l:target != a:pos.col
    return s:stop(l:block, l:line, l:target)
  elseif a:pos.kind ==# 'gap' && a:dir > 0 && songwriter#tab#model#InLastBar(l:line, a:pos.col)
    return {'kind': 'newbar'}
  endif
  return a:pos
endfunction

" The position of stop `col` of `line`: an empty bar's middle, or a column.
function! s:stop(block, line, col) abort
  let l:empty = songwriter#tab#model#EmptyBarStops(a:line, songwriter#tab#model#NoteColumns(a:block))
  return {'kind': index(l:empty, a:col) >= 0 ? 'bar' : 'col', 'col': a:col}
endfunction

" Spec 3.6: the tab with the note of `carry` at `pos` on line `lin`: its base
" with room opened as `a`/`i` (3.1), an empty bar (3.3.4) or a new bar (5) would,
" and the note written there over whatever its string had, room made for it
" (7.5). Where the carry started, its origin, untouched. Returns {'lines',
" 'col': the note's column}, or {} when the note cannot go there (a separator).
function! songwriter#tab#carry#Render(carry, pos, lin) abort
  if a:pos ==# a:carry.pos0 && a:lin == a:carry.lin0
    return {'lines': copy(a:carry.origin), 'col': a:carry.col0}
  endif
  let l:block = songwriter#tab#model#Parse(0, a:carry.base)
  if a:pos.kind ==# 'col'
    let l:room = {'lines': a:carry.base, 'col': a:pos.col}
  elseif a:pos.kind ==# 'gap'
    let l:room = a:pos.side > 0
          \ ? songwriter#tab#slots#Append(l:block, a:lin, a:pos.col)
          \ : songwriter#tab#slots#Prepend(l:block, a:lin, a:pos.col)
  elseif a:pos.kind ==# 'bar'
    let l:room = songwriter#tab#slots#EmptyBar(a:carry.base, a:lin, a:pos.col)
  else
    let l:room = songwriter#tab#slots#AppendBar(l:block)
  endif
  return empty(l:room) ? {} : s:put(l:room.lines, a:lin, l:room.col, a:carry.text)
endfunction

" `text` written at column `col` of line `lin`, over the note there if any.
function! s:put(lines, lin, col, text) abort
  let l:lines = copy(a:lines)
  let l:c = a:col
  let l:note = songwriter#tab#model#NoteAt(l:lines[a:lin], l:c)
  if !empty(l:note)
    let l:t = l:lines[a:lin]
    let l:c = l:note.col
    let l:lines[a:lin] = strpart(l:t, 0, l:c - 1) . repeat('-', l:note.len) . strpart(l:t, l:c - 1 + l:note.len)
  endif
  let l:room = songwriter#tab#columns#MakeRoom(l:lines, a:lin, l:c, len(a:text))
  if has_key(l:room, 'error')
    return {}
  endif
  let l:t = l:room.lines[a:lin]
  let l:room.lines[a:lin] = strpart(l:t, 0, l:room.col - 1) . a:text . strpart(l:t, l:room.col - 1 + len(a:text))
  return l:room
endfunction

" Arrow key -> [string step, column direction].
let s:moves = {'<Up>': [-1, 0], '<Down>': [1, 0], '<Left>': [0, -1], '<Right>': [0, 1]}

" Spec 3.6: the keys for arrow `key` in the insert state: on a note, carry it
" (Move); elsewhere, the arrow itself.
function! songwriter#tab#carry#Key(key) abort
  if empty(songwriter#tab#model#NoteAt(getline('.'), col('.')))
    return eval('"\' . a:key . '"')
  endif
  return "\<Cmd>call songwriter#tab#carry#Move(" . string(a:key) . ")\<CR>"
endfunction

" Spec 3.6: carry the note under the cursor one string up / down or one stop
" left / right (arrow `key`). Straight after a move (cursor on the carried
" note, buffer unchanged since), the carry goes on from where it is, in the same
" undo step; otherwise the note under the cursor is lifted first. The tab is
" linted with the cursor on the note, and the insert state is kept. With
" nowhere to go, nothing changes.
function! songwriter#tab#carry#Move(key) abort
  let [l:dlin, l:dir] = s:moves[a:key]
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:carry = songwriter#tab#state#Get('carry')
  let l:going = !empty(l:carry) && l:carry.start == l:block.start
        \ && l:carry.line == line('.') && l:carry.cursor == col('.')
  if !l:going
    let l:carry = songwriter#tab#carry#Lift(l:block.lines,
          \ songwriter#tab#model#CursorLin(l:block), col('.'))
    if empty(l:carry)
      return
    endif
    let l:carry.start = l:block.start
  endif
  let l:lin = l:carry.lin + l:dlin
  if l:lin < 0 || l:lin >= len(l:block.lines)
    return
  endif
  let l:pos = l:dir == 0 ? l:carry.pos
        \ : songwriter#tab#carry#Step(l:carry.base, l:lin, l:carry.pos, l:dir)
  if l:pos ==# l:carry.pos && l:lin == l:carry.lin
    return
  endif
  let l:res = songwriter#tab#carry#Render(l:carry, l:pos, l:lin)
  if empty(l:res)
    return
  endif
  if l:going
    silent! undojoin
  endif
  call songwriter#tab#model#Write(l:block, l:res.lines)
  call cursor(l:block.start + l:lin, l:res.col)
  call songwriter#tab#edit#LintAndFollow(songwriter#tab#model#Read())
  call songwriter#tab#state#Set('carry', extend(l:carry,
        \ {'pos': l:pos, 'lin': l:lin, 'line': line('.'), 'cursor': col('.')}))
  call songwriter#tab#insert#Keep()
endfunction
