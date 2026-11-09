" autoload/songwriter/grammar.vim - the .song.txt format's patterns, defined
" once. Every other module (motions, editing, linter, syntax) gets its regexes
" from here; do not write one of these patterns inline elsewhere.

" A tablature line: a string name immediately followed by a bar pipe (`e|--`).
let s:tab_line = '^\a[|]'

" A note on a tab line: a run of digits (a fret; `12` is one note).
let s:note = '[0-9]\+'
let s:note_char = '[0-9]'

" A note group on a tab line, as the linter sees it: any run of characters that
" are not dashes, pipes or whitespace. It keeps playing techniques with their
" notes (`5h7`, `3/5`, `12b14`) and stand-alone marks (`x`) as one unit.
let s:tab_atom = '[^-|[:space:]]\+'

" Where tab-line `w`/`b` stop outside tablature mode (notes, names, pipes).
" Kept in map-ready form: the `|` is written `\\|` so it survives the mapping.
let s:tab_word_stop = '[0-9a-zA-Z\\|]'

" Chords under the cursor (editing). A chord token is a maximal run of chord
" characters; it is a chord only when the whole token matches s:chord: a root,
" a quality made of known parts, and an optional `/bass` root. Submatches:
" 1 root, 2 quality, 3 bass (empty when absent).
let s:chord_root = '[A-G][#b]\='
let s:chord_token_char = '[A-Za-z0-9#/+]'
let s:chord = '\C^\(' . s:chord_root . '\)'
      \ . '\(\%(maj\|min\|m\|dim\|aug\|sus\|add\|M\|[0-9]\|[#b+]\)*\)'
      \ . '\%(/\(' . s:chord_root . '\)\)\=$'

" Chords for highlighting, most specific first.
let s:chord_syntax = [
      \ '\m\<[A-G][b#]\(m\|maj7\|dim\|aug\|sus[24]\|[5679]\)[0-9A-Za-z/]*',
      \ '\m\<[A-G][b#][796][0-9A-Za-z/]*',
      \ '\m\<[A-G][b#]\>',
      \ '\m\<[A-G]\(m\|maj7\|dim\|aug\|sus[24]\|5\)[0-9A-Za-z/]*',
      \ '\m\<[A-G][796][0-9A-Za-z/]*',
      \ '\m\<[A-G]\>',
      \ ]

" Tab-line start as highlighted by syntax/songwriter.vim. NOTE: broader than
" s:tab_line (leading whitespace allowed, string name limited to A-G); the two
" are kept as-is so highlighting and editing behaviour stay unchanged.
let s:tab_line_syntax = '^\s*[A-Ga-g]|'

function! songwriter#grammar#TabLine() abort
  return s:tab_line
endfunction
function! songwriter#grammar#IsTabLine(line) abort
  return a:line =~# s:tab_line
endfunction
function! songwriter#grammar#Note() abort
  return s:note
endfunction
function! songwriter#grammar#IsNoteChar(char) abort
  return a:char =~# s:note_char
endfunction
function! songwriter#grammar#TabWordStop() abort
  return s:tab_word_stop
endfunction
function! songwriter#grammar#TabAtom() abort
  return s:tab_atom
endfunction
" [root, quality, bass] when `token` is a whole chord, else [].
function! songwriter#grammar#ParseChord(token) abort
  let l:m = matchlist(a:token, s:chord)
  return empty(l:m) ? [] : l:m[1:3]
endfunction
function! songwriter#grammar#ChordTokenChar() abort
  return s:chord_token_char
endfunction
function! songwriter#grammar#ChordSyntax() abort
  return copy(s:chord_syntax)
endfunction
function! songwriter#grammar#TabLineSyntax() abort
  return s:tab_line_syntax
endfunction
