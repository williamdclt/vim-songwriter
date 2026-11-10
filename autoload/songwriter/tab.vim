" autoload/songwriter/tab.vim - tablature operations (spec [Tablature]).
"
" Public functions are the buffer entry points: they read the block with
" songwriter#tab#model#Read(), call a pure helper that returns new lines and/or
" a cursor column, and apply the result. Parsing and column arithmetic live in
" the model (tab/model.vim); the linter in tab/lint.vim.

" === Editing ===

" Append `--` to every string of the block.
function! songwriter#tab#AddDashes() abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call songwriter#tab#model#Write(l:block, map(copy(l:block.lines), "v:val . '--'"))
endfunction

" Spec [Tablature][[Editing]] 2: insert a dash after the cursor column on
" every string of the block.
function! songwriter#tab#AddDash() abort
  call s:insert_after_cursor('-')
endfunction

" Insert a bar pipe after the cursor column on every string of the block.
function! songwriter#tab#AddBar() abort
  call s:insert_after_cursor('|')
endfunction

function! s:insert_after_cursor(char) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call songwriter#tab#model#Write(l:block,
        \ songwriter#tab#model#InsertColumns(l:block.lines, col('.'), 1, a:char))
endfunction

" Spec [Tablature][[Editing]] 1: lint the block around the cursor.
function! songwriter#tab#Lint() abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call songwriter#tab#model#Write(l:block, songwriter#tab#lint#Lint(l:block.lines).lines)
endfunction

" Insert `chord` on a new line above the block, aligned to the cursor column.
function! songwriter#tab#TabChord(chord) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call append(l:block.start - 1, repeat(' ', col('.') - 1) . a:chord)
endfunction

" Spec [Tablature][[Editing]] 3.4: put `digit` in the cell under the cursor. On
" a dash it replaces the dash; on a note it replaces the whole note. Straight
" after a digit was typed (cursor still on it, buffer unchanged since), the next
" digit is appended instead, so two-digit frets are typed one key at a time
" (3.4.1). Then lint the block, keeping the cursor on the digit (4.1); this
" fills any open slot, in the same undo step as the slot, as is a digit appended
" to a fret (4.3.1). The insert state is kept. No-op off a tab line and on a
" separator (3.4.2).
function! songwriter#tab#EnterNote(digit) abort
  let l:line = getline('.')
  if !songwriter#grammar#IsTabLine(l:line)
    return
  endif
  let l:digit = a:digit . ''
  let l:col = col('.')
  let l:ch = (l:col <= len(l:line)) ? l:line[l:col - 1] : ''
  if songwriter#grammar#IsSeparatorChar(l:ch)
    return
  endif
  let l:typing = songwriter#tab#state#Get('typing')
  let l:insert = songwriter#tab#insert#Active()
  if !empty(l:typing) || !empty(songwriter#tab#state#Get('slot'))
    silent! undojoin
  endif
  let l:note = s:note_at(l:line, l:col)
  if !empty(l:typing) && l:typing.line == line('.') && l:typing.col == l:col
        \ && songwriter#grammar#IsFretChar(l:ch)
    call setline('.', l:line[0 : l:col - 1] . l:digit . l:line[l:col :])
    call cursor(line('.'), l:col + 1)
  elseif !empty(l:note)
    call setline('.', strpart(l:line, 0, l:note.col - 1) . l:digit
          \ . strpart(l:line, l:note.col - 1 + l:note.len))
    call cursor(line('.'), l:note.col)
  else
    call setline('.', l:line[0 : l:col - 2] . l:digit . l:line[l:col :])
    call cursor(line('.'), l:col)
  endif
  call songwriter#tab#edit#LintAndFollow(songwriter#tab#model#Read())
  call songwriter#tab#slots#Forget()
  call songwriter#tab#state#Set('typing', {'line': line('.'), 'col': col('.')})
  if l:insert
    call songwriter#tab#insert#Keep()
  endif
endfunction

" The note of `line` covering column `col`, or {}.
function! s:note_at(line, col) abort
  for l:n in songwriter#tab#model#Notes(a:line)
    if a:col >= l:n.col && a:col < l:n.col + l:n.len
      return l:n
    endif
  endfor
  return {}
endfunction

" Spec [Tablature][[Editing]] 3.1: open room for a new note on every string,
" to the right of the current note (side +1, `a`) or to its left (side -1,
" `i`), land the cursor on the new slot and enter the insert state. An open
" slot is closed first (4.3). The block is linted (4.2), and the slot is
" remembered until a note fills it or it is closed, which restores the tab as it
" was before the lint (4.3).
function! songwriter#tab#AddNote(side) abort
  call songwriter#tab#slots#Abandon()
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:mark = songwriter#tab#slots#Mark(a:side)
  let l:block = songwriter#tab#edit#LintAndFollow(l:block)
  let l:lin = songwriter#tab#model#CursorLin(l:block)
  let l:result = a:side > 0
        \ ? songwriter#tab#slots#Append(l:block, l:lin, col('.'))
        \ : songwriter#tab#slots#Prepend(l:block, l:lin, col('.'))
  call songwriter#tab#edit#Apply(l:block, l:result)
  if !empty(l:result)
    call songwriter#tab#slots#Open(l:mark)
  endif
endfunction

" Spec [Tablature][[Editing]] 5: append a new bar to the end of the tab with a
" slot in its middle, and land the cursor on it, ready for a note. Like `a`,
" the block is linted first (4.2) and the slot is remembered (4.3); closed, the
" tab goes back as it was.
function! songwriter#tab#AddBarSlot() abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:mark = songwriter#tab#slots#Mark(1)
  let l:block = songwriter#tab#edit#LintAndFollow(l:block)
  call songwriter#tab#edit#Apply(l:block, songwriter#tab#slots#AppendBar(l:block))
  call songwriter#tab#slots#Open(l:mark)
endfunction

" Spec [Tablature][[Editing]] 8: add an empty tab under (below 1, `o`) or
" over (below 0, `O`) the block around the cursor, with the same string names
" and a blank line between the two, and land on the slot in its middle, on the
" cursor's string. The slot is remembered as `a`'s is (4.3): a digit fills it,
" and abandoned, it is linted to an empty bar. An open slot is abandoned first.
function! songwriter#tab#NewTab(below) abort
  call songwriter#tab#slots#Abandon()
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:tab = songwriter#tab#slots#EmptyTab(l:block)
  let l:row = songwriter#tab#model#CursorLin(l:block)
  if a:below
    let l:last = l:block.end
    call append(l:last, [''] + l:tab.lines)
    let l:first = l:last + 2
  else
    call append(l:block.start - 1, l:tab.lines + [''])
    let l:first = l:block.start
  endif
  call cursor(l:first + l:row, l:tab.col)
  call songwriter#tab#slots#Open()
endfunction

" The string names of a new tab when none are given (standard guitar tuning).
let s:default_names = 'eBGDAE'

" Spec [Tablature][[Editing]] 9 (`:SongwriterNewTab`): add an empty tab with
" string `names` (one letter each, highest first; default eBGDAE). In a tab it
" goes under that tab; on a blank line it takes that line's place; elsewhere it
" goes under the cursor line. A blank line keeps it apart from a neighbouring
" tab. Tablature mode is turned on and the cursor lands on the slot of the top
" string, remembered as `o`'s is (8). Invalid names are refused with a message.
function! songwriter#tab#NewTabNamed(names) abort
  let l:names = empty(a:names) ? s:default_names : a:names
  if !songwriter#grammar#IsStringNames(l:names)
    call songwriter#tab#edit#Error('songwriter: string names are single letters, highest first (eBGDAE): ' . l:names)
    return
  endif
  call songwriter#tab#slots#Abandon()
  let l:tab = songwriter#tab#slots#EmptyTabNamed(split(l:names, '\zs'))
  let l:block = songwriter#tab#model#Read()
  if !empty(l:block)
    let l:after = l:block.end
  elseif getline('.') =~# '^\s*$'
    let l:after = line('.') - 1
    call deletebufline('%', line('.'))
  else
    let l:after = line('.')
  endif
  let l:lines = copy(l:tab.lines)
  let l:first = l:after + 1
  if l:after >= 1 && songwriter#grammar#IsTabLine(getline(l:after))
    call insert(l:lines, '')
    let l:first += 1
  endif
  if l:after < line('$') && songwriter#grammar#IsTabLine(getline(l:after + 1))
    call add(l:lines, '')
  endif
  if line('$') == 1 && getline(1) ==# '' && l:after == 0
    call setline(1, l:lines)
  else
    call append(l:after, l:lines)
  endif
  let b:songwriter_tabmode = 1
  call cursor(l:first, l:tab.col)
  call songwriter#tab#slots#Open()
endfunction

" === Linting after edits (spec [Tablature][[Editing]] 4) ===

" === Motions ===

" Spec [Tablature][[Editing]] 3.2: move to the next (dir +1) / previous (-1)
" note on the current line. No-op off a tab line or with no note that way.
" An open slot is closed first (4.3), and the move goes on from the slot's
" side (see s:from_slot).
function! songwriter#tab#MoveNote(dir) abort
  let l:slot = songwriter#tab#slots#Abandon()
  let l:line = getline('.')
  if !songwriter#grammar#IsTabLine(l:line)
    return
  endif
  let l:cols = map(songwriter#tab#model#Notes(l:line), 'v:val.col')
  let l:target = s:from_slot(l:slot, l:cols, col('.'), a:dir)
  if l:target != col('.')
    call cursor(line('.'), l:target)
  endif
endfunction

" Spec [Tablature][[Editing]] 3.5: the bar motions `W`/`B`/`E` (`key`),
" `count` times (see columns#BarStop). An open slot is closed first (4.3).
function! songwriter#tab#MoveBar(key, count) abort
  call songwriter#tab#slots#Abandon()
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:col = songwriter#tab#columns#BarStop(l:block.lines, getline('.'), col('.'), a:key, a:count)
  if l:col != col('.')
    call cursor(line('.'), l:col)
  endif
endfunction

" Spec [Tablature][[Editing]] 3.3: `l` (dir +1) / `h` (dir -1). In the normal
" state they only move (3.3.2): to the next/previous stop (see s:stops),
" crossing bar pipes; with none that way, the cursor stays. In the insert state,
" see s:insert_column.
function! songwriter#tab#MoveColumn(dir) abort
  if songwriter#tab#insert#Active()
    call s:insert_column(a:dir)
    return
  endif
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:target = songwriter#tab#model#Advance(s:stops(l:block), col('.'), a:dir, 1)
  if l:target != col('.')
    call cursor(line('.'), l:target)
  endif
endfunction

" Spec 3.3.3 and 5: `l`/`h` in the insert state, where the gaps between notes
" are stops too. On the open slot, close it (4.3) and move on (see
" s:leave_slot). On a note column, open a slot after it (`l`, as `a`) or
" before it (`h`, as `i`). Elsewhere, move as in the normal state, opening the
" slot of an empty bar landed in (3.3.4); `l` with nowhere to go in the tab's
" last bar adds a new bar (5).
function! s:insert_column(dir) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:col = col('.')
  let l:slot = songwriter#tab#state#Get('slot')
  if !empty(l:slot) && l:slot.col == l:col
        \ && songwriter#tab#model#Read(l:slot.line).start == l:block.start
    call s:leave_slot(l:block, l:slot, a:dir)
  elseif index(songwriter#tab#model#NoteColumns(l:block), l:col) >= 0
    call songwriter#tab#AddNote(a:dir)
  else
    let l:target = songwriter#tab#model#Advance(s:stops(l:block), l:col, a:dir, 1)
    if l:target != l:col
      call s:land(l:block, l:target)
    elseif a:dir > 0 && s:in_last_bar(getline('.'), l:col)
      call songwriter#tab#AddBarSlot()
    endif
  endif
endfunction

" Close `slot`, under the cursor, and move from where the cursor was before it
" opened (see s:from_slot), opening the slot of an empty bar landed in (3.3.4).
" With no stop that way the slot stays open, except that `l` from a slot after
" the last note of the tab's last bar makes a new bar (5) instead.
function! s:leave_slot(block, slot, dir) abort
  let l:col = col('.')
  let l:back = get(a:slot, 'side', 0) == -a:dir
  if !l:back && songwriter#tab#model#Advance(s:stops(a:block), l:col, a:dir, 1) == l:col
    if a:dir > 0 && s:in_last_bar(getline('.'), l:col) && s:bar_has_notes(a:block, l:col)
      call songwriter#tab#slots#Abandon()
      call songwriter#tab#AddBarSlot()
    endif
    return
  endif
  call songwriter#tab#slots#Abandon()
  let l:block = songwriter#tab#model#Read()
  call s:land(l:block, s:from_slot(a:slot, s:stops(l:block), col('.'), a:dir))
endfunction

" Where a move in direction `dir` goes among `stops` from column `col`, the
" cursor's column once `slot` (from slots#Abandon, {} if none) is closed. A
" slot opened on one side of a note (Mark's `side`) was between that note and
" the next one: moving back towards the note lands on it (`col` itself when it
" is a stop), moving on goes past it, to the next stop.
function! s:from_slot(slot, stops, col, dir) abort
  if get(a:slot, 'side', 0) == -a:dir && index(a:stops, a:col) >= 0
    return a:col
  endif
  return songwriter#tab#model#Advance(a:stops, a:col, a:dir, 1)
endfunction

" Move the cursor to column `target` of its line, opening the slot of the
" empty bar there if it is one (3.3.4).
function! s:land(block, target) abort
  if index(s:empty_bar_stops(getline('.'), songwriter#tab#model#NoteColumns(a:block)), a:target) >= 0
    let l:mark = songwriter#tab#slots#Mark(0)
    call cursor(line('.'), a:target)
    let l:mark.from = a:target
    call songwriter#tab#edit#Apply(a:block, songwriter#tab#slots#EmptyBar(a:block.lines,
          \ songwriter#tab#model#CursorLin(a:block), a:target))
    call songwriter#tab#slots#Open(l:mark)
  else
    call cursor(line('.'), a:target)
  endif
endfunction

" The stops of `l`/`h` on the cursor's line: the columns where any string of
" `block` has a note (3.3.1), and the middle of every empty bar (3.3.4).
function! s:stops(block) abort
  let l:cols = songwriter#tab#model#NoteColumns(a:block)
  return sort(l:cols + s:empty_bar_stops(getline('.'), l:cols), 'n')
endfunction

" Spec 3.3.4: the stops of the empty bars of `line` (no column of `cols`, the
" block's note columns, inside them): their middle dash. A bar with nothing
" between its pipes (`||`) has no stop.
function! s:empty_bar_stops(line, cols) abort
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

" True when the bar of the cursor's line around `col` has a note on any string
" of `block`.
function! s:bar_has_notes(block, col) abort
  let l:bar = songwriter#tab#model#BarAt(getline('.'), a:col)
  return !empty(filter(songwriter#tab#model#NoteColumns(a:block),
        \ 'songwriter#tab#model#InBar(v:val, l:bar)'))
endfunction

" True when `col` is in the last bar of a tab line that ends with a pipe:
" the line's final pipe is the first pipe at or after `col`.
function! s:in_last_bar(line, col) abort
  let l:pipes = songwriter#tab#model#Pipes(a:line)
  if empty(l:pipes) || l:pipes[-1] != len(a:line) || a:col > l:pipes[-1]
    return 0
  endif
  return empty(filter(copy(l:pipes), 'v:val >= a:col && v:val < l:pipes[-1]'))
endfunction

