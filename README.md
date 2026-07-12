Vim plugin to help writing guitar tablatures, chord progressions and chord annotations on lyrics, as well as freeform prose.

Design constraint: this is (as much as possible) not a custom file format. Someone without Vim, who's not familiar with this project, should be able to understand the music and prose easily.

## Features

- interleave freeform prose, lyrics, chord progressions, tabs... as a sort of notebook.
- Syntax highlighting of tablature, chord progressions
- Tab edit:
  - add bar
  - add space (dashes) on all strings simulateously
  - insert a chord with a : command (eg `:whateverthecommandis Am7`)
  - move whole chord up or down chromatically with ctrl+A and ctrl+X
- Chord edit:
  - move whole chord up or down chromatically with ctrl+A and ctrl+X
  - change the nature of the chord with a command (eg `:whateverthecommandis maj7`)
  - change the nature of the chord between minor and major with a key (does not handle 7, sus4, etc)
- Chord + lyrics edit:
  - Insert a chord above the current position of the cursor
    - automatically insert whatever space is needed before the chord for alignment

## Contribute

Use https://github.com/junegunn/vader.vim for testing.

## Potential inspiration

https://github.com/matt-snider/vim-guitar-tab

chordpro format and https://github.com/vim-scripts/chordpro.vim? But I don't like that it's a separate format for displaying, I want the text version to be maximally readable.

