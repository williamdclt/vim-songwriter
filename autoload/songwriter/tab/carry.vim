" autoload/songwriter/tab/carry.vim - carrying a note with the arrow keys in the
" insert state (spec [Tablature][[Editing]] 3.6). Lift and Render are pure
" (block lines in, lines and cursor out); Key and Move are the entry points.
"
" The first arrow lifts the note out of the tab, as `x` would erase it (6.7):
" what is left is the base, kept for the whole carry with the note's text. Where
" the note is over the base is a position of the insert state (see
" stops#Step, which `l`/`h` step through too), on the note's string. Each arrow
" moves the position (stops#Step) or the string and renders the base with the
" note there, replacing the note of its string on a column, so whatever the
" note replaced or opened on its way is back as it was once it moves on. Block
" lines are 0-indexed (`lin`), columns 1-indexed.

" Spec 3.6: lift the note covering column `col` of line `lin` out of `lines`.
" The base keeps as many bars as the linted tab had: a bar the note leaves
" empty at the end stays, so that it, and an empty bar before it, are still
" stops (3.3.4) for the note to go back to. Returns the carry: {'base': the
" linted lines without the note, 'map': where the columns of `lines` are in
" the base, 'origin': `lines`, 'text': the note, 'lin', 'pos': where it is
" over the base, 'lin0', 'col0', 'pos0': where it started}, or {} off a note.
function! songwriter#tab#carry#Lift(lines, lin, col) abort
  let l:note = songwriter#tab#model#NoteAt(a:lines[a:lin], a:col)
  if empty(l:note)
    return {}
  endif
  let l:c = l:note.col
  let l:erased = songwriter#tab#columns#EraseNote(a:lines, a:lin, l:c)
  let l:lint = songwriter#tab#lint#Lint(l:erased.lines)
  let l:base = l:lint.lines
  let l:map = songwriter#tab#colmap#Then(l:erased.map, l:lint.map)
  let l:bars = len(songwriter#tab#model#Pipes(songwriter#tab#lint#Lint(a:lines).lines[a:lin])) - 1
  while len(songwriter#tab#model#Pipes(l:base[a:lin])) - 1 < l:bars
    let l:map = songwriter#tab#colmap#Then(l:map, songwriter#tab#colmap#Insert(len(l:base[0]), 6))
    call map(l:base, "v:val . '-----|'")
  endwhile
  if len(l:erased.lines[a:lin]) == len(a:lines[a:lin])
    " Shared column (6.7.1): it stays, with the note's string empty there.
    let l:pos = {'kind': 'col', 'col': songwriter#tab#lint#FollowColumn(l:erased.lines, l:lint, a:lin, l:c)}
  else
    " Lone column (6.7.2): it went, the note is in the gap it leaves.
    let l:cols = filter(songwriter#tab#model#BarColumns(songwriter#tab#model#Parse(0, a:lines), a:lin, l:c).cols,
          \ 'v:val != l:c')
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
  return {'base': l:base, 'map': l:map, 'origin': copy(a:lines), 'text': l:note.text,
        \ 'lin': a:lin, 'pos': l:pos, 'lin0': a:lin, 'col0': l:c, 'pos0': l:pos}
endfunction

" The position of a note lifted from column `col` of `line`, alone in its bar,
" over `base`, that line in the base: that bar, empty, or a new bar when the
" base has no such bar.
function! s:emptied_bar(line, base, col) abort
  let l:k = len(filter(songwriter#tab#model#Pipes(a:line), 'v:val < a:col')) - 1
  let l:pipes = songwriter#tab#model#Pipes(a:base)
  if l:k < 0 || l:k + 1 >= len(l:pipes)
    return {'kind': 'newbar'}
  endif
  return {'kind': 'bar', 'col': l:pipes[l:k] + (l:pipes[l:k + 1] - l:pipes[l:k]) / 2}
endfunction

" A gap between two columns of a bar is the same place whichever side it was
" entered from: named after the column before it, two positions compare equal
" when they are the same place.
function! s:canonical(base, lin, pos) abort
  if a:pos.kind !=# 'gap' || a:pos.side > 0
    return a:pos
  endif
  let l:prev = filter(songwriter#tab#model#BarColumns(songwriter#tab#model#Parse(0, a:base), a:lin, a:pos.col).cols,
        \ 'v:val < a:pos.col')
  return empty(l:prev) ? a:pos : {'kind': 'gap', 'side': 1, 'col': l:prev[-1]}
endfunction

" Spec 3.6: the tab with the note of `carry` at `pos` on line `lin`: its base
" with room opened as `a`/`i` (3.1), an empty bar (3.3.4) or a new bar (5) would,
" and the note written there over whatever its string had, room made for it
" (7.5). Returns {'lines', 'col': the note's column, 'map': where the columns
" of the base are}; where the carry started, its origin, untouched, with no
" map ({'lines', 'col', 'origin': 1}). {} when the note cannot go there (a
" separator).
function! songwriter#tab#carry#Render(carry, pos, lin) abort
  if a:lin == a:carry.lin0 && s:canonical(a:carry.base, a:lin, a:pos)
        \ ==# s:canonical(a:carry.base, a:lin, a:carry.pos0)
    return {'lines': copy(a:carry.origin), 'col': a:carry.col0, 'origin': 1}
  endif
  let l:block = songwriter#tab#model#Parse(0, a:carry.base)
  if a:pos.kind ==# 'col'
    let l:room = {'lines': a:carry.base, 'col': a:pos.col, 'map': []}
  elseif a:pos.kind ==# 'gap'
    let l:room = a:pos.side > 0
          \ ? songwriter#tab#slots#Append(l:block, a:lin, a:pos.col)
          \ : songwriter#tab#slots#Prepend(l:block, a:lin, a:pos.col)
  elseif a:pos.kind ==# 'bar'
    let l:room = songwriter#tab#slots#EmptyBar(a:carry.base, a:lin, a:pos.col)
  else
    let l:room = songwriter#tab#slots#AppendBar(l:block)
  endif
  if empty(l:room)
    return {}
  endif
  let l:put = s:put(l:room.lines, a:lin, l:room.col, a:carry.text)
  return empty(l:put) ? {} : extend(l:put, {'map': songwriter#tab#colmap#Then(l:room.map, l:put.map)})
endfunction

" `text` written at column `col` of line `lin`, over the note there if any:
" {'lines', 'col', 'map'} (columns#PutNote), or {}.
function! s:put(lines, lin, col, text) abort
  let l:lines = copy(a:lines)
  let l:c = a:col
  let l:note = songwriter#tab#model#NoteAt(l:lines[a:lin], l:c)
  if !empty(l:note)
    let l:c = l:note.col
    let l:lines[a:lin] = songwriter#tab#model#Blank(l:lines[a:lin], l:note)
  endif
  let l:room = songwriter#tab#columns#PutNote(l:lines, a:lin, l:c, a:text)
  return has_key(l:room, 'error') ? {} : l:room
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
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:carry = songwriter#tab#state#Get('carry')
  let l:going = !empty(l:carry) && l:carry.saved.origin.top == l:block.top
        \ && l:carry.line == line('.') && l:carry.col == col('.')
  call songwriter#tab#edit#Do(function('s:move', [s:moves[a:key], l:going ? l:carry : {}]),
        \ {'join': l:going, 'prelint': 0, 'insert': 1})
endfunction

" Spec 3.7: a carry of a copy of the note covering column `col` of line `lin`
" of `lines` (linted). The note stays: the base is `lines` as they are, so
" wherever the copy goes the original is still there, and the copy carried
" back onto it gives `lines` again. 'moving' marks the carry for `hjkl`
" (Moving). Returns {} off a note.
function! songwriter#tab#carry#Copy(lines, lin, col) abort
  let l:note = songwriter#tab#model#NoteAt(a:lines[a:lin], a:col)
  if empty(l:note)
    return {}
  endif
  let l:pos = {'kind': 'col', 'col': l:note.col}
  return {'base': copy(a:lines), 'map': [], 'origin': copy(a:lines), 'text': l:note.text,
        \ 'lin': a:lin, 'pos': l:pos, 'lin0': a:lin, 'col0': l:note.col, 'pos0': l:pos,
        \ 'moving': 1}
endfunction

" Spec 3.7: `<leader>k` / `<leader>j` (`dir` -1 / 1) copy the note under the
" cursor onto the string above / below, cursor on the copy, and start moving
" it: the insert state, with `hjkl` as the arrows (Moving). Nothing happens
" outside tablature mode, off a note or with no string that way.
function! songwriter#tab#carry#Duplicate(dir) abort
  if !songwriter#keys#InTabMode()
    return
  endif
  let l:done = songwriter#tab#edit#Do(function('s:duplicate', [a:dir]), {'prelint': 0})
  if !empty(l:done)
    call songwriter#tab#insert#Keep()
    call songwriter#tab#insert#Show('-- TAB MOVE --')
  endif
endfunction

" Pure. The copy of the note under the cursor of `ctx`, one string `dir`.
function! s:duplicate(dir, ctx) abort
  let l:linted = songwriter#tab#edit#Linted(a:ctx.block.lines, a:ctx.lin, a:ctx.col)
  let l:carry = songwriter#tab#carry#Copy(l:linted.lines, a:ctx.lin, l:linted.col)
  if empty(l:carry)
    return {}
  endif
  let l:origin = songwriter#tab#edit#Derive(songwriter#tab#model#Snapshot(a:ctx.block),
        \ l:linted.lines, l:linted.map)
  let l:carry.saved = {'origin': l:origin, 'base': l:origin}
  return s:move([a:dir, 0], l:carry, a:ctx)
endfunction

" Spec 3.7: whether a duplicated note is being moved: in the insert state,
" the cursor on the copy, nothing changed since it was last moved. `hjkl` are
" then the arrows (keys.vim).
function! songwriter#tab#carry#Moving() abort
  let l:carry = songwriter#tab#state#Get('carry')
  return get(l:carry, 'moving', 0) && songwriter#tab#insert#Active()
        \ && l:carry.line == line('.') && l:carry.col == col('.')
endfunction

" Spec 3.7: a lone `<leader>` ends the move as `<Esc>` does; anywhere else it
" does nothing.
function! songwriter#tab#carry#EndMove() abort
  if songwriter#tab#carry#Moving()
    call songwriter#tab#insert#Escape()
  endif
endfunction

" Pure. The move [string step, column direction] of the carry `carry` (or of
" the note under the cursor of `ctx`, lifted, when it is {}). The carry keeps
" the snapshots of its origin and its base ('saved'), which the tab it renders
" is made from (edit.vim's 'base').
function! s:move(move, carry, ctx) abort
  let [l:dlin, l:dir] = a:move
  let l:carry = a:carry
  if empty(l:carry)
    let l:carry = songwriter#tab#carry#Lift(a:ctx.block.lines, a:ctx.lin, a:ctx.col)
    if empty(l:carry)
      return {}
    endif
    let l:origin = songwriter#tab#model#Snapshot(a:ctx.block)
    let l:carry.saved = {'origin': l:origin,
          \ 'base': songwriter#tab#edit#Derive(l:origin, l:carry.base, l:carry.map)}
  endif
  let l:lin = l:carry.lin + l:dlin
  if l:lin < 0 || l:lin >= len(a:ctx.block.lines)
    return {}
  endif
  let l:pos = l:dir == 0 ? l:carry.pos
        \ : songwriter#tab#stops#Step(l:carry.base, l:lin, l:carry.pos, l:dir)
  if l:pos ==# l:carry.pos && l:lin == l:carry.lin
    return {}
  endif
  let l:res = songwriter#tab#carry#Render(l:carry, l:pos, l:lin)
  if empty(l:res)
    return {}
  endif
  let l:from = get(l:res, 'origin', 0) ? l:carry.saved.origin : l:carry.saved.base
  return {'lines': l:res.lines, 'base': l:from, 'map': get(l:res, 'map', []),
        \ 'lin': l:lin, 'col': l:res.col,
        \ 'state': {'carry': extend(copy(l:carry), {'pos': l:pos, 'lin': l:lin})}}
endfunction
