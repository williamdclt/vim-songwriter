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

" Tablature mode is on when a buffer is opened (spec [Tablature][[Editing]] 3).
let b:songwriter_tabmode = 1
let b:undo_ftplugin .= '| unlet! b:songwriter_tabmode'

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
" Visual-mode keys (spec [Chords][[Editing]]: visual <Ctrl-A>/<Ctrl-X>).
for s:key in ['<C-A>', '<C-X>']
  execute 'xmap <buffer> ' . s:key . ' <Plug>(' . s:plug_keys[s:key] . ')'
  let b:undo_ftplugin .= '| silent! xunmap <buffer> ' . s:key
endfor

" Context-dependent keys (tab line, tablature mode), per mode: see
" autoload/songwriter/keys.vim. In the map's right side the key name is passed
" with `<` as <lt>, so a special key such as <Esc> reaches Dispatch as its name
" rather than being translated; `|` is written <Bar> on both sides.
for s:mode in ['n', 'o', 'x']
  for s:key in songwriter#keys#ContextKeys(s:mode)
    let s:lhs = substitute(s:key, '|', '<Bar>', 'g')
    execute printf('%snoremap <buffer> <expr> %s songwriter#keys#Dispatch(%s, %s)',
          \ s:mode, s:lhs,
          \ substitute(substitute(string(s:key), '<', '<lt>', 'g'), '|', '<Bar>', 'g'),
          \ string(s:mode))
    let b:undo_ftplugin .= printf('| silent! %sunmap <buffer> %s', s:mode, s:lhs)
  endfor
endfor

" Spec [Tablature][[Rendering]] 4: the time column under the cursor follows
" it; the highlight is a window match, so it goes when the window shows
" another buffer or loses focus.
augroup songwriter_column
  autocmd! * <buffer>
  autocmd CursorMoved,CursorMovedI,BufWinEnter,WinEnter,TextChanged,TextChangedI <buffer>
        \ call songwriter#tab#highlight#Update()
  autocmd BufWinLeave,WinLeave <buffer> call songwriter#tab#highlight#Clear()
augroup END
let b:undo_ftplugin .= '| exe "autocmd! songwriter_column * <buffer>" | call songwriter#tab#highlight#Clear()'

unlet s:mode s:lhs
unlet s:key s:plug s:plug_keys
