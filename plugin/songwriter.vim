" plugin/songwriter.vim - user-facing entry points: :Songwriter* commands and
" <Plug>(songwriter-*) maps. The logic lives in autoload/songwriter/.

if exists('g:loaded_songwriter_plugin')
  finish
endif
let g:loaded_songwriter_plugin = 1

" Spec [Tablature][[Rendering]] 4: the time column under the cursor, and
" [[Editing]] 3.8.5: that column in the move state (defaults that
" a color scheme or the user can override).
function! s:colors() abort
  highlight default link songwriterTimeColumn CursorColumn
  highlight default link songwriterMoveColumn Search
endfunction
call s:colors()
augroup songwriter_colors
  autocmd!
  autocmd ColorScheme * call s:colors()
augroup END

" === Ex commands ===
command! -nargs=0 SongwriterAddBar call songwriter#tab#AddBar()
command! -nargs=0 SongwriterAddDash call songwriter#tab#AddDash()
command! -nargs=0 SongwriterAddDashes call songwriter#tab#AddDashes()
command! -nargs=? SongwriterNewTab call songwriter#tab#newtab#NewTabNamed(<q-args>)
command! -nargs=0 SongwriterLint call songwriter#tab#Lint()
command! -nargs=1 SongwriterTabChord call songwriter#tab#TabChord(<q-args>)
command! -nargs=1 SongwriterChordAbove call songwriter#chord#ChordAbove(<q-args>)
command! -nargs=1 SongwriterChordQuality call songwriter#chord#ChordQuality(<q-args>)
command! -nargs=1 SongwriterTransposeChord call songwriter#chord#TransposeChord(<q-args>)
command! -nargs=0 SongwriterToggleMinorMajor call songwriter#chord#ToggleMinorMajor()
command! -nargs=0 SongwriterToggleTabMode call songwriter#keys#ToggleTabMode()
command! -nargs=0 SongwriterStop call songwriter#sound#Stop()

" === <Plug> maps (bound to default keys in ftplugin/songwriter.vim) ===
nnoremap <Plug>(songwriter-lint) <Cmd>call songwriter#tab#Lint()<CR>
nnoremap <Plug>(songwriter-add-dash) <Cmd>call songwriter#tab#AddDash()<CR>
nnoremap <Plug>(songwriter-transpose-up) <Cmd>call songwriter#chord#TransposeChord(v:count1)<CR>
nnoremap <Plug>(songwriter-transpose-down) <Cmd>call songwriter#chord#TransposeChord(-v:count1)<CR>
xnoremap <Plug>(songwriter-transpose-up) <Cmd>call songwriter#chord#TransposeVisual(v:count1)<CR>
xnoremap <Plug>(songwriter-transpose-down) <Cmd>call songwriter#chord#TransposeVisual(-v:count1)<CR>
nnoremap <Plug>(songwriter-toggle-minor-major) <Cmd>call songwriter#chord#ToggleMinorMajor()<CR>
nnoremap <Plug>(songwriter-toggle-tabmode) <Cmd>call songwriter#keys#ToggleTabMode()<CR>
nnoremap <Plug>(songwriter-chord-name) <Cmd>call songwriter#tab#chordname#Show()<CR>
" Spec [Tablature][[Editing]] 12.1: the play operator, the note under the
" cursor, the selection.
nnoremap <expr> <Plug>(songwriter-play) songwriter#tab#operator#Start('play')
nnoremap <expr> <Plug>(songwriter-play-note) songwriter#tab#operator#StartOn('play', 'note')
xnoremap <Plug>(songwriter-play) <Cmd>call songwriter#tab#visual#Op('play', v:register)<CR>
