" autoload/songwriter/tab/check.vim - the rules of the music, checked on every
" edit of a tab when g:songwriter_check is set (the test suite sets it). See
" design.md "Checking the rules".
"
" An edit gives new lines and a column map (tab/colmap.vim) from the lines it
" was given. Whatever it does, the music it does not touch must be as it was:
"   - every note it did not erase is a note with the same text, starting
"     where the map puts its column (so notes that started together still
"     do, and no note has been joined to another one);
"   - two of those notes that were in different chains of a string still
"     are (a dash keeps `5` and `/7` apart);
"   - once linted, the pipes of every string are aligned.
" A tab whose pipes are not aligned has no time columns yet: of an edit of it
" (a lint), only that each string keeps its notes in order is checked.
" What an edit changes on purpose it says: the notes it erases, as
" {'lin', 'col'} of the lines it was given (any column of the note), and the
" notes it writes, as {'lin', 'col'} of the lines it gives (where the note
" starts: a note written must be a note of its own there, not joined to the
" one before it). A note rewritten in place is one of each.

" True when the rules are checked.
function! songwriter#tab#check#On() abort
  return get(g:, 'songwriter_check', 0)
endfunction

" Throw, naming `what`, when the edit from `old` to `new` with column map `map`
" breaks a rule (Errors), in check mode.
function! songwriter#tab#check#Edit(what, old, new, map, erased, written) abort
  if !songwriter#tab#check#On()
    return
  endif
  let l:errors = songwriter#tab#check#Errors(a:old, a:new, a:map, a:erased, a:written)
  if !empty(l:errors)
    throw printf('songwriter: check: %s: %s', a:what, join(l:errors, '; '))
  endif
endfunction

" Throw, naming `what`, when the pipes of the linted `lines` are not aligned,
" in check mode.
function! songwriter#tab#check#Lint(what, lines) abort
  if !songwriter#tab#check#On()
    return
  endif
  let l:errors = songwriter#tab#check#Linted(a:lines)
  if !empty(l:errors)
    throw printf('songwriter: check: %s: %s', a:what, join(l:errors, '; '))
  endif
endfunction

" Throw, in check mode, when a loop that should end has run `n` times.
function! songwriter#tab#check#Cap(what, n) abort
  if songwriter#tab#check#On()
    throw printf('songwriter: check: %s did not settle in %d passes', a:what, a:n)
  endif
endfunction

" Pure. The rules the edit from `old` to `new`, of column map `map`, breaks,
" erasing the notes `erased` (of `old`) and writing the notes `written` (of
" `new`): a list of messages, [] when none.
function! songwriter#tab#check#Errors(old, new, map, erased, written) abort
  if !empty(songwriter#tab#check#Linted(a:old))
    return s:music_kept(a:old, a:new, a:erased, a:written)
  endif
  let l:errors = []
  for l:lin in range(min([len(a:old), len(a:new)]))
    let l:name = songwriter#tab#model#Name(a:old[l:lin])
    let l:kept = []
    for l:n in songwriter#tab#model#Notes(a:old[l:lin])
      if s:listed(a:erased, l:lin, l:n.col, l:n.col + l:n.len - 1)
        continue
      endif
      let l:m = songwriter#tab#colmap#At(a:map, l:n.col)
      if l:m == 0
        continue
      endif
      let l:new = songwriter#tab#model#NoteAt(a:new[l:lin], l:m)
      if !empty(l:new) && s:listed(a:written, l:lin, l:new.col, l:new.col)
        continue
      endif
      if empty(l:new) || l:new.col != l:m || l:new.text !=# l:n.text
        call add(l:errors, printf('note %s %d (%s) -> %d: %s', l:name, l:n.col, l:n.text, l:m,
              \ empty(l:new) ? strpart(a:new[l:lin], l:m - 1, l:n.len) : l:new.text))
        continue
      endif
      call add(l:kept, [l:n.col, l:m])
    endfor
    for l:w in filter(copy(a:written), 'v:val.lin == l:lin')
      let l:new = songwriter#tab#model#NoteAt(a:new[l:lin], l:w.col)
      if empty(l:new) || l:new.col != l:w.col
        call add(l:errors, printf('written %s %d: %s', l:name, l:w.col,
              \ empty(l:new) ? 'no note' : l:new.text))
      endif
    endfor
    for l:k in range(max([0, len(l:kept) - 1]))
      let [l:a, l:b] = [l:kept[l:k], l:kept[l:k + 1]]
      if !s:same_chain(a:old[l:lin], l:a[0], l:b[0]) && s:same_chain(a:new[l:lin], l:a[1], l:b[1])
        call add(l:errors, printf('chains %s %d, %d joined', l:name, l:a[0], l:b[0]))
      endif
    endfor
  endfor
  return l:errors
endfunction

" Pure. Every note of `lines`, as {'lin', 'col'}: what an edit that clears
" them erases.
function! songwriter#tab#check#Notes(lines) abort
  let l:res = []
  for l:lin in range(len(a:lines))
    call extend(l:res, map(songwriter#tab#model#Notes(a:lines[l:lin]), {_, n -> {'lin': l:lin, 'col': n.col}}))
  endfor
  return l:res
endfunction

" Pure. The rules the linted tab `lines` breaks: its pipes are the same on
" every string.
function! songwriter#tab#check#Linted(lines) abort
  let l:pipes = map(copy(a:lines), 'songwriter#tab#model#Pipes(v:val)')
  return len(uniq(sort(l:pipes))) > 1 ? ['pipes not aligned'] : []
endfunction

" Pure. The rules broken by an edit of `old`, whose pipes are not aligned:
" its columns are not time columns, so a column map cannot say where the
" music went (only lint gets such a tab, to align it). Each string keeps its
" notes in order, when the edit erases and writes none.
function! s:music_kept(old, new, erased, written) abort
  if !empty(a:erased) || !empty(a:written)
    return []
  endif
  let l:errors = []
  for l:lin in range(min([len(a:old), len(a:new)]))
    let [l:was, l:is] = map([a:old[l:lin], a:new[l:lin]],
          \ {_, l -> map(songwriter#tab#model#Notes(l), 'v:val.text')})
    if l:was !=# l:is
      call add(l:errors, printf('notes %s %s -> %s', songwriter#tab#model#Name(a:old[l:lin]),
            \ join(l:was), join(l:is)))
    endif
  endfor
  return l:errors
endfunction

" True when `list` ({'lin', 'col'}) has an entry on line `lin` between columns
" `s` and `e`.
function! s:listed(list, lin, s, e) abort
  for l:p in a:list
    if l:p.lin == a:lin && l:p.col >= a:s && l:p.col <= a:e
      return 1
    endif
  endfor
  return 0
endfunction

" True when columns `a` and `b` of `line` are in the same chain.
function! s:same_chain(line, a, b) abort
  let l:ch = songwriter#tab#model#ChainAt(a:line, a:a)
  return !empty(l:ch) && a:b < l:ch.col + l:ch.len
endfunction
