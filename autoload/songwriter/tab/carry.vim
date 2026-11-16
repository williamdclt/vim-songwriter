" autoload/songwriter/tab/carry.vim - carrying notes across strings (spec
" [Tablature][[Editing]] 3.6-3.8, 7): `<leader>k`/`<leader>j`, `s`/`S`, the
" copies of `<leader><leader>k`/`<leader><leader>j`, the move state (`m`) and
" visual `<leader>k`/`<leader>j`. Lift, Copy, Step, Render and Move are pure
" (block lines in, lines and cursor out); the rest are entry points.
"
" A carry lifts notes out of the tab: what is left, the base, is kept for the
" whole run with the notes. Each step moves every note the same number of
" strings, or changes their texts (`S` keeps the pitch, the move state's
" `h`/`l` change the fret), and the tab is rendered from the base with the
" notes written there, over whatever their strings had: a note a carried note
" replaced is back as soon as it moves on, and back where they started, the
" tab is the one they were lifted from. Notes never change time column, so the
" base keeps every column of the tab. Block lines are 0-indexed (`lin`),
" columns 1-indexed.
"
" A carry is {'origin': the lines it was lifted from, 'base', 'notes':
" [{'lin', 'col' (in the base), 'pre', 'text0', 'text', 'post'}] ('pre' and
" 'post': the separators that go with the note, before and after it, from
" 'col'), 'dlin': how many strings
" down they are, 'kind': 'note', 'column' or 'visual', 'cur': the index of the
" note the cursor is on (-1: none), 'off': the cursor's byte in that note,
" 'lin0', 'col0': the cursor where it was lifted}.

" Spec 3.6, 7.1: lift `notes` (as Notes() gives them) out of `lines`, the
" cursor being at column `col` of line `lin`.
function! songwriter#tab#carry#Lift(lines, notes, kind, lin, col) abort
  let l:base = copy(a:lines)
  for l:n in a:notes
    let l:base[l:n.lin] = songwriter#tab#model#Blank(l:base[l:n.lin], {'col': l:n.col, 'len': s:len(l:n)})
  endfor
  return s:carry(a:lines, l:base, a:notes, a:kind, a:lin, a:col)
endfunction

" Spec 3.7: a carry of a copy of `note` (as Notes() gives it): the base is
" `lines` as they are, so wherever the copy goes the original is still there,
" and the copy carried back onto it gives `lines` again.
function! songwriter#tab#carry#Copy(lines, note) abort
  return s:carry(a:lines, copy(a:lines), [a:note], 'note', a:note.lin, a:note.col)
endfunction

function! s:carry(lines, base, notes, kind, lin, col) abort
  let l:cur = -1
  let l:notes = []
  for l:n in a:notes
    if l:n.lin == a:lin && a:col >= l:n.col && a:col < l:n.col + s:len(l:n)
      let l:cur = len(l:notes)
    endif
    call add(l:notes, extend(copy(l:n), {'text0': l:n.text}))
  endfor
  return {'origin': copy(a:lines), 'base': a:base, 'notes': l:notes, 'dlin': 0, 'kind': a:kind,
        \ 'cur': l:cur, 'off': l:cur < 0 ? 0 : a:col - l:notes[l:cur].col,
        \ 'lin0': a:lin, 'col0': a:col}
endfunction

" The width of note `n` of a carry, with its separators.
function! s:len(n) abort
  return len(a:n.pre . a:n.text . a:n.post)
endfunction

" Spec 3.6.1: `note` (as model#Notes gives it) of line `lin`, `line`, as a
" carried note {'lin', 'col', 'pre', 'text', 'post'}: with the separators of
" its chain that have no note beyond them (3.1.3), before it when it is the
" chain's first note, after it when it is its last.
function! s:note(line, lin, note) abort
  let l:chain = songwriter#tab#model#ChainAt(a:line, a:note.col)
  let l:notes = filter(songwriter#tab#model#Notes(a:line),
        \ {_, n -> n.col >= l:chain.col && n.col < l:chain.col + l:chain.len})
  let l:pre = l:notes[0].col == a:note.col ? strpart(a:line, l:chain.col - 1, a:note.col - l:chain.col) : ''
  let l:end = a:note.col + a:note.len
  let l:post = l:notes[-1].col == a:note.col ? strpart(a:line, l:end - 1, l:chain.col + l:chain.len - l:end) : ''
  return {'lin': a:lin, 'col': a:note.col - len(l:pre), 'pre': l:pre, 'text': a:note.text, 'post': l:post}
endfunction

" Spec 3.6, 3.8.2, 7: `carry` with its notes `dlin` strings down (up when
" negative), their frets changing by `frets`, and, with `keep_pitch`, by the
" interval between the strings they leave and reach (7.3). Returns the new
" carry, or {'error': message} (3.6.3, 3.8.2, 7.4).
function! songwriter#tab#carry#Step(carry, dlin, frets, keep_pitch) abort
  let l:carry = copy(a:carry)
  let l:carry.dlin = a:carry.dlin + a:dlin
  let l:carry.notes = []
  let l:frets = 0
  for l:n in a:carry.notes
    let [l:from, l:to] = [l:n.lin + a:carry.dlin, l:n.lin + l:carry.dlin]
    if l:to < 0 || l:to >= len(a:carry.base)
      return {'error': printf('no string %s %s', a:dlin < 0 ? 'above' : 'below',
            \ songwriter#tab#model#Name(a:carry.base[l:from]))}
    endif
    let l:text = l:n.text
    if l:text =~# '^' . songwriter#grammar#Fret() . '$'
      let l:frets += 1
      let l:fret = str2nr(l:text, 10) + a:frets
      if a:keep_pitch && l:from != l:to
        let l:shift = s:interval(a:carry.base, l:from, l:to)
        if type(l:shift) == v:t_dict
          return l:shift
        endif
        let l:fret += l:shift
      endif
      let l:max = get(g:, 'songwriter_max_fret', 24)
      if l:fret < 0
        return {'error': a:frets < 0 ? 'the fret would go below 0'
              \ : printf('the fret would go below 0 on string %s', songwriter#tab#model#Name(a:carry.base[l:to]))}
      elseif l:fret > l:max
        return {'error': printf('the fret would go above %d', l:max)}
      endif
      let l:text = string(l:fret)
    endif
    call add(l:carry.notes, extend(copy(l:n), {'text': l:text}))
  endfor
  if a:frets != 0 && l:frets == 0
    return {'error': 'no fret to change'}
  endif
  return l:carry
endfunction

" Spec 7.3: the number of frets a note moving from string `from` to string `to`
" changes by to keep its pitch, or {'error'}. Strings are taken to be listed
" from the highest to the lowest, neighbouring strings less than an octave
" apart: the interval is read from pitch classes.
function! s:interval(lines, from, to) abort
  for l:lin in [a:from, a:to]
    if songwriter#pitch#Class(songwriter#tab#model#Name(a:lines[l:lin])) < 0
      return {'error': printf('string name %s is not a note', songwriter#tab#model#Name(a:lines[l:lin]))}
    endif
  endfor
  let [l:hi, l:lo] = a:to < a:from ? [a:to, a:from] : [a:from, a:to]
  let l:interval = (songwriter#pitch#Class(songwriter#tab#model#Name(a:lines[l:hi]))
        \ - songwriter#pitch#Class(songwriter#tab#model#Name(a:lines[l:lo])) + 12) % 12
  if l:interval == 0
    return {'error': printf('cannot tell the interval between strings %s and %s',
          \ songwriter#tab#model#Name(a:lines[l:hi]), songwriter#tab#model#Name(a:lines[l:lo]))}
  endif
  return a:to < a:from ? -l:interval : l:interval
endfunction

" Spec 3.6.1, 7.5: the tab with the notes of `carry` where they are: its base
" with each note (and its separators) written on its string, over the note
" starting on its time column there if any, room made for it
" (columns#PutNote). Returns {'lines', 'map'
" (where the columns of the base went), 'lin', 'col' (the cursor), 'home' (1
" when the notes are back where they started: the origin, untouched)}, or
" {'error'}.
function! songwriter#tab#carry#Render(carry) abort
  if a:carry.dlin == 0 && empty(filter(copy(a:carry.notes), 'v:val.text !=# v:val.text0'))
    return {'lines': copy(a:carry.origin), 'map': [], 'lin': a:carry.lin0, 'col': a:carry.col0, 'home': 1}
  endif
  let l:lines = copy(a:carry.base)
  let l:map = []
  " Right to left, so that the room one note makes moves the notes already
  " written, never one still to write.
  for l:n in sort(copy(a:carry.notes), {a, b -> b.col - a.col})
    let l:to = l:n.lin + a:carry.dlin
    let l:c = songwriter#tab#colmap#At(l:map, l:n.col)
    let l:there = songwriter#tab#model#NoteAt(l:lines[l:to], l:c + len(l:n.pre))
    if !empty(l:there) && l:there.col == l:c + len(l:n.pre)
      let l:lines[l:to] = songwriter#tab#model#Blank(l:lines[l:to], l:there)
    endif
    let l:room = songwriter#tab#columns#PutNote(l:lines, l:to, l:c, l:n.pre . l:n.text . l:n.post)
    if has_key(l:room, 'error')
      return l:room
    endif
    let l:lines = l:room.lines
    let l:map = songwriter#tab#colmap#Then(l:map, l:room.map)
  endfor
  if a:carry.cur >= 0
    let l:n = a:carry.notes[a:carry.cur]
    let l:lin = l:n.lin + a:carry.dlin
    let l:col = songwriter#tab#colmap#At(l:map, l:n.col) + min([a:carry.off, s:len(l:n) - 1])
  else
    " 7.6: off its notes, the cursor moves one string with them, inside the tab.
    let l:lin = max([0, min([a:carry.lin0 + a:carry.dlin, len(l:lines) - 1])])
    let l:n = a:carry.notes[0]
    let l:col = songwriter#tab#colmap#At(l:map, l:n.col) + len(l:n.pre)
  endif
  return {'lines': l:lines, 'map': l:map, 'lin': l:lin, 'col': l:col, 'home': 0}
endfunction

" Spec 3.6, 7.1: the notes `s`/`S` take from column `col` of line `lin`: the
" note covering it ('note'), or every note starting on the time column under
" it ('column'), as carried notes (s:note), or {'error'}. For a column, the
" cursor may be off its notes: on a column where a note of another string
" starts, or under a note of another string covering it.
function! songwriter#tab#carry#Notes(lines, lin, col, kind) abort
  if a:kind ==# 'note'
    let l:note = songwriter#tab#model#NoteAt(a:lines[a:lin], a:col)
    return empty(l:note) ? {'error': 'no note under the cursor'}
          \ : [s:note(a:lines[a:lin], a:lin, l:note)]
  endif
  let l:c = s:column_at(a:lines, a:lin, a:col)
  if l:c == 0
    return {'error': 'no time column under the cursor'}
  endif
  let l:notes = []
  for l:i in range(len(a:lines))
    let l:note = songwriter#tab#model#NoteAt(a:lines[l:i], l:c)
    if !empty(l:note) && l:note.col == l:c
      call add(l:notes, s:note(a:lines[l:i], l:i, l:note))
    endif
  endfor
  return l:notes
endfunction

" The start of the note covering `col` on line `lin`; off a note, the column
" `col` when a note on another string starts there, else the start of a note
" covering `col` on another string. 0: none.
function! s:column_at(lines, lin, col) abort
  let l:note = songwriter#tab#model#NoteAt(a:lines[a:lin], a:col)
  if !empty(l:note)
    return l:note.col
  endif
  let l:covering = []
  for l:l in a:lines
    let l:note = songwriter#tab#model#NoteAt(l:l, a:col)
    if !empty(l:note)
      if l:note.col == a:col
        return a:col
      endif
      call add(l:covering, l:note.col)
    endif
  endfor
  return empty(l:covering) ? 0 : min(l:covering)
endfunction

" Pure, spec 3.6, 7: one carry from scratch: the notes of `kind` at column
" `col` of line `lin` carried `dir` strings, keeping their pitch with
" `keep_pitch`. Returns Render's {'lines', 'map', 'lin', 'col'}, or {'error'}.
function! songwriter#tab#carry#Move(lines, lin, col, dir, keep_pitch, kind) abort
  let l:notes = songwriter#tab#carry#Notes(a:lines, a:lin, a:col, a:kind)
  if type(l:notes) == v:t_dict
    return l:notes
  endif
  let l:carry = songwriter#tab#carry#Step(songwriter#tab#carry#Lift(a:lines, l:notes, a:kind, a:lin, a:col),
        \ a:dir, 0, a:keep_pitch)
  return has_key(l:carry, 'error') ? l:carry : songwriter#tab#carry#Render(l:carry)
endfunction

" === Entry points ===

" The carry going on at the cursor of the block whose first line is `top`
" (state#Continuing), {} otherwise.
function! s:running(top) abort
  let l:carry = songwriter#tab#state#Continuing('carry')
  return !empty(l:carry) && l:carry.saved.origin.top == a:top ? l:carry : {}
endfunction

" Spec 3.6, 3.8, 7: carry the notes of `kind` ('note' or 'column') under the
" cursor `dir` strings down (up when negative), their frets changing by
" `frets`, keeping their pitch with `keep_pitch`. Straight after a carry of the
" same kind (cursor where it left it, buffer unchanged since), it goes on from
" where it is, in the same undo step (3.6.2); a `kind` of '' goes on with any
" carry. Otherwise the notes under the cursor are lifted first. The tab is
" linted with the cursor on the notes, and `.` repeats the carry (7.6). A
" refusal is echoed.
function! songwriter#tab#carry#Carry(kind, dir, frets, keep_pitch) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:carry = s:running(l:block.top)
  let l:going = !empty(l:carry) && (empty(a:kind) || l:carry.kind ==# a:kind)
  call songwriter#tab#edit#Do(function('s:step',
        \ [l:going ? l:carry : {}, empty(a:kind) ? 'note' : a:kind, a:dir, a:frets, a:keep_pitch]),
        \ {'join': l:going, 'prelint': !l:going, 'slot': 'close',
        \ 'repeat': printf('songwriter#tab#carry#Carry(%s, %d, %d, %d)', string(a:kind), a:dir, a:frets, a:keep_pitch)})
endfunction

" Pure. A step of `carry`, or of the notes of `kind` under the cursor of `ctx`,
" lifted, when it is {}, as an edit result (edit.vim). The carry keeps the
" snapshots of its origin and its base ('saved'), which the tab it renders is
" made from (edit.vim's 'base').
function! s:step(carry, kind, dir, frets, keep_pitch, ctx) abort
  let l:carry = a:carry
  if empty(l:carry)
    let l:notes = songwriter#tab#carry#Notes(a:ctx.block.lines, a:ctx.lin, a:ctx.col, a:kind)
    if type(l:notes) == v:t_dict
      return {'error': 'songwriter: ' . l:notes.error}
    endif
    let l:carry = songwriter#tab#carry#Lift(a:ctx.block.lines, l:notes, a:kind, a:ctx.lin, a:ctx.col)
    let l:carry.saved = s:saved(a:ctx.block, l:carry)
  endif
  return s:result(songwriter#tab#carry#Step(l:carry, a:dir, a:frets, a:keep_pitch))
endfunction

" The snapshots of a carry lifted from `block`: its origin, and its base, whose
" columns are those of the origin.
function! s:saved(block, carry) abort
  let l:origin = songwriter#tab#model#Snapshot(a:block)
  return {'origin': l:origin, 'base': songwriter#tab#edit#Derive(l:origin, a:carry.base, [])}
endfunction

" The edit result of rendering `carry` (or its refusal).
function! s:result(carry) abort
  if has_key(a:carry, 'error')
    return {'error': 'songwriter: ' . a:carry.error}
  endif
  let l:res = songwriter#tab#carry#Render(a:carry)
  if has_key(l:res, 'error')
    return {'error': 'songwriter: ' . l:res.error}
  endif
  return {'lines': l:res.lines, 'map': l:res.map, 'lin': l:res.lin, 'col': l:res.col,
        \ 'base': l:res.home ? a:carry.saved.origin : a:carry.saved.base,
        \ 'state': {'carry': a:carry}}
endfunction

" Spec 3.7: `<leader><leader>k` / `<leader><leader>j` (`dir` -1 / 1) copy the
" note under the cursor onto the string above / below, cursor on the copy,
" which is carried from there (Carry). Nothing happens off a note or with no
" string that way.
function! songwriter#tab#carry#Duplicate(dir) abort
  call songwriter#tab#edit#Do(function('s:duplicate', [a:dir]), {'slot': 'close',
        \ 'repeat': printf('songwriter#tab#carry#Duplicate(%d)', a:dir)})
endfunction

" Pure. The copy of the note under the cursor of `ctx`, one string `dir`.
function! s:duplicate(dir, ctx) abort
  let l:note = songwriter#tab#model#NoteAt(a:ctx.line, a:ctx.col)
  if empty(l:note)
    return {}
  endif
  let l:note = s:note(a:ctx.line, a:ctx.lin, l:note)
  let l:carry = songwriter#tab#carry#Copy(a:ctx.block.lines, l:note)
  let l:carry.off = a:ctx.col - l:note.col
  let l:carry.saved = s:saved(a:ctx.block, l:carry)
  let l:step = songwriter#tab#carry#Step(l:carry, a:dir, 0, 0)
  return has_key(l:step, 'error') ? {} : s:result(l:step)
endfunction

" Spec 3.6.4: visual `<leader>k` / `<leader>j` (`dir` -1 / 1) carry every note
" the selection touches one string, and select the same part of the tab
" around them again, so that pressing them again goes on in the run (3.6.2).
" The tab is linted. A refusal is echoed, the selection kept.
function! songwriter#tab#carry#Visual(dir) abort
  let l:sel = songwriter#selection#Get()
  execute "normal! \<Esc>"
  let l:block = songwriter#tab#model#Read(l:sel.cursor[1])
  if empty(l:block)
    return songwriter#selection#Select(l:sel)
  endif
  let l:carry = s:running(l:block.top)
  let l:going = !empty(l:carry) && l:carry.kind ==# 'visual'
  if !l:going
    let l:carry = s:lift_selection(l:block, l:sel)
    if empty(l:carry.notes)
      return songwriter#selection#Select(l:sel)
    endif
  endif
  let l:step = songwriter#tab#carry#Step(l:carry, a:dir, 0, 0)
  let l:res = has_key(l:step, 'error') ? l:step : songwriter#tab#carry#Render(l:step)
  if has_key(l:res, 'error')
    call songwriter#selection#Select(l:sel)
    return songwriter#tab#edit#Error('songwriter: ' . l:res.error)
  endif
  let l:lint = songwriter#tab#lint#Lint(l:res.lines)
  let l:map = songwriter#tab#colmap#Then(l:res.map, l:lint.map)
  if l:going
    silent! undojoin
  endif
  call songwriter#tab#edit#Write(l:block, {'lines': l:lint.lines, 'map': l:map,
        \ 'base': l:res.home ? l:step.saved.origin : l:step.saved.base})
  let l:new = copy(l:step.sel)
  for l:end in ['anchor', 'cursor']
    let [l:lin, l:col] = l:step.sel[l:end]
    let l:lin = max([0, min([l:lin + l:step.dlin, len(l:block.lines) - 1])])
    let l:new[l:end] = [0, l:block.start + l:lin, max([1, songwriter#tab#colmap#At(l:map, l:col)]), 0]
  endfor
  let l:new.cursor += [l:new.cursor[2]]
  call songwriter#selection#Select(l:new)
  call songwriter#tab#state#Set('carry', extend(l:step, {'line': line('.'), 'col': col('.')}))
endfunction

" The carry of the notes of `block` that selection `sel` touches, with the
" selection's ends kept as [lin, col] of the block ('sel').
function! s:lift_selection(block, sel) abort
  let l:notes = []
  for [l:lnum, l:first, l:last] in songwriter#selection#Spans(a:sel)
    if l:lnum < a:block.start || l:lnum > a:block.end
      continue
    endif
    let l:lin = l:lnum - a:block.start
    let l:line = a:block.lines[l:lin]
    for l:note in songwriter#tab#model#Notes(l:line)
      if songwriter#tab#model#NoteEnd(l:note) >= l:first + 1 && l:note.col <= l:last + 1
        call add(l:notes, s:note(l:line, l:lin, l:note))
      endif
    endfor
  endfor
  let l:lin = a:sel.cursor[1] - a:block.start
  let l:carry = songwriter#tab#carry#Lift(a:block.lines, l:notes, 'visual', l:lin, a:sel.cursor[2])
  let l:carry.saved = s:saved(a:block, l:carry)
  let l:carry.sel = extend(copy(a:sel), {'anchor': [a:sel.anchor[1] - a:block.start, a:sel.anchor[2]],
        \ 'cursor': [l:lin, a:sel.cursor[2]]})
  return l:carry
endfunction

" === The move state (spec 3.8) ===

" Whether the move state is on: entered with `m`, the cursor on a note of a tab
" line in tablature mode. `hjkl`, `J`/`K` and `<leader>j`/`<leader>k` then act
" on that note (keys.vim).
function! songwriter#tab#carry#Moving() abort
  return get(b:, 'songwriter_moving', 0) && songwriter#keys#InTabMode()
        \ && songwriter#grammar#IsTabLine(getline('.'))
        \ && !empty(songwriter#tab#model#NoteAt(getline('.'), col('.')))
endfunction

" Spec 3.8: the keys for `m` in tablature mode: on a note, enter the move
" state; elsewhere, Vim's own `m`.
function! songwriter#tab#carry#MoveKey() abort
  if empty(songwriter#tab#model#NoteAt(getline('.'), col('.')))
    return 'm'
  endif
  return "\<Cmd>call songwriter#tab#carry#StartMove()\<CR>"
endfunction

" Spec 3.8: enter the move state, leaving the insert state first.
function! songwriter#tab#carry#StartMove() abort
  if songwriter#tab#insert#Active()
    call songwriter#tab#insert#Escape()
  endif
  let b:songwriter_moving = 1
  call songwriter#tab#insert#Show('-- TAB MOVE --')
endfunction

" Spec 3.8.4: leave the move state.
function! songwriter#tab#carry#EndMove() abort
  if get(b:, 'songwriter_moving', 0)
    unlet b:songwriter_moving
    call songwriter#tab#insert#Show('')
  endif
endfunction

" Spec 3.8.4: the move state ends once the cursor has left the notes (run when
" the cursor moves or the text changes).
function! songwriter#tab#carry#Check() abort
  if get(b:, 'songwriter_moving', 0) && !songwriter#tab#carry#Moving()
    call songwriter#tab#carry#EndMove()
  endif
endfunction
