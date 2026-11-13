" autoload/songwriter/keys.vim - context-dependent keys.
"
" Keys whose meaning depends on where the cursor is are declared in the tables
" below, one set per mode (n: normal, o: operator-pending, x: visual), and
" mapped by ftplugin/songwriter.vim as
"     {mode}noremap <buffer> <expr> {key} songwriter#keys#Dispatch({key}, {mode})
" Dispatch picks the action for the current context, most specific first, and
" falls back to the key's default behaviour:
"   0. s:moving[mode]  - tablature mode, moving a duplicated note
"                        (songwriter#tab#carry#Moving)
"   1. s:typed[mode]   - tablature mode, insert state, straight after a note
"                        was typed (songwriter#tab#typing#JustTyped)
"   2. s:tabinsert[mode] - tablature mode, insert state
"   3. s:tabmode[mode] - tablature mode on (<leader>t) and cursor on a tab line
"   4. s:tabline[mode] - cursor on a tab line
"   5. s:annotation[mode] - tablature mode, cursor on an annotation line of a
"                        tab ([[Annotations]] 1)
"   6. the key itself
" An action is an Ex command, run with <Cmd> (no mode change, no command-line
" echo), or, when it starts with `=`, an expression whose value is the keys to
" run (operators need this: they return `g@`). Special keys are written in <>
" notation ('<Esc>'). To add a context key: add it to a table.

let s:moving = {'n': {}, 'o': {}, 'x': {}}
let s:typed = {'n': {}, 'o': {}, 'x': {}}
let s:tabinsert = {'n': {}, 'o': {}, 'x': {}}
let s:tabmode = {}
let s:tabline = {}
let s:annotation = {'n': {}, 'o': {}, 'x': {}}

" Spec [Tablature][[Editing]] 3.7: `hjkl` are the arrows while a duplicated
" note is moved.
for [s:hjkl, s:arrow] in [['h', '<Left>'], ['j', '<Down>'], ['k', '<Up>'], ['l', '<Right>']]
  let s:moving.n[s:hjkl] = printf('call songwriter#tab#carry#Move(%s)', string(s:arrow))
endfor
unlet s:hjkl s:arrow

" Spec [Tablature][[Editing]] 3.4.1.3: separator keys write a separator
" straight after a typed note.
for s:sep in ['h', 'p', 'b', 'r', 't', 's', '/', '~']
  let s:typed.n[s:sep] = printf('call songwriter#tab#typing#EnterSeparator(%s)', string(s:sep))
endfor
unlet s:sep
" Spec 3.4.1.2: `<Space>` is `l`.
let s:tabinsert.n['<Space>'] = 'call songwriter#tab#motion#MoveColumn(1)'
" Spec 3.6: the arrows carry the note under the cursor.
for s:arrow in ['<Up>', '<Down>', '<Left>', '<Right>']
  let s:tabinsert.n[s:arrow] = printf('=songwriter#tab#carry#Key(%s)', string(s:arrow))
endfor
unlet s:arrow

" Spec [Tablature][[Editing]] 3, 6, 8 and 10.
let s:tabmode.n = {
      \ 'w': 'call songwriter#tab#motion#MoveWord("w")',
      \ 'b': 'call songwriter#tab#motion#MoveWord("b")',
      \ 'e': 'call songwriter#tab#motion#MoveWord("e")',
      \ 'ge': 'call songwriter#tab#motion#MoveWord("ge")',
      \ 'l': 'call songwriter#tab#motion#MoveColumn(1)',
      \ 'h': 'call songwriter#tab#motion#MoveColumn(-1)',
      \ 'L': 'call songwriter#tab#motion#StepColumn(1)',
      \ 'H': 'call songwriter#tab#motion#StepColumn(-1)',
      \ 'W': 'call songwriter#tab#motion#MoveBar("W", v:count1)',
      \ 'B': 'call songwriter#tab#motion#MoveBar("B", v:count1)',
      \ 'E': 'call songwriter#tab#motion#MoveBar("E", v:count1)',
      \ 'a': 'call songwriter#tab#slots#AddNote(1)',
      \ 'i': 'call songwriter#tab#slots#AddNote(-1)',
      \ '<Esc>': 'call songwriter#tab#insert#Escape()',
      \ 'd': '=songwriter#tab#operator#Start("d")',
      \ 'y': '=songwriter#tab#operator#Start("y")',
      \ 'c': '=songwriter#tab#operator#Start("c")',
      \ 'Y': '=songwriter#tab#operator#StartOn("y", "column")',
      \ 'D': '=songwriter#tab#operator#StartOn("d", "bar-end")',
      \ 'C': '=songwriter#tab#operator#StartOn("c", "bar-end")',
      \ '>>': 'call songwriter#tab#operator#Shift(1, v:count1)',
      \ '<<': 'call songwriter#tab#operator#Shift(-1, v:count1)',
      \ 'gp': 'call songwriter#tab#operator#Overlay(v:register)',
      \ 'x': 'call songwriter#tab#operator#EraseOrMute(v:count1, v:register)',
      \ 'p': 'call songwriter#tab#operator#Put(0, v:count1, v:register)',
      \ 'P': 'call songwriter#tab#operator#Put(1, v:count1, v:register)',
      \ '.': '=songwriter#tab#repeat#Repeat()',
      \ 'o': 'call songwriter#tab#newtab#NewTab(1)',
      \ 'O': 'call songwriter#tab#newtab#NewTab(0)',
      \ 'V': 'call songwriter#tab#visual#Column()',
      \ '=': 'call songwriter#tab#voicings#Prompt()',
      \ '+': 'call songwriter#tab#voicings#Plus()',
      \ }
" Spec 7: `s` (keep the fret) / `S` (keep the pitch), then `k`/`j` (the note
" under the cursor) or `K`/`J` (its whole time column), up/down a string.
for [s:prefix, s:pitch] in [['s', 0], ['S', 1]]
  for [s:dirkey, s:dir] in [['k', -1], ['j', 1]]
    let s:tabmode.n[s:prefix . s:dirkey] = printf('call songwriter#tab#strings#Change(%d, %d, 0)', s:dir, s:pitch)
    let s:tabmode.n[s:prefix . toupper(s:dirkey)] = printf('call songwriter#tab#strings#Change(%d, %d, 1)', s:dir, s:pitch)
  endfor
endfor
unlet s:prefix s:pitch s:dirkey s:dir
for s:d in range(10)
  let s:tabmode.n[s:d] = 'call songwriter#tab#typing#EnterNote(' . s:d . ')'
endfor
unlet s:d

" Spec 6.2.1 and 6.2.2 (string motions after an operator, `L`/`H` being
" `l`/`h`, 3.3.5), 6.2.4 (`j`/`k`/`J`/`K` across strings) and 6.8 (a doubled
" operator, `dd`, acts on the column; `<leader>pp` too, 12.1). The
" text objects are added to this table and the visual one below.
let s:tabmode.o = {
      \ 'w': 'call songwriter#tab#operator#Motion("w")',
      \ 'b': 'call songwriter#tab#operator#Motion("b")',
      \ 'e': 'call songwriter#tab#operator#Motion("e")',
      \ 'ge': 'call songwriter#tab#operator#Motion("ge")',
      \ 'l': 'call songwriter#tab#operator#Motion("l")',
      \ 'h': 'call songwriter#tab#operator#Motion("h")',
      \ 'L': 'call songwriter#tab#operator#Motion("l")',
      \ 'H': 'call songwriter#tab#operator#Motion("h")',
      \ 'j': 'call songwriter#tab#operator#Across("j")',
      \ 'k': 'call songwriter#tab#operator#Across("k")',
      \ 'J': 'call songwriter#tab#operator#Across("J")',
      \ 'K': 'call songwriter#tab#operator#Across("K")',
      \ 'd': 'call songwriter#tab#operator#Doubled("d")',
      \ 'y': 'call songwriter#tab#operator#Doubled("y")',
      \ 'c': 'call songwriter#tab#operator#Doubled("c")',
      \ 'p': 'call songwriter#tab#operator#Doubled("p")',
      \ }

" Spec 6.9.
let s:tabmode.x = {
      \ 'w': 'call songwriter#tab#visual#Motion("w")',
      \ 'b': 'call songwriter#tab#visual#Motion("b")',
      \ 'e': 'call songwriter#tab#visual#Motion("e")',
      \ 'ge': 'call songwriter#tab#visual#Motion("ge")',
      \ 'l': 'call songwriter#tab#visual#Motion("l")',
      \ 'h': 'call songwriter#tab#visual#Motion("h")',
      \ 'L': 'call songwriter#tab#visual#Motion("l")',
      \ 'H': 'call songwriter#tab#visual#Motion("h")',
      \ 'W': 'call songwriter#tab#visual#Motion("W")',
      \ 'B': 'call songwriter#tab#visual#Motion("B")',
      \ 'E': 'call songwriter#tab#visual#Motion("E")',
      \ 'd': 'call songwriter#tab#visual#Op("d", v:register)',
      \ 'x': 'call songwriter#tab#visual#Op("d", v:register)',
      \ 'y': 'call songwriter#tab#visual#Op("y", v:register)',
      \ 'c': 'call songwriter#tab#visual#Op("c", v:register)',
      \ 'p': 'call songwriter#tab#visual#Put(v:register)',
      \ 'P': 'call songwriter#tab#visual#Put(v:register)',
      \ 'j': '=songwriter#tab#visual#Vertical("j")',
      \ 'k': '=songwriter#tab#visual#Vertical("k")',
      \ }
" Spec 6.1 / 6.9.1, 6.9.6: the text objects, the same after an operator
" (operator.vim) and in visual mode (visual.vim): [key, function, kind,
" around]. `iW`/`aW` are `i|`/`a|`.
for [s:key, s:fn, s:kind, s:around] in [
      \ ['ic', 'Object', 'c', 0], ['ac', 'Object', 'c', 1],
      \ ['i|', 'Object', '|', 0], ['a|', 'Object', '|', 1],
      \ ['iW', 'Object', '|', 0], ['aW', 'Object', '|', 1],
      \ ['in', 'StringObject', 'n', 0], ['an', 'StringObject', 'n', 1],
      \ ['iw', 'StringObject', 'w', 0], ['aw', 'StringObject', 'w', 1]]
  for [s:mode, s:module] in [['o', 'operator'], ['x', 'visual']]
    let s:tabmode[s:mode][s:key] = printf('call songwriter#tab#%s#%s(%s, %d)',
          \ s:module, s:fn, string(s:kind), s:around)
  endfor
endfor
unlet s:key s:fn s:kind s:around s:mode s:module
" [[Annotations]] 8: the annotation word above the column.
for [s:key, s:around] in [['ia', 0], ['aa', 1]]
  let s:tabmode.o[s:key] = printf('=songwriter#tab#annotate#Object(%d)', s:around)
  let s:tabmode.x[s:key] = printf('call songwriter#tab#annotate#Select(%d)', s:around)
endfor
unlet s:key s:around
" [[Annotations]] 9: between the strings and the annotation lines.
let s:tabmode.n.gk = 'call songwriter#tab#annotate#Up()'
let s:annotation.n = {
      \ 'gk': 'call songwriter#tab#annotate#Up()',
      \ 'gj': 'call songwriter#tab#annotate#Down()',
      \ }

" Spec [Tablature][[Motions]].
let s:tabline.n = {
      \ 'w': 'call songwriter#keys#TabWord(1)',
      \ 'b': 'call songwriter#keys#TabWord(-1)',
      \ 'W': 'call songwriter#keys#JumpBarLine(1)',
      \ 'B': 'call songwriter#keys#JumpBarLine(-1)',
      \ }
let s:tabline.o = {
      \ 'W': 'call songwriter#keys#JumpBarLine(1)',
      \ 'B': 'call songwriter#keys#JumpBarLine(-1)',
      \ }
let s:tabline.x = {
      \ 'W': 'call songwriter#keys#JumpBarLine(1)',
      \ 'B': 'call songwriter#keys#JumpBarLine(-1)',
      \ }

" Every key of `mode` (default 'n') that needs a dispatching map.
function! songwriter#keys#ContextKeys(...) abort
  let l:mode = a:0 ? a:1 : 'n'
  return uniq(sort(keys(s:moving[l:mode]) + keys(s:typed[l:mode]) + keys(s:tabinsert[l:mode])
        \ + keys(s:tabmode[l:mode]) + keys(s:tabline[l:mode]) + keys(s:annotation[l:mode])))
endfunction

function! songwriter#keys#Dispatch(key, ...) abort
  let l:mode = a:0 ? a:1 : 'n'
  if songwriter#grammar#IsTabLine(getline('.'))
    if songwriter#keys#InTabMode()
      if songwriter#tab#carry#Moving()
        if has_key(s:moving[l:mode], a:key)
          return s:action(s:moving[l:mode][a:key])
        endif
        " Spec 3.7: a lone <leader> ends the move. Its own map is replaced
        " by this one when the leader is a context key (a <Space> leader).
        if l:mode ==# 'n' && s:key(a:key) ==# get(g:, 'mapleader', '\')
          return s:action('call songwriter#tab#carry#EndMove()')
        endif
      endif
      if has_key(s:typed[l:mode], a:key) && songwriter#tab#typing#JustTyped()
        return s:action(s:typed[l:mode][a:key])
      endif
      if has_key(s:tabinsert[l:mode], a:key) && songwriter#tab#insert#Active()
        return s:action(s:tabinsert[l:mode][a:key])
      endif
      if has_key(s:tabmode[l:mode], a:key)
        return s:action(s:tabmode[l:mode][a:key])
      endif
    endif
    if has_key(s:tabline[l:mode], a:key)
      return s:action(s:tabline[l:mode][a:key])
    endif
  elseif has_key(s:annotation[l:mode], a:key) && songwriter#keys#InTabMode()
        \ && songwriter#grammar#IsAnnotationLine(getline('.'))
        \ && !empty(songwriter#tab#model#Around(line('.')))
    return s:action(s:annotation[l:mode][a:key])
  endif
  return s:key(a:key)
endfunction

" The keys `key` stands for, from its <> notation ('<Esc>').
function! s:key(key) abort
  return a:key =~# '^<.\+>$' ? eval('"\' . a:key . '"') : a:key
endfunction

function! s:action(action) abort
  return a:action[0] ==# '=' ? eval(a:action[1:]) : "\<Cmd>" . a:action . "\<CR>"
endfunction

" Tablature mode: a buffer-local flag, set on by the ftplugin and off when
" unset.
function! songwriter#keys#InTabMode() abort
  return get(b:, 'songwriter_tabmode', 0)
endfunction

" Spec [Tablature][[Editing]] 3.1.6, 3.7: the state of tablature mode, for a
" status line: 'TAB MOVE' while a duplicated note is moved, 'TAB INSERT' in
" the insert state, '' otherwise.
function! songwriter#keys#Mode() abort
  if songwriter#tab#carry#Moving()
    return 'TAB MOVE'
  endif
  return songwriter#tab#insert#Active() ? 'TAB INSERT' : ''
endfunction

function! songwriter#keys#ToggleTabMode() abort
  let b:songwriter_tabmode = !songwriter#keys#InTabMode()
  call songwriter#tab#highlight#Update()
  echo (b:songwriter_tabmode ? 'songwriter: tablature mode on' : 'songwriter: tablature mode off')
endfunction

" Spec [Tablature][[Motions]] 1-2: on a tab line `w`/`b` stop on notes, string
" names and pipes, never on dashes.
function! songwriter#keys#TabWord(dir) abort
  call search(songwriter#grammar#TabWordStop(), a:dir > 0 ? 'W' : 'bW')
endfunction

" Spec [Tablature][[Motions]] 3-4: `W`/`B` jump to the next/previous pipe.
function! songwriter#keys#JumpBarLine(dir) abort
  let v:searchforward = a:dir > 0
  call search(songwriter#grammar#Pipe(), a:dir > 0 ? 'W' : 'bW')
endfunction
