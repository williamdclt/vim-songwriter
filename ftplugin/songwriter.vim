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
