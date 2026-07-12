Vim plugin to help writing guitar tablatures, chord progressions and chord annotations on lyrics, as well as freeform prose.

Design constraint: this is (as much as possible) not a custom file format. Someone without Vim, who's not familiar with this project, should be able to understand the music and prose easily.

## Features

- [x] interleave freeform prose, lyrics, chord progressions, tabs... as a sort of notebook.
- [x] Syntax highlighting of tablature, chord progressions
- Tab edit:
  - [x] add bar (`:SongwriterAddBar`)
  - [x] add space (dashes) on all strings simultaneously (`:SongwriterAddDashes`)
  - [x] insert a chord with a command (`:SongwriterTabChord Am7`)
  - [x] move whole chord up or down chromatically (`<Ctrl-A>`/`<Ctrl-X>`)
- Chord edit:
  - [x] move whole chord up or down chromatically (`<Ctrl-A>`/`<Ctrl-X>`)
  - [x] change the nature of the chord with a command (`:SongwriterChordQuality maj7`)
  - [x] change the nature of the chord between minor and major (`<leader>m`)
- Chord + lyrics edit:
  - [x] Insert a chord above the current position of the cursor
    - automatically insert whatever space is needed before the chord for alignment (`:SongwriterChordAbove Am7`)

## Key Mappings

- `<Ctrl-A>` / `<Ctrl-X>` — transpose chord under cursor up/down
- `<leader>m` — toggle minor/major

## Contribute

Use https://github.com/junegunn/vader.vim for testing.

## Potential inspiration

https://github.com/matt-snider/vim-guitar-tab

chordpro format and https://github.com/vim-scripts/chordpro.vim? But I don't like that it's a separate format for displaying, I want the text version to be maximally readable.
