# vim-songwriter

Write guitar tablatures, chord progressions and lyrics with chords in plain
text. The files stay readable in any text editor: no special syntax, no
rendering step.

```
[Verse]

Am                F
I walk a lonely road

e|--------0-----|--------1-----|
B|-----1-----1--|-----1-----1--|
G|--2-----------|--2-----------|
D|--------------|--------------|
A|--0-----------|--------------|
E|--------------|--1-----------|
```

## Installation

Use your plugin manager, or Vim's packages:

```bash
git clone <repository-url> ~/.vim/pack/plugins/start/vim-songwriter
```

Files named `*.song.txt` or `*.tab.txt` are detected automatically.

## File format

| Element      | Example                       | Highlight     |
|--------------|-------------------------------|---------------|
| Section      | `[Chorus]`, `[[Bridge]]`      | bold yellow   |
| Chord        | `Am`, `F#sus4`, `D/F#`        | magenta       |
| Tab line     | `e\|--3--5h7--x--\|`          | blue dashes   |
| Anything else | lyrics, notes                | default       |

In a tab, a note is a fret number (`12`) or `x` (muted). Anything else between
notes (`h`, `p`, `/`, `b`, `~`…) is a technique marker and is kept as is.
Tabs are separated by blank lines.

See [specification.song.txt](specification.song.txt) for the full format.

## Tablature mode

Tablature mode is on when a file is opened; toggle it with `<leader>t`. Outside
tablature mode, tab lines are plain text with smarter motions (`w`/`b` skip
dashes, `W`/`B` jump between bar lines).

In tablature mode, keys on a tab line work on **time columns** (the notes played
together, across all strings) and keep the tab aligned. Off a tab line, Vim
behaves as usual.

Like Vim, it has a normal state (moving never changes the file) and an insert
state (moving opens room for new notes). The insert state shows
`-- TAB INSERT --`.

### Writing notes

| Key            | Action                                                       |
|----------------|--------------------------------------------------------------|
| `0`–`9`        | Enter a fret (type `1` `2` for `12`)                         |
| `x` on a dash  | Enter a muted note                                           |
| `a` / `i`      | Open a slot after / before the note, enter the insert state  |
| `<Esc>`        | Leave the insert state (an unused slot disappears)           |
| `o` / `O`      | New empty tab below / above, same tuning                     |
| `_`            | Insert a dash at the cursor on every string                  |
| `\|\|`          | Align and tidy the tab                                       |

In the insert state, `l` / `h` step through notes *and* the gaps between them,
opening a slot in each gap; `l` past the last note adds a new bar.

In the insert state, notes are typed one after the other: `a5789` gives
`5-7-8-9`. A digit joins the fret before it only when that makes a real fret
(`12`, `24`; at most `g:songwriter_max_fret`, 24 by default), so `25` is two
notes. Press `<Space>` (same as `l`) to end a `1` or `2` meant alone: `1 5`.
`j` / `k` after a note stay on its column, to type a chord (`5j7`).
Technique markers are typed straight after a note: `5h7`, `7b`, `5/9~`
(`h p b r t s / ~`).

Use Vim's `f` and `r` to edit technique markers: `fhr/` turns a hammer-on into
a slide.

### Writing chords

`=` then a chord name and `<Enter>` writes a whole chord on the time column,
with its root on the cursor's string: on the A string `=Am<Enter>` is the open
Am, on the low E string the barre at the 5th fret. `==` right after it cycles to
the next voicing: lower strings first, then higher ones, then the 12th fret.
In the insert state it fills the slot, and the next digit goes on after it.

`=` then a quality alone changes the chord already on the column, keeping its
root (the note on the lowest string): on an `Em`, `=M7<Enter>` gives `EM7`, and
`=5<Enter>` turns a single note into a power chord.

Shapes (E, A, D at any fret, open C and G) cover major, `m`, `7`, `m7`, `maj7`,
`sus2`, `sus4` in standard tuning. Power chords (`=E5`) are root, fifth and
octave, and follow any tuning (drop D gives the one-finger shape).

### Moving

| Key            | Moves to                                          |
|----------------|---------------------------------------------------|
| `w` / `b`      | next / previous note on the string                |
| `l` / `h`      | next / previous time column (any string)          |
| `L` / `H`      | same, but never opens a slot in the insert state  |
| `W` / `B` / `E`| start of next bar / start of bar / end of bar     |

`j`, `k`, `f`, `t`, `$`… are unchanged.

### Editing columns

Operators act on whole time columns, on every string, and keep the spacing.

| Key             | Action                                                   |
|-----------------|----------------------------------------------------------|
| `x`             | Erase the note (the column goes if it is left empty)     |
| `dd` `yy` `cc`  | Delete / yank / change the time column (`Y` = `yy`)      |
| `D` / `C`       | Delete / change to the end of the bar                    |
| `p` / `P`       | Paste columns or bars after / before the cursor's        |
| `gp`            | Overlay a column onto the current one (add a bass note)  |
| `>>` / `<<`     | Push the column one dash later / earlier                 |
| `sk` / `sj`     | Move the note one string up / down, same fret            |
| `Sk` / `Sj`     | Same, keeping the pitch (fret is recomputed)             |
| `sK` `sJ` `SK` `SJ` | Same, for the whole time column                      |
| `V`             | Visual selection of the time column                      |
| `.`             | Repeat                                                   |

Operators take any motion (`dw`, `d$`, `dW`) and these text objects:

| Object          | Selects                                     |
|-----------------|---------------------------------------------|
| `ic` / `ac`     | time column / plus the gap after it         |
| `i\|` / `a\|`     | bar / plus one bar line                     |
| `in` / `an`     | single note on its string / plus its gap    |
| `ap`            | whole tab                                   |

Since digits type notes, put counts after the operator: `d3d`, `d2ac`.

Yanked columns are ordinary blockwise registers, so they paste fine outside
tablature mode, and tabs with fewer strings (bass) paste onto the lowest strings.

### Status line

`songwriter#keys#Mode()` returns `TAB INSERT` in the insert state:

```vim
set statusline+=%{exists('*songwriter#keys#Mode')?songwriter#keys#Mode():''}
```

## Chords

| Key                 | Action                                                |
|---------------------|-------------------------------------------------------|
| `<C-A>` / `<C-X>`   | Transpose the chord up / down a semitone (count works)|
| `<leader>m`         | Toggle minor / major                                  |

In visual mode, `<C-A>` / `<C-X>` transpose every chord in the selection. Off a
chord they increment numbers as usual.

## Commands

| Command                            | Action                                       |
|------------------------------------|----------------------------------------------|
| `:SongwriterNewTab [strings]`      | New empty tab (default `eBGDAE`; bass: `GDAE`) |
| `:SongwriterLint`                  | Align and tidy the tab (`\|\|`)               |
| `:SongwriterAddDash`               | Insert a dash on every string (`_`)          |
| `:SongwriterAddDashes`             | Append `--` to every string                  |
| `:SongwriterAddBar`                | Insert a bar line after the cursor           |
| `:SongwriterChordAbove {chord}`    | Write a chord above the cursor, aligned      |
| `:SongwriterTabChord {chord}`      | Write a chord above the tab, at the cursor   |
| `:SongwriterChordQuality {quality}`| Change the chord's quality (`:SongwriterChordQuality sus4`) |
| `:SongwriterTransposeChord {n}`    | Transpose the chord by `n` semitones         |
| `:SongwriterToggleMinorMajor`      | Toggle minor / major (`<leader>m`)           |
| `:SongwriterToggleTabMode`         | Toggle tablature mode (`<leader>t`)          |

## Mappings

Each default key calls a `<Plug>` mapping, so you can bind your own keys too:

| Default       | `<Plug>` mapping                          |
|---------------|-------------------------------------------|
| `<C-A>`       | `<Plug>(songwriter-transpose-up)`         |
| `<C-X>`       | `<Plug>(songwriter-transpose-down)`       |
| `<leader>m`   | `<Plug>(songwriter-toggle-minor-major)`   |
| `<leader>t`   | `<Plug>(songwriter-toggle-tabmode)`       |
| `\|\|`         | `<Plug>(songwriter-lint)`                 |
| `_`           | `<Plug>(songwriter-add-dash)`             |

## Development

Design decisions are recorded in [design.md](design.md); the format and its
implementation status in [specification.song.txt](specification.song.txt).

Tests use [Vader.vim](https://github.com/junegunn/vader.vim) (cloned on first
run): `make test`. Run `make hooks` once after cloning to enable the pre-commit
hook, which requires green tests.

Inspiration: [vim-guitar-tab](https://github.com/matt-snider/vim-guitar-tab),
[chordpro.vim](https://github.com/vim-scripts/chordpro.vim).
