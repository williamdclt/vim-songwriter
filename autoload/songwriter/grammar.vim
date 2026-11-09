" autoload/songwriter/grammar.vim - the .song.txt format's patterns, defined
" once. Every other module (motions, editing, linter, syntax) gets its regexes
" from here; do not write one of these patterns inline elsewhere.

" A tablature line: a string name immediately followed by a bar pipe (`e|--`).
let s:tab_line = '^\a[|]'

" A tab line whose last bar is closed: nothing but whitespace after its final
" pipe (`e|--3--|`, not `e|--3--`).
let s:closed_tab_line = '[|]\s*$'

" A note on a tab line: a run of digits (a fret; `12` is one note).
let s:note = '[0-9]\+'
let s:note_char = '[0-9]'

" A note group on a tab line, as the linter sees it: any run of characters that
" are not dashes, pipes or whitespace. It keeps playing techniques with their
" notes (`5h7`, `3/5`, `12b14`) and stand-alone marks (`x`) as one unit.
let s:tab_atom = '[^-|[:space:]]\+'

" Pieces of a tab line.
let s:pipe = '[|]'
let s:not_pipe = '[^|]'
let s:leading_pipe = '^|'
let s:final_pipe = '|$'
let s:dash = '-'
let s:dash_run = '^-*'
let s:only_dashes = '^-\+$'
let s:trailing_space = '\s*$'
" What separates the note groups of a register row.
let s:note_separators = '[-|]\+'
" What separates the frets of a note group.
let s:not_fret = '\D\+'

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

" A leading minor quality (`m`, `min`, but not `maj`).
let s:minor_prefix = '^\%(min\|m\%(aj\)\@!\)'

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
" The string name on a highlighted tab line.
let s:tab_prefix_syntax = '^\s*[A-Ga-g]\ze|'

" Section markers for highlighting: subsections (`[[Rendering]]`) first.
let s:section_syntax = [
      \ '\[\[\s*[A-Za-z][A-Za-z0-9 -]*\s*\]\]',
      \ '\[\s*[A-Za-z][A-Za-z0-9 -]*\s*\]',
      \ ]

function! songwriter#grammar#TabLine() abort
  return s:tab_line
endfunction
function! songwriter#grammar#IsTabLine(line) abort
  return a:line =~# s:tab_line
endfunction
function! songwriter#grammar#IsClosedTabLine(line) abort
  return a:line =~# s:closed_tab_line
endfunction
function! songwriter#grammar#Note() abort
  return s:note
endfunction
function! songwriter#grammar#Pipe() abort
  return s:pipe
endfunction
function! songwriter#grammar#NotPipe() abort
  return s:not_pipe
endfunction
function! songwriter#grammar#LeadingPipe() abort
  return s:leading_pipe
endfunction
function! songwriter#grammar#FinalPipe() abort
  return s:final_pipe
endfunction
function! songwriter#grammar#Dash() abort
  return s:dash
endfunction
function! songwriter#grammar#DashRun() abort
  return s:dash_run
endfunction
function! songwriter#grammar#OnlyDashes() abort
  return s:only_dashes
endfunction
function! songwriter#grammar#TrailingSpace() abort
  return s:trailing_space
endfunction
function! songwriter#grammar#NoteSeparators() abort
  return s:note_separators
endfunction
function! songwriter#grammar#NotFret() abort
  return s:not_fret
endfunction
function! songwriter#grammar#MinorPrefix() abort
  return s:minor_prefix
endfunction
function! songwriter#grammar#TabPrefixSyntax() abort
  return s:tab_prefix_syntax
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
function! songwriter#grammar#SectionSyntax() abort
  return copy(s:section_syntax)
endfunction
function! songwriter#grammar#TabLineSyntax() abort
  return s:tab_line_syntax
endfunction
