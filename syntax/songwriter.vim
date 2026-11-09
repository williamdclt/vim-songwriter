" syntax/songwriter.vim - Syntax highlighting for songwriter files
" Maintainer:
" License: MIT

if exists('b:current_syntax')
  finish
endif

" Subsection markers: [[Rendering]], [[Motions]], etc.
" and section markers: [Intro], [Verse 1], [Chorus], etc.
for s:pat in songwriter#grammar#SectionSyntax()
  execute 'syn match songwriterSection ' . string(s:pat)
endfor

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
execute 'syn match songwriterTabPrefix ' . string(songwriter#grammar#TabPrefixSyntax()) . ' contained'

" Tab fret numbers
execute 'syn match songwriterTabFret ' . string(songwriter#grammar#Fret()) . ' contained'

" Tab bar separator
execute 'syn match songwriterTabBar ' . string(songwriter#grammar#Pipe()) . ' contained'

" Tab dash (empty string)
execute 'syn match songwriterTabDash ' . string(songwriter#grammar#Dash()) . ' contained'

" === Highlighting ===
hi def songwriterChord gui=bold cterm=bold guifg=#aa00ff ctermfg=Magenta
hi def songwriterTabLine gui=none cterm=none guifg=NONE ctermfg=NONE
hi def songwriterTabPrefix gui=none cterm=none guifg=#888888 ctermfg=Blue
hi def songwriterTabFret gui=none cterm=none guifg=#ffffff ctermfg=White
hi def songwriterTabDash gui=none cterm=none guifg=#888888 ctermfg=Blue
hi def songwriterTabBar gui=none cterm=none guifg=#ffffff ctermfg=White
hi def songwriterSection gui=bold cterm=bold guifg=#ffff00 ctermfg=Yellow

let b:current_syntax = 'songwriter'
