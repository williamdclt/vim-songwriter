" syntax/songwriter.vim - Syntax highlighting for songwriter files
" Maintainer:
" License: MIT

if exists('b:current_syntax')
  finish
endif

" Section markers: [Intro], [Verse 1], [Chorus], etc.
syn match songwriterSection '\v\[\s*[A-Za-z][A-Za-z0-9 -]*\s*\]'

" Chords (standalone, anywhere in text)
" Requires at least one distinguishing feature to avoid false positives on prose.
" Three branches:
"   1. Root + accidental (e.g. Bb, C#, Ebb)
"   2. Root + suffix (e.g. Am, D7, Em9, Gsus4)
"   3. Root + accidental + suffix +/- bass (e.g. D/F#, Bbm7, C#maj9/G)
syn match songwriterChord '\v\<[A-G][b#]+\>[0-9A-Za-z/]*'
syn match songwriterChord '\v\<[A-G][mM7dimaug5]|[69]|sus[24]|maj7][0-9A-Za-z/]*'
syn match songwriterChord '\v\<[A-G][b#][mM7dimaug5]|[69]|sus[24]|maj7][0-9A-Za-z/]*'

" Tab lines: string prefix + pipe + fret content to end of line
syn region songwriterTabLine start='\v\%(\s\|\^\)\@<=\a\|' end='\$' contains=songwriterTabPrefix,songwriterTabFret

" Tab string prefix letter (e.g. "e" in "e|")
syn match songwriterTabPrefix '\v\%(\s\|\^\)\@<=\a\+\zs\%' contained

" Tab fret numbers
syn match songwriterTabFret '\v\d\+' contained

hi def link songwriterChord Identifier
hi def link songwriterTabLine Normal
hi def link songwriterTabPrefix Type
hi def link songwriterTabFret Number
hi def link songwriterSection Title

let b:current_syntax = 'songwriter'
