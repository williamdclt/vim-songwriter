" autoload/songwriter/keys.vim - context-dependent keys.
"
" Keys whose meaning depends on where the cursor is are declared in the tables
" below and mapped by ftplugin/songwriter.vim as
"     nnoremap <buffer> <expr> {key} songwriter#keys#Dispatch({key})
" Dispatch picks the action for the current context, most specific first, and
" falls back to the key's default behaviour:
"   1. s:tabmode_keys - tablature mode on (<leader>t) and cursor on a tab line
"   2. s:tabline_keys - cursor on a tab line
"   3. the key itself
" An action is an Ex command, run with <Cmd> (no mode change, no command-line
" echo). To add a context key: add it to a table and to s:context_keys.

" Spec [Tablature][[Editing]] 3.
let s:tabmode_keys = {
      \ 'w': 'call songwriter#tab#MoveNote(1)',
      \ 'b': 'call songwriter#tab#MoveNote(-1)',
      \ 'l': 'call songwriter#tab#MoveColumn(1)',
      \ 'h': 'call songwriter#tab#MoveColumn(-1)',
      \ 'a': 'call songwriter#tab#AddNote(1)',
      \ 'i': 'call songwriter#tab#AddNote(-1)',
      \ }
for s:d in range(10)
  let s:tabmode_keys[s:d] = 'call songwriter#tab#EnterNote(' . s:d . ')'
endfor
unlet s:d

" Spec [Tablature][[Motions]].
let s:tabline_keys = {
      \ 'w': 'call songwriter#keys#TabWord(1)',
      \ 'b': 'call songwriter#keys#TabWord(-1)',
      \ 'L': 'call songwriter#keys#JumpBarLine(1)',
      \ 'H': 'call songwriter#keys#JumpBarLine(-1)',
      \ }

" Every key that needs a dispatching map.
function! songwriter#keys#ContextKeys() abort
  return uniq(sort(keys(s:tabmode_keys) + keys(s:tabline_keys)))
endfunction

function! songwriter#keys#Dispatch(key) abort
  if songwriter#grammar#IsTabLine(getline('.'))
    if songwriter#keys#InTabMode() && has_key(s:tabmode_keys, a:key)
      return "\<Cmd>" . s:tabmode_keys[a:key] . "\<CR>"
    endif
    if has_key(s:tabline_keys, a:key)
      return "\<Cmd>" . s:tabline_keys[a:key] . "\<CR>"
    endif
  endif
  return a:key
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
