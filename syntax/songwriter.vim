" syntax/songwriter.vim - Syntax highlighting for songwriter files
" Maintainer:
" License: MIT

if exists('b:current_syntax')
  finish
endif

" Section markers: [Intro], [Verse 1], [Chorus], etc.
syn match songwriterSection '\v\[\s*[A-Za-z][A-Za-z0-9 -]*\s*\]'

" Chords (standalone, anywhere in text)
" Five branches:
"   1. Root + accidental (e.g. Bb, C#, Ebb) with optional suffix
"   2. Root + minor/maj7/dim/aug/5/sus/m7 etc. (e.g. Am, Dm7, Gmaj7, Bsus4)
"   3. Root + 7/9/6 power/seventh suffix (e.g. D7, E9, G6)
"   4. Root + accidental + suffix (e.g. D#m7, Bbmaj7)
"   5. Bare root (major chord, e.g. A, G, E)
syn match songwriterChord '\v\<[A-G][b#]+\+[0-9A-Za-z/]*'
syn match songwriterChord '\v\<[A-G][mM7dimaug5]|[69]|sus[24]|maj7][0-9A-Za-z/]*'
syn match songwriterChord '\v\<[A-G][796][0-9A-Za-z/]*'
syn match songwriterChord '\v\<[A-G][b#][mM7dimaug5]|[69]|sus[24]|maj7][0-9A-Za-z/]*'
syn match songwriterChord '\v\<[A-G]\>'

" Tab lines: string prefix + pipe + fret content to end of line
syn region songwriterTabLine start='\v\%(\s\|\^\)\@<=\a\|' end='\$' contains=songwriterTabPrefix,songwriterTabFret,songwriterTabBar

" Tab string prefix letter (e.g. "e" in "e|")
syn match songwriterTabPrefix '\v\%(\s\|\^\)\@<=\a\+\zs\%' contained

" Tab fret numbers
syn match songwriterTabFret '\v\d\+' contained

" Tab bar separator
syn match songwriterTabBar '\v|' contained

hi def link songwriterChord Identifier
hi def link songwriterTabLine Normal
hi def link songwriterTabPrefix Type
hi def link songwriterTabFret Number
hi def link songwriterTabBar Special
hi def link songwriterSection Title

let b:current_syntax = 'songwriter'
