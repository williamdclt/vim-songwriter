Vim plugin to help writing guitar tablatures, chord progressions and chord annotations on lyrics, as well as freeform prose.

Design constraint: someone without Vim (just normal text editor), who's not familiar with this project, should be able to read a .song.txt file and understand everything in it easily. This means no complex rendering.

See specification.song.txt for a specification of this file format. 

This plugin is tested with Vader.vim (`test/` folder) to prevent regressions. Vader documentation at https://raw.githubusercontent.com/junegunn/vader.vim/refs/heads/master/doc/vader.txt, you can look for example in existing test files in this project.

Design decisions MUST be recorded in `design.md`.

## Potential inspiration

https://github.com/matt-snider/vim-guitar-tab

chordpro format and https://github.com/vim-scripts/chordpro.vim? But I don't like that it's a separate format for displaying, I want the text version to be maximally readable.
