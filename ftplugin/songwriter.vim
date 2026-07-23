" ftplugin/songwriter.vim - Buffer-local settings for songwriter files
setlocal nowrap
setlocal iskeyword+=\|
setlocal foldmethod=marker
setlocal foldmarker=[,]

" Transpose chord under cursor up/down
nnoremap <buffer> <C-A> :call SongwriterTransposeChord(1)<CR>
nnoremap <buffer> <C-X> :call SongwriterTransposeChord(-1)<CR>

" Toggle minor/major
nnoremap <buffer> <leader>m :call SongwriterToggleMinorMajor()<CR>

" Tablature motions: w/b skip over dashes, stopping on notes, bar lines, string names
nnoremap <buffer> w :call search('[0-9a-zA-Z\\|]', 'W')<CR>
nnoremap <buffer> b :call search('[0-9a-zA-Z\\|]', 'bW')<CR>

" Tablature bar-line jumps: L/H jump to next/previous |
nnoremap <buffer> L :call search('\v\\|', 'W')<CR>
nnoremap <buffer> H :call search('\v\\|', 'bW')<CR>
