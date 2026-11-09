" ftplugin/songwriter.vim - buffer-local settings and key bindings.

if exists('b:did_ftplugin')
  finish
endif
let b:did_ftplugin = 1

setlocal nowrap
setlocal iskeyword+=\|
setlocal foldmethod=marker
setlocal foldmarker=[,]
" Note: no space before each `|` below: :unmap would take it as part of the key.
let b:undo_ftplugin = 'setlocal wrap< iskeyword< foldmethod< foldmarker< '

" Plain keys -> <Plug> maps (plugin/songwriter.vim).
let s:plug_keys = {
      \ '<C-A>': 'songwriter-transpose-up',
      \ '<C-X>': 'songwriter-transpose-down',
      \ '<leader>m': 'songwriter-toggle-minor-major',
      \ '<leader>t': 'songwriter-toggle-tabmode',
      \ '\|\|': 'songwriter-lint',
      \ '_': 'songwriter-add-dash',
      \ }
for [s:key, s:plug] in items(s:plug_keys)
  execute 'nmap <buffer> ' . s:key . ' <Plug>(' . s:plug . ')'
  let b:undo_ftplugin .= '| silent! nunmap <buffer> ' . s:key
endfor

" Context-dependent keys (tab line, tablature mode): see autoload/songwriter/keys.vim.
for s:key in songwriter#keys#ContextKeys()
  execute printf('nnoremap <buffer> <expr> %s songwriter#keys#Dispatch(%s)', s:key, string(s:key))
  let b:undo_ftplugin .= '| silent! nunmap <buffer> ' . s:key
endfor
onoremap <buffer> <expr> L songwriter#keys#Dispatch('L')
onoremap <buffer> <expr> H songwriter#keys#Dispatch('H')
let b:undo_ftplugin .= '| silent! ounmap <buffer> L| silent! ounmap <buffer> H'

" Visual L/H keep the `:call` form: it leaves visual mode, which is a known
" defect (switching to Dispatch/<Cmd> would change that behaviour).
xnoremap <buffer> <expr> L songwriter#grammar#IsTabLine(getline('.')) ? ':call songwriter#keys#JumpBarLine(1)<CR>' : 'L'
xnoremap <buffer> <expr> H songwriter#grammar#IsTabLine(getline('.')) ? ':call songwriter#keys#JumpBarLine(-1)<CR>' : 'H'
let b:undo_ftplugin .= '| silent! xunmap <buffer> L| silent! xunmap <buffer> H'

unlet s:key s:plug s:plug_keys
