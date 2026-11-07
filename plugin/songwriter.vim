" plugin/songwriter.vim - Songwriter: thin global wrappers over the autoload
" implementation plus the :command definitions. The public Songwriter*() names
" are kept stable so the test-suite and the ftplugin mappings bind unchanged;
" the real logic lives in autoload/songwriter/{util,tab,chord}.vim.

if exists('g:loaded_songwriter_plugin')
  finish
endif
let g:loaded_songwriter_plugin = 1

" --- Thin wrappers over autoload/songwriter/tab.vim ---
function! SongwriterAddDashes()
  call songwriter#tab#AddDashes()
endfunction
function! SongwriterAddDash()
  call songwriter#tab#AddDash()
endfunction
function! SongwriterAddBar()
  call songwriter#tab#AddBar()
endfunction
function! SongwriterLint()
  call songwriter#tab#Lint()
endfunction
function! SongwriterTabChord(chord)
  call songwriter#tab#TabChord(a:chord)
endfunction

" --- Thin wrappers over autoload/songwriter/chord.vim ---
function! SongwriterTransposeChord(dir)
  call songwriter#chord#TransposeChord(a:dir)
endfunction
function! SongwriterChordAbove(chord)
  call songwriter#chord#ChordAbove(a:chord)
endfunction
function! SongwriterChordQuality(q)
  call songwriter#chord#ChordQuality(a:q)
endfunction
function! SongwriterToggleMinorMajor()
  call songwriter#chord#ToggleMinorMajor()
endfunction

" === Ex commands ===
command! -nargs=0 SongwriterAddBar call SongwriterAddBar()
command! -nargs=0 SongwriterAddDash call SongwriterAddDash()
command! -nargs=0 SongwriterAddDashes call SongwriterAddDashes()
command! -nargs=0 SongwriterLint call SongwriterLint()
command! -nargs=1 SongwriterTabChord call SongwriterTabChord(<q-args>)
command! -nargs=1 SongwriterChordAbove call SongwriterChordAbove(<q-args>)
command! -nargs=1 SongwriterChordQuality call SongwriterChordQuality(<q-args>)
command! -nargs=1 SongwriterTransposeChord call SongwriterTransposeChord(<q-args>)
command! -nargs=0 SongwriterToggleMinorMajor call SongwriterToggleMinorMajor()
