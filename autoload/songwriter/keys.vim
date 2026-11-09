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
      \ 'w': 'call songwriter#tab#MoveNote(1)',
      \ 'b': 'call songwriter#tab#MoveNote(-1)',
      \ 'l': 'call songwriter#tab#MoveColumn(1)',
      \ 'h': 'call songwriter#tab#MoveColumn(-1)',
      \ 'a': 'call songwriter#tab#AddNote(1)',
      \ 'i': 'call songwriter#tab#AddNote(-1)',
      \ '<Esc>': 'call songwriter#tab#slots#Abandon()',
      \ 'd': '=songwriter#tab#operator#Start("d")',
      \ 'y': '=songwriter#tab#operator#Start("y")',
      \ 'c': '=songwriter#tab#operator#Start("c")',
      \ 'Y': '=songwriter#tab#operator#StartOn("y", "column")',
      \ 'D': '=songwriter#tab#operator#StartOn("d", "bar-end")',
      \ 'C': '=songwriter#tab#operator#StartOn("c", "bar-end")',
      \ '>>': 'call songwriter#tab#operator#Shift(1, v:count1)',
      \ '<<': 'call songwriter#tab#operator#Shift(-1, v:count1)',
      \ 'gp': 'call songwriter#tab#operator#Overlay(v:register)',
      \ 'x': 'call songwriter#tab#operator#Erase(v:count1, v:register)',
      \ 'p': 'call songwriter#tab#operator#Put(0, v:count1, v:register)',
      \ 'P': 'call songwriter#tab#operator#Put(1, v:count1, v:register)',
      \ '.': '=songwriter#tab#operator#Repeat()',
      \ 'o': 'call songwriter#tab#NewTab(1)',
      \ 'O': 'call songwriter#tab#NewTab(0)',
      \ 'V': 'call songwriter#tab#operator#VisualColumn()',
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

" Spec 6.1 (text objects), 6.2.1 (pure motions after an operator) and 6.8
" (a doubled operator, `dd`, acts on the column).
let s:tabmode.o = {
      \ 'w': 'call songwriter#tab#operator#Motion("w")',
      \ 'b': 'call songwriter#tab#operator#Motion("b")',
      \ 'l': 'call songwriter#tab#operator#Motion("l")',
      \ 'h': 'call songwriter#tab#operator#Motion("h")',
      \ 'ic': 'call songwriter#tab#operator#Object("c", 0)',
      \ 'ac': 'call songwriter#tab#operator#Object("c", 1)',
      \ 'i|': 'call songwriter#tab#operator#Object("|", 0)',
      \ 'a|': 'call songwriter#tab#operator#Object("|", 1)',
      \ 'in': 'call songwriter#tab#operator#NoteObject(0)',
      \ 'an': 'call songwriter#tab#operator#NoteObject(1)',
      \ 'd': 'call songwriter#tab#operator#Doubled("d")',
      \ 'y': 'call songwriter#tab#operator#Doubled("y")',
      \ 'c': 'call songwriter#tab#operator#Doubled("c")',
      \ }
" Spec 6.9.
let s:tabmode.x = {
      \ 'w': 'call songwriter#tab#operator#VisualMotion("w")',
      \ 'b': 'call songwriter#tab#operator#VisualMotion("b")',
      \ 'l': 'call songwriter#tab#operator#VisualMotion("l")',
      \ 'h': 'call songwriter#tab#operator#VisualMotion("h")',
      \ 'ic': 'call songwriter#tab#operator#VisualObject("c", 0)',
      \ 'ac': 'call songwriter#tab#operator#VisualObject("c", 1)',
      \ 'i|': 'call songwriter#tab#operator#VisualObject("|", 0)',
      \ 'a|': 'call songwriter#tab#operator#VisualObject("|", 1)',
      \ 'in': 'call songwriter#tab#operator#VisualNoteObject(0)',
      \ 'an': 'call songwriter#tab#operator#VisualNoteObject(1)',
      \ 'd': 'call songwriter#tab#operator#VisualOp("d", v:register)',
      \ 'x': 'call songwriter#tab#operator#VisualOp("d", v:register)',
      \ 'y': 'call songwriter#tab#operator#VisualOp("y", v:register)',
      \ 'c': 'call songwriter#tab#operator#VisualOp("c", v:register)',
      \ 'p': 'call songwriter#tab#operator#VisualPut(v:register)',
      \ 'P': 'call songwriter#tab#operator#VisualPut(v:register)',
      \ 'j': '=songwriter#tab#operator#VisualVertical("j")',
      \ 'k': '=songwriter#tab#operator#VisualVertical("k")',
      \ }

" Spec [Tablature][[Motions]].
let s:tabline.n = {
      \ 'w': 'call songwriter#keys#TabWord(1)',
      \ 'b': 'call songwriter#keys#TabWord(-1)',
      \ 'L': 'call songwriter#keys#JumpBarLine(1)',
      \ 'H': 'call songwriter#keys#JumpBarLine(-1)',
      \ }
let s:tabline.o = {
      \ 'L': 'call songwriter#keys#JumpBarLine(1)',
      \ 'H': 'call songwriter#keys#JumpBarLine(-1)',
      \ }
let s:tabline.x = {
      \ 'L': 'call songwriter#keys#JumpBarLine(1)',
      \ 'H': 'call songwriter#keys#JumpBarLine(-1)',
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

" Tablature mode: a buffer-local flag, off by default.
function! songwriter#keys#InTabMode() abort
  return get(b:, 'songwriter_tabmode', 0)
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

" Spec [Tablature][[Motions]] 3-4: `L`/`H` jump to the next/previous pipe.
function! songwriter#keys#JumpBarLine(dir) abort
  let v:searchforward = a:dir > 0
  call search('|', a:dir > 0 ? 'W' : 'bW')
endfunction
