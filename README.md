## What is this

Vim plugin to help writing guitar tablatures, chord progressions and chord annotations on lyrics, as well as freeform prose.

Design constraint: someone without Vim (just normal text editor), who's not familiar with this project, should be able to read a .song.txt file and understand everything in it easily. This means no complex rendering.

## Documentation

See specification.song.txt for a specification of this file format, and implementation status.

Design decisions MUST be recorded in `design.md`.

## Testing

This plugin is tested with Vader.vim (`test/` folder) to prevent regressions. Vader documentation at https://raw.githubusercontent.com/junegunn/vader.vim/refs/heads/master/doc/vader.txt, you can look for example in existing test files in this project.

Run tests: `make test`.

Tests MUST be green to commit, which is enforced by pre-commit hook.

## Potential inspiration

https://github.com/matt-snider/vim-guitar-tab

chordpro format and https://github.com/vim-scripts/chordpro.vim? But I don't like that it's a separate format for displaying, I want the text version to be maximally readable.
