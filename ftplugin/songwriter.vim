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

" Typing || on a tab block lints it (aligns bar pipes, normalises dashes)
nnoremap <buffer> \|\| :call SongwriterLint()<CR>

" Typing _ on a tab block inserts a dash on every string at the cursor column
nnoremap <buffer> _ :call SongwriterAddDash()<CR>

" Return 1 when the cursor is on a tab line (a string name followed by a bar
" pipe). Uses the same pattern as the rest of the plugin (s:TabLinePat in
" plugin/songwriter.vim); see design.md.
function! SongwriterIsTablatureLine() abort
    " Shared tab-line test from
    " the util module (see design.md).
  return songwriter#grammar#IsTabLine(getline('.'))
endfunction

" Tablature motions. Not in tablature mode, w/b skip over dashes, stopping on
" notes, bar lines and string names. In "tablature" mode (<leader>t toggles it,
" default off; see spec [Tablature -> Editing] 3) the keys become note-level
" motions:
"     3.1 w/b move to the next/prev NOTE on the current line, skipping dashes and
"          pipes (SongwriterMoveNote).
"     3.2 l/h move to the next/prev column where ANY line of the block has a note
"          (SongwriterMoveColumn).
" Off a tab line (prose), or out of tablature mode for l/h, they fall back to
" their normal behaviour. Each map is written fully inline (like L/H below) so
" the ex-command runs; note the \| is escaped because a bare | would be read as
" a command separator inside the map.
nnoremap <buffer> <expr> w get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterMoveNote(1)<CR>' : (SongwriterIsTablatureLine() ? ':call search(''[0-9a-zA-Z\\|]'', ''W'')<CR>' : 'w')
nnoremap <buffer> <expr> b get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterMoveNote(-1)<CR>' : (SongwriterIsTablatureLine() ? ':call search(''[0-9a-zA-Z\\|]'', ''bW'')<CR>' : 'b')
nnoremap <buffer> <expr> l get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterMoveColumn(1)<CR>' : 'l'
nnoremap <buffer> <expr> h get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterMoveColumn(-1)<CR>' : 'h'

" 3.3 / 3.4 — note entry. In tablature mode on a tab line, a digit enters a
" fret (3.3), and a/i open 3 dashes of room for the next note to the right (a)
" or left (i), landing on the 2nd new dash, on every string (3.4). Off tab mode
" or on prose the keys fall back to their normal behaviour (a count / append /
" insert). Each map is inline like L/H so the ex-command runs. The digit is baked
" as a bare number (not a string) so the ex-command needs no inner quotes.
nnoremap <buffer> <expr> 1 get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterEnterNote(1)<CR>' : '1'
nnoremap <buffer> <expr> 2 get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterEnterNote(2)<CR>' : '2'
nnoremap <buffer> <expr> 3 get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterEnterNote(3)<CR>' : '3'
nnoremap <buffer> <expr> 4 get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterEnterNote(4)<CR>' : '4'
nnoremap <buffer> <expr> 5 get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterEnterNote(5)<CR>' : '5'
nnoremap <buffer> <expr> 6 get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterEnterNote(6)<CR>' : '6'
nnoremap <buffer> <expr> 7 get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterEnterNote(7)<CR>' : '7'
nnoremap <buffer> <expr> 8 get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterEnterNote(8)<CR>' : '8'
nnoremap <buffer> <expr> 9 get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterEnterNote(9)<CR>' : '9'
nnoremap <buffer> <expr> 0 get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterEnterNote(0)<CR>' : '0'
nnoremap <buffer> <expr> a get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterAddNote(1)<CR>' : 'a'
nnoremap <buffer> <expr> i get(b:,'songwriter_tabmode',0) && SongwriterIsTablatureLine() ? ':call SongwriterAddNote(-1)<CR>' : 'i'


" Toggle the buffer-local "tablature" mode (default off).
nnoremap <buffer> <leader>t :call SongwriterToggleTabMode()<CR>

function! SongwriterToggleTabMode() abort
  let b:songwriter_tabmode = !get(b:, 'songwriter_tabmode', 0)
  echo (b:songwriter_tabmode ? 'songwriter: tablature mode on' : 'songwriter: tablature mode off')
endfunction

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
