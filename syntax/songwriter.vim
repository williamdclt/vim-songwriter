" syntax/songwriter.vim - Syntax highlighting for songwriter files
" Maintainer:
" License: MIT

if exists('b:current_syntax')
  finish
endif

" Section markers: [Intro], [Verse 1], [Chorus], etc.
syn match songwriterSection '\[\s*[A-Za-z][A-Za-z0-9 -]*\s*\]'

" === Chords (ordered most-specific to least-specific) ===

" Root + accidental + quality suffix (Bbm, C#m7, Bbmaj7)
syn match songwriterChord '\m\<[A-G][b#]\(m\|maj7\|dim\|aug\|sus[24]\|[5679]\)[0-9A-Za-z/]*'

" Root + accidental + 7/9/6 + extended (F#7, Bb9, Db6)
syn match songwriterChord '\m\<[A-G][b#][796][0-9A-Za-z/]*'

" Bare accidental root (Bb, C#)
syn match songwriterChord '\m\<[A-G][b#]\>'

" Root + quality suffix (Am, Dm7, Gmaj7, D5)
syn match songwriterChord '\m\<[A-G]\(m\|maj7\|dim\|aug\|sus[24]\|5\)[0-9A-Za-z/]*'

" Root + 7/9/6 + extended (D7, E9, G6, A7sus4)
syn match songwriterChord '\m\<[A-G][796][0-9A-Za-z/]*'

" Bare root (A, G, E)
syn match songwriterChord '\m\<[A-G]\>'

" === Tab lines ===
" Tab line region: string prefix + pipe + content to end of line
syn region songwriterTabLine start='^\s*[A-Ga-g]|' end='$' contains=songwriterTabPrefix,songwriterTabFret,songwriterTabBar,songwriterTabDash

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
