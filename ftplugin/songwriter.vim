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

" Check if current line is tablature (starts with string name followed by |)
function! SongwriterIsTablatureLine() abort
  return getline('.') =~# '^[eEaAdDgGbB][|]'
endfunction

" Tablature motions: w/b skip over dashes, stopping on notes, bar lines, string names
" Only active on tablature lines; falls back to normal w/b otherwise
nnoremap <buffer> <expr> w SongwriterIsTablatureLine() ? ':call search(''[0-9a-zA-Z\\|]'', ''W'')<CR>' : 'w'
nnoremap <buffer> <expr> b SongwriterIsTablatureLine() ? ':call search(''[0-9a-zA-Z\\|]'', ''bW'')<CR>' : 'b'

" Tablature bar-line jumps: L/H jump to next/previous |
" Only active on tablature lines; falls back to normal L/H otherwise
nnoremap <buffer> <expr> L SongwriterIsTablatureLine() ? ':call SongwriterJumpBarLine(1)<CR>' : 'L'
nnoremap <buffer> <expr> H SongwriterIsTablatureLine() ? ':call SongwriterJumpBarLine(-1)<CR>' : 'H'
xnoremap <buffer> <expr> L SongwriterIsTablatureLine() ? ':call SongwriterJumpBarLine(1)<CR>' : 'L'
xnoremap <buffer> <expr> H SongwriterIsTablatureLine() ? ':call SongwriterJumpBarLine(-1)<CR>' : 'H'
onoremap <buffer> <expr> L SongwriterIsTablatureLine() ? ':call SongwriterJumpBarLine(1)<CR>' : 'L'
onoremap <buffer> <expr> H SongwriterIsTablatureLine() ? ':call SongwriterJumpBarLine(-1)<CR>' : 'H'

function! SongwriterJumpBarLine(forward) abort
  let v:searchforward = a:forward > 0
  call search('|', a:forward > 0 ? 'W' : 'bW')
endfunction
