" autoload/songwriter/keys.vim - context-dependent keys.
"
" Keys whose meaning depends on where the cursor is are declared in the tables
" below, one set per mode (n: normal, o: operator-pending, x: visual), and
" mapped by ftplugin/songwriter.vim as
"     {mode}noremap <buffer> <expr> {key} songwriter#keys#Dispatch({key}, {mode})
" Dispatch picks the action for the current context, most specific first, and
" falls back to the key's default behaviour:
"   1. s:tabmode[mode] - tablature mode on (<leader>t) and cursor on a tab line
"   2. s:tabline[mode] - cursor on a tab line
"   3. the key itself
" An action is an Ex command, run with <Cmd> (no mode change, no command-line
" echo), or, when it starts with `=`, an expression whose value is the keys to
" run (operators need this: they return `g@`). Special keys are written in <>
" notation ('<Esc>'). To add a context key: add it to a table.

let s:tabmode = {}
let s:tabline = {}

" Spec [Tablature][[Editing]] 3, 6 and 8.
let s:tabmode.n = {
      \ 'w': 'call songwriter#tab#MoveWord("w")',
      \ 'b': 'call songwriter#tab#MoveWord("b")',
      \ 'e': 'call songwriter#tab#MoveWord("e")',
      \ 'ge': 'call songwriter#tab#MoveWord("ge")',
      \ 'l': 'call songwriter#tab#MoveColumn(1)',
      \ 'h': 'call songwriter#tab#MoveColumn(-1)',
      \ 'L': 'call songwriter#tab#StepColumn(1)',
      \ 'H': 'call songwriter#tab#StepColumn(-1)',
      \ 'W': 'call songwriter#tab#MoveBar("W", v:count1)',
      \ 'B': 'call songwriter#tab#MoveBar("B", v:count1)',
      \ 'E': 'call songwriter#tab#MoveBar("E", v:count1)',
      \ 'a': 'call songwriter#tab#AddNote(1)',
      \ 'i': 'call songwriter#tab#AddNote(-1)',
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
      \ 'o': 'call songwriter#tab#NewTab(1)',
      \ 'O': 'call songwriter#tab#NewTab(0)',
      \ 'V': 'call songwriter#tab#visual#Column()',
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
  let s:tabmode.n[s:d] = 'call songwriter#tab#EnterNote(' . s:d . ')'
endfor
unlet s:d

" Spec 6.1 (text objects, `iW`/`aW` being `i|`/`a|`), 6.2.1 and 6.2.2 (string
" motions after an operator, `L`/`H` being `l`/`h`, 3.3.5) and 6.8
" (a doubled operator, `dd`, acts on the column).
let s:tabmode.o = {
      \ 'w': 'call songwriter#tab#operator#Motion("w")',
      \ 'b': 'call songwriter#tab#operator#Motion("b")',
      \ 'e': 'call songwriter#tab#operator#Motion("e")',
      \ 'ge': 'call songwriter#tab#operator#Motion("ge")',
      \ 'l': 'call songwriter#tab#operator#Motion("l")',
      \ 'h': 'call songwriter#tab#operator#Motion("h")',
      \ 'L': 'call songwriter#tab#operator#Motion("l")',
      \ 'H': 'call songwriter#tab#operator#Motion("h")',
      \ 'ic': 'call songwriter#tab#operator#Object("c", 0)',
      \ 'ac': 'call songwriter#tab#operator#Object("c", 1)',
      \ 'i|': 'call songwriter#tab#operator#Object("|", 0)',
      \ 'a|': 'call songwriter#tab#operator#Object("|", 1)',
      \ 'iW': 'call songwriter#tab#operator#Object("|", 0)',
      \ 'aW': 'call songwriter#tab#operator#Object("|", 1)',
      \ 'in': 'call songwriter#tab#operator#StringObject("n", 0)',
      \ 'an': 'call songwriter#tab#operator#StringObject("n", 1)',
      \ 'iw': 'call songwriter#tab#operator#StringObject("w", 0)',
      \ 'aw': 'call songwriter#tab#operator#StringObject("w", 1)',
      \ 'd': 'call songwriter#tab#operator#Doubled("d")',
      \ 'y': 'call songwriter#tab#operator#Doubled("y")',
      \ 'c': 'call songwriter#tab#operator#Doubled("c")',
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
      \ 'ic': 'call songwriter#tab#visual#Object("c", 0)',
      \ 'ac': 'call songwriter#tab#visual#Object("c", 1)',
      \ 'i|': 'call songwriter#tab#visual#Object("|", 0)',
      \ 'a|': 'call songwriter#tab#visual#Object("|", 1)',
      \ 'iW': 'call songwriter#tab#visual#Object("|", 0)',
      \ 'aW': 'call songwriter#tab#visual#Object("|", 1)',
      \ 'in': 'call songwriter#tab#visual#StringObject("n", 0)',
      \ 'an': 'call songwriter#tab#visual#StringObject("n", 1)',
      \ 'iw': 'call songwriter#tab#visual#StringObject("w", 0)',
      \ 'aw': 'call songwriter#tab#visual#StringObject("w", 1)',
      \ 'd': 'call songwriter#tab#visual#Op("d", v:register)',
      \ 'x': 'call songwriter#tab#visual#Op("d", v:register)',
      \ 'y': 'call songwriter#tab#visual#Op("y", v:register)',
      \ 'c': 'call songwriter#tab#visual#Op("c", v:register)',
      \ 'p': 'call songwriter#tab#visual#Put(v:register)',
      \ 'P': 'call songwriter#tab#visual#Put(v:register)',
      \ 'j': '=songwriter#tab#visual#Vertical("j")',
      \ 'k': '=songwriter#tab#visual#Vertical("k")',
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
  return uniq(sort(keys(s:tabmode[l:mode]) + keys(s:tabline[l:mode])))
endfunction

function! songwriter#keys#Dispatch(key, ...) abort
  let l:mode = a:0 ? a:1 : 'n'
  if songwriter#grammar#IsTabLine(getline('.'))
    if songwriter#keys#InTabMode() && has_key(s:tabmode[l:mode], a:key)
      return s:action(s:tabmode[l:mode][a:key])
    endif
    if has_key(s:tabline[l:mode], a:key)
      return s:action(s:tabline[l:mode][a:key])
    endif
  endif
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

" Spec [Tablature][[Editing]] 3.1.6: the state of tablature mode, for a status
" line: 'TAB INSERT' in the insert state, '' otherwise.
function! songwriter#keys#Mode() abort
  return songwriter#tab#insert#Active() ? 'TAB INSERT' : ''
endfunction

function! songwriter#keys#ToggleTabMode() abort
  let b:songwriter_tabmode = !songwriter#keys#InTabMode()
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
