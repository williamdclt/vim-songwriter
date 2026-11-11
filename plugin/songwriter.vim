" plugin/songwriter.vim - user-facing entry points: :Songwriter* commands and
" <Plug>(songwriter-*) maps. The logic lives in autoload/songwriter/.

if exists('g:loaded_songwriter_plugin')
  finish
endif
let g:loaded_songwriter_plugin = 1

" Spec [Tablature][[Rendering]] 4: the time column under the cursor, in a grey
" just off the background (light on a light one, dark on a dark one), so that
" it marks the column without drawing the eye from the notes. A default: a
" color scheme or the user can define songwriterTimeColumn instead. It is set
" again when the background changes, as the grey depends on it.
function! s:column_colors(force) abort
  if a:force
    highlight clear songwriterTimeColumn
  endif
  if &background ==# 'dark'
    highlight default songwriterTimeColumn ctermbg=236 guibg=#303030
  else
    highlight default songwriterTimeColumn ctermbg=255 guibg=#eeeeee
  endif
endfunction
call s:column_colors(0)
augroup songwriter_colors
  autocmd!
  autocmd ColorScheme * call s:column_colors(0)
  autocmd OptionSet background call s:column_colors(1)
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

" === <Plug> maps (bound to default keys in ftplugin/songwriter.vim) ===
nnoremap <Plug>(songwriter-lint) <Cmd>call songwriter#tab#Lint()<CR>
nnoremap <Plug>(songwriter-add-dash) <Cmd>call songwriter#tab#AddDash()<CR>
nnoremap <Plug>(songwriter-transpose-up) <Cmd>call songwriter#chord#TransposeChord(v:count1)<CR>
nnoremap <Plug>(songwriter-transpose-down) <Cmd>call songwriter#chord#TransposeChord(-v:count1)<CR>
xnoremap <Plug>(songwriter-transpose-up) <Cmd>call songwriter#chord#TransposeVisual(v:count1)<CR>
xnoremap <Plug>(songwriter-transpose-down) <Cmd>call songwriter#chord#TransposeVisual(-v:count1)<CR>
nnoremap <Plug>(songwriter-toggle-minor-major) <Cmd>call songwriter#chord#ToggleMinorMajor()<CR>
nnoremap <Plug>(songwriter-toggle-tabmode) <Cmd>call songwriter#keys#ToggleTabMode()<CR>
