" syntax/songwriter.vim - Syntax highlighting for songwriter files
" Maintainer:
" License: MIT

if exists('b:current_syntax')
  finish
endif

" Subsection markers: [[Rendering]], [[Motions]], etc.
syn match songwriterSection '\[\[\s*[A-Za-z][A-Za-z0-9 -]*\s*\]\]'

" Section markers: [Intro], [Verse 1], [Chorus], etc.
syn match songwriterSection '\[\s*[A-Za-z][A-Za-z0-9 -]*\s*\]'

" === Chords (patterns from songwriter#grammar, most specific first) ===
for s:pat in songwriter#grammar#ChordSyntax()
  execute 'syn match songwriterChord ' . string(s:pat)
endfor
unlet s:pat

" === Tab lines ===
" Tab line region: string prefix + pipe + content to end of line
execute 'syn region songwriterTabLine start=' . string(songwriter#grammar#TabLineSyntax())
      \ . " end='$' contains=songwriterTabPrefix,songwriterTabFret,songwriterTabBar,songwriterTabDash"

" Tab string prefix letter (e.g. "e" in "e|")
syn match songwriterTabPrefix '^\s*[A-Ga-g]\ze|' contained

" Tab fret numbers
syn match songwriterTabFret '\d\+' contained

" Tab bar separator
syn match songwriterTabBar '|' contained

" Tab dash (empty string)
syn match songwriterTabDash '-' contained

" === Highlighting ===
hi def songwriterChord gui=bold cterm=bold guifg=#aa00ff ctermfg=Magenta
hi def songwriterTabLine gui=none cterm=none guifg=NONE ctermfg=NONE
hi def songwriterTabPrefix gui=none cterm=none guifg=#888888 ctermfg=Blue
hi def songwriterTabFret gui=none cterm=none guifg=#ffffff ctermfg=White
hi def songwriterTabDash gui=none cterm=none guifg=#888888 ctermfg=Blue
hi def songwriterTabBar gui=none cterm=none guifg=#ffffff ctermfg=White
hi def songwriterSection gui=bold cterm=bold guifg=#ffff00 ctermfg=Yellow

let b:current_syntax = 'songwriter'
