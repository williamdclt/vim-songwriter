" autoload/songwriter/pitch.vim - pitch classes: note names to semitones and
" back. Used by chord transposition and by tablature string intervals.

let s:chromatic = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
let s:flat_to_sharp = {'Eb': 'D#', 'Gb': 'F#', 'Ab': 'G#', 'Bb': 'A#', 'Db': 'C#'}

" Pitch class (0-11, C = 0) of a note name (`A`, `C#`, `Bb`), or -1. The letter
" may be lowercase, as in tab string names (`e|`).
function! songwriter#pitch#Class(name) abort
  let l:name = toupper(a:name[0:0]) . a:name[1:]
  return index(s:chromatic, get(s:flat_to_sharp, l:name, l:name))
endfunction

" Name of pitch class `pc` (any integer, taken modulo 12), spelled with sharps.
function! songwriter#pitch#Name(pc) abort
  return s:chromatic[(a:pc % 12 + 12) % 12]
endfunction
