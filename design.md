# Design

Lasting design decisions and their rationale, by topic. Keep this file in sync
with the code: edit the relevant section in place (see AGENTS.md).

## Constraint: plain text first

A `.song.txt` must stay readable by someone with a plain text editor who has
never heard of this plugin (README). The plugin only highlights and edits; it
never relies on concealing or rendering.

## Architecture

### Modules

| File | Role |
|---|---|
| `autoload/songwriter/grammar.vim` | The format's patterns (tab line, note, fret, separator, chain, chord, highlighting). The only place regexes for the format are written. |
| `autoload/songwriter/tab/model.vim` | Tab block model: parse, queries (notes, time columns, bars), `Splice`/`Blank` and the column-insertion primitive, and `Read`/`Write` (the buffer edges). |
| `autoload/songwriter/tab/edit.vim` | The buffer side of a tablature edit: `Do` runs a whole edit at the cursor (slot, undo join, lints, one write, insert state, state for the next key, register, `.`); `Commit`, `LintAndFollow`, `Apply` and the pure `Linted` are its parts. |
| `autoload/songwriter/tab/slots.vim` | Slots: where a new note's room goes (pure), the buffer's one open slot with how to close it, and `a`/`i` and the new bar's slot (`AddNote`, `AddBarSlot`). |
| `autoload/songwriter/tab/insert.vim` | The insert state of tablature mode: entering, keeping, leaving it, and `<Esc>`. |
| `autoload/songwriter/tab/typing.vim` | Typing notes and separators: digits, `x` on a dash, separators after a note (`EnterNote`, `EnterSeparator`). |
| `autoload/songwriter/tab/motion.vim` | Tablature-mode motions at the cursor (`w`/`b`/`e`/`ge`, `l`/`h`, `L`/`H`, `W`/`B`/`E`), and the slots the insert state opens on the way. |
| `autoload/songwriter/tab/stops.vim` | Where motions stop and what string motions cover after an operator, pure (`Stops`, `Advance`, `BarStop`, `StringMotion`), and the insert state's positions and how `l`/`h` and the arrows step through them (`Step`). |
| `autoload/songwriter/tab/carry.vim` | Carrying a note with the arrow keys in the insert state, and duplicating one to carry its copy with `hjkl`. |
| `autoload/songwriter/tab/newtab.vim` | New tabs: `o`/`O` and `:SongwriterNewTab`. |
| `autoload/songwriter/tab/state.vim` | Buffer state valid only while `b:changedtick` is unchanged (slot, insert state, digit being typed, carried note, `.`). |
| `autoload/songwriter/tab/lint.vim` | The linter, as a pure function over a block's lines. |
| `autoload/songwriter/tab/highlight.vim` | The time column under the cursor, highlighted in tablature mode. |
| `autoload/songwriter/tab.vim` | The tab commands that work outside tablature mode too: `_`, `\|\|`, `:SongwriterAddBar`, `:SongwriterAddDashes`, `:SongwriterTabChord`. |
| `autoload/songwriter/tab/columns.vim` | Editing time columns, pure: extract, delete, erase (any set of notes, `EraseSet`), shift, make room for a note, rewrite a note in place (`SetNote`). |
| `autoload/songwriter/tab/frets.vim` | `<C-A>`/`<C-X>` in tablature mode: pure `Add()` and the normal and visual entry points. |
| `autoload/songwriter/tab/objects.vim` | Text object ranges and the snapping of other ranges, pure. |
| `autoload/songwriter/tab/paste.vim` | Pasting blockwise registers, pure: row matching, insert, overlay. |
| `autoload/songwriter/tab/operator.vim` | Tablature-mode operators, text objects, `x`/`p`/`P`, `>>`/`<<`, `gp`: buffer entry points around the pure modules. |
| `autoload/songwriter/tab/visual.vim` | Tablature-mode visual mode: selections, motions, operators on a selection. |
| `autoload/songwriter/tab/register.vim` | Blockwise tab registers and the string names of their source tab. |
| `autoload/songwriter/tab/repeat.vim` | `.` for actions that are not operators. |
| `autoload/songwriter/tab/voicings.vim` | Whole chords on a time column: voicings of a chord name in their cycle order, placing one (pure), and `=`/`==`. |
| `autoload/songwriter/tab/chordname.vim` | Naming the chord on a time column (`<leader>?`): the column's pitches, named by `chord#Identify`. |
| `autoload/songwriter/tab/strings.vim` | Moving notes and time columns to another string, keeping the fret or the pitch: pure `Move()` and its entry point. |
| `autoload/songwriter/tab/play.vim` | Playing a tab: open string pitches, the steps a target plays (pure), handed to `sound.vim`. |
| `autoload/songwriter/sound.vim` | Plucked-string synthesis into cached WAV files, the player command, and the timers and jobs that play steps. |
| `autoload/songwriter/sound9.vim` | The synthesis loop in compiled Vim9 script, used on Vim 9. |
| `autoload/songwriter/chord.vim` | Chord model, chord editing, and naming the chord of some pitches (`Identify`). |
| `autoload/songwriter/pitch.vim` | Pitch classes: note names to semitones and back (sharp spelling). Shared by chords and tab string intervals. |
| `autoload/songwriter/keys.vim` | Context-dependent keys: tables and `Dispatch()`, tablature-mode flag and state (`Mode()`), tab-line `w`/`b`/`W`/`B`. |
| `plugin/songwriter.vim` | `:Songwriter*` commands and `<Plug>(songwriter-*)` maps. |
| `ftplugin/songwriter.vim` | Buffer options and key bindings, with a complete `b:undo_ftplugin`. |
| `syntax/songwriter.vim` | Highlighting, with patterns taken from the grammar. |

There are no global functions: everything public is `songwriter#…` and
autoloads on first use.

### Data flow

An operation is a thin buffer entry point around pure logic:

1. `songwriter#tab#model#Read()` parses the block around the cursor (or returns
   `{}` off a tab line, which every entry point treats as a no-op);
2. a pure function computes the result: new lines and/or a cursor column
   (`{'lines': [...], 'col': n}`, `{}` for "nothing to do"), and what to record
   (`state`, `register`);
3. the result is written back.

`edit#Do(Fn, opts)` is the whole sequence for an edit at the cursor, and the
one place that applies the rules of spec 4 (linting after edits) and 4.3
(slots): what happens to an open slot (closed, closed keeping the lint,
filled), whether the edit joins the previous undo step, lints before and
after, opens a slot, keeps the insert state, and records itself for `.`. An
entry point states these as options instead of writing them out, so a rule is
never forgotten in one place. The lints and the edit are computed in memory
(`edit#Linted` is lint plus cursor-following, pure) and written once, and
`model#Write` sets only the lines that differ: an edit that changes nothing
leaves no undo step, and the undo join happens only on an actual write. Entry
points that are not one edit at the cursor (operators, which run through
`g@`; slots closed by motions) use its parts: `Commit` (lint, follow, write),
`LintAndFollow`, `Apply` (write, no lint).

Pure functions are testable without buffer setup and composable: spec item 4
(lint after an edit) is "edit, then lint, then follow the moved note", which is
why `lint#Lint` reports where every note moved.

### Keys

Keys whose meaning depends on context are declared in tables in `keys.vim`, one
set per mode (normal, operator-pending, visual), and mapped as `<expr>` maps
calling `songwriter#keys#Dispatch(key, mode)`, which picks, in order: the
tablature-mode action (mode on and cursor on a tab line), the tab-line action,
or the key's default. Actions run through `<Cmd>…<CR>` (Vim 8.2.1978+ / Neovim
0.5+): no mode change (visual `W`/`B`/`E` stay in visual mode), no command-line
echo, and valid as an operator-pending motion or text object. An action written
`=expr` returns keys instead; operators use it to return `g@`. Plain keys
(`||`, `_`, `<C-A>`, `<leader>m`…) map to `<Plug>(songwriter-*)` so users can
rebind them. `]`/`[` are a second binding of `<C-A>`/`<C-X>`, easier to reach
and easier to repeat; Vim's own `]`/`[` commands (`[[`, `]s`, `[z`…) mean
little in a song file.

`||` is not a double bar line (the format has none); it is the key that lints
the block.

## Format grammar

- **Tab line**: a string name immediately followed by a pipe, `^\a[|]`. Tab
  features are scoped to such lines explicitly; anything else is prose.
  Highlighting uses the broader `^\s*[A-Ga-g]|` (both live in the grammar; they
  are not unified because that would change behaviour).
- **Tab block**: the contiguous run of tab lines around a line.
- **Note**: a fret (a run of digits; `12` is one note spanning two columns) or
  `x`. There is one note model: motions, time columns, operators and the
  linter all use `model#Notes`.
- **Separator**: anything else between notes (`h`, `/`, `b`, `~`, unknown
  notation). A separator is closer to a dash than to a note: `5h7` can be a
  long 5 before the hammer-on, so the 7 has its own moment in time and a note
  on another string can line up under it. It takes up space and is preserved.
  Being the default class, notation the plugin has never heard of is safe.
- **Chain**: a run of notes and separators with no dash. Used by string moves
  only, since a hammer-on stays on one string; everything else works on notes.
  Decoration around a note (`(5)`, `<12>`) is separators too, so erasing the 5
  leaves `()`; digits that are not frets (`7b1/2`) read as notes.
- **Bar**: the region between two pipes. On a line, the bar around column `c` is
  bounded by the nearest pipes strictly left and right of `c`
  (`model#BarAt`).

## Tablature

### Block model

`model#Parse(start, lines)` gives `{start, end, lines, strings}` with each string's
notes (`{col, len, text}`) and pipe columns. Columns are 1-indexed byte columns,
as `col()` returns (tab lines are ASCII). Queries on a parsed block:
`NoteColumns` (block-wide, sorted, unique), `ColumnEnd`, `IsShared`,
`BarColumns` (a bar and its time columns), `BarNotes`, `GapEnd`; on a line,
`BarAt`, `InBar`, `NoteAt`; on a list, `ColumnFor`;
and `Cursor`, the cursor as `{block, lin, col, line}`. The pure column code
(`columns.vim`, `objects.vim`, `paste.vim`) takes a block's lines and parses them
once on entry. Pure
functions address the cursor as `lin` (0-indexed in the block) and `col`. The
width of a line's prefix is known only to `Name`, `Names` and `BodyOffset`.
Text is written into a line with `Splice` (`Blank` turns a note into dashes);
the single mutation primitive across strings is
`InsertColumns(lines, offset, n, char)`: pad every line with dashes up to
`offset`, then insert `n` copies of `char` after it, on every string, so pipes
and notes stay vertically aligned.

### Column insertion (`_`, `:SongwriterAddBar`)

`_` (spec [Tablature][[Editing]] 2) inserts a dash, `:SongwriterAddBar` a pipe,
after the cursor column (at column `col+1`) on every string of the block.
`:SongwriterAddDashes` appends `--` to every string.

### Linter (`||`, spec [Tablature][[Editing]] 1)

The linter works on the block around the cursor, bar by bar. It is a re-flow,
not a full formatter.

**An unclosed last bar is closed first.** A line with anything but whitespace
after its final pipe (`e|--3--5--`) gets a pipe appended before parsing, so its
last bar is linted rather than discarded. Appending at the end keeps every
earlier column, so note moves and the cursor-following (FollowColumn) still
refer to the caller's original columns.

**Note order is sacred.** Relative note order on each string defines when notes
are played: `e|---5--4--|` is a sequence, and collapsing the two notes onto one
column would change the music. So the invariant is: never move a note onto the
same column as another note of the same string. A bar keeps its width
`max_col - min_col + 5` (two leading dashes, the note span, two trailing
dashes).

**Two leading / two trailing dashes are per bar, not per string.** The bar's
leftmost note (on any string) sits two dashes after the shared left pipe; other
strings, whose first note comes later, keep their extra leading dashes, which
preserves the order across strings. Likewise the rightmost note sits two dashes
before the right pipe, and shorter strings are padded so the pipes line up.

**Separators are kept** (spec 1.5). They are placed alongside the notes of their
string, keeping the same distance from what precedes them, so a pushed note
leaves its separator behind (`5h--7`). They count for the bar's edges but not
for overlaps between strings, since they occupy no time. Everything else in a
bar (dashes, whitespace) is re-rendered as dashes.

**Empty bar** (no note on any string) becomes `|-----|`: five dashes rather
than the two of a bar edge, so that a slot opened in it is its middle dash and
a note typed there (`|--7--|`) needs no reflow.

**Empty bars at the end are deleted** (spec 1.4): a trailing empty bar is
leftover space, not music. All of them go, not just the very last one, so that
lint stays idempotent (linting twice changes nothing); empty bars between
notes are rests and are kept. A tab keeps at least one bar, so an all-empty tab
lints to `|-----|`, and so does a tab with no bar at all (`e||`, left by
`da|` on the only bar). This applies to every lint, so `cap` leaves a single bar. A cursor that was in a deleted
bar lands on the tab's last pipe.

**Overlapping notes** (spec 1.3, two-digit notes). Each note gets a natural output
offset `c0 - mincol + 2`, then a fixed-point pass enforces:

- *same-string order*: a note keeps its original gap to the previous note on
  its string;
- *cross-string de-overlap*: a note starting strictly after a note on another
  string but inside that note's span is pushed right to leave exactly one dash
  after it. Notes starting on the same column are aligned and never split; a
  single digit lining up with the first digit of a `12` is left alone.

The pass is capped at 200 iterations (never reached in practice): pushing one
note can collide with another on a neighbouring string.

**Output**: `lint#Lint(lines)` returns `{lines, moves}`; `moves` lists every
note's line, bar, width and column before and after, so callers can keep the cursor on
the same note. Only the string name's first character is kept, and anything
after the final pipe is dropped.

### Vim's units in a tab

Text is one-dimensional; a tab has two axes, time (left to right) and strings
(top to bottom). Each of Vim's units is mapped onto the axis where it means
something, so that its keys keep their instinctive sense:

| Vim unit  | In a tab | Keys |
|-----------|----------|------|
| character | the time column as a position, the note as content | `l` `h`, `x`, `ic`/`ac`, `in`/`an` |
| word      | a chain on one string: a dash is the space between words | `w` `b` `e` `ge`, `iw`/`aw` |
| WORD      | a bar | `W` `B` `E`, `i\|`/`a\|` (`iW`/`aW`) |
| line      | for editing, the time column; for moving, the string | `dd` `yy` `>>`; `j` `k` |
| sentence  | nothing: the format marks no phrases or beats | native |
| paragraph | a tab (tabs are separated by blank lines) | native `{` `}` `ip`/`ap` |

- **A word is a chain**: Vim's word is a run of non-blanks, and a chain is a
  run of notes and separators with no dash, so `5h7` is one word, as it is one
  unit for the string moves (spec 7.1). `l` still reaches its 7, which has its
  own time column, so `l` <= `w` <= `W` in reach.
- **The line splits in two.** A text line is both the unit `j`/`k` move
  across and the record `dd`/`yy`/`>>` act on. Across strings, a string cannot
  be that record (nobody means to delete the G string), so editing goes to the
  time column (see "Operators and text objects") and moving stays on strings.
  `D`/`C` need an end, which a column does not have: they borrow the bar's.
- **An operator's reach follows its motion** (spec 6.2). The string motions
  (`l` `h` `w` `b` `e` `ge`) move along one string, so after an operator they
  erase notes on that string, each as `x` does; `dl` is `x`, as in Vim.
  Widening `dw` to every string would delete every other string's notes up to
  wherever this string plays next, which in a sparse tab is much more than a
  word. Column-wide targets (`ac`, `a|`, `dd`, `dW`, `d$`, `f`/`t`) act on
  time columns.

### Tablature mode (`<leader>t`, spec [Tablature][[Editing]] 3)

A buffer-local flag, `b:songwriter_tabmode`, set on by the ftplugin when a
buffer is opened (and unset by `b:undo_ftplugin`); unset means off.

**Two states, as in Vim.** In the normal state moving never changes the file:
Vim's contract is that motions only move, and a motion that edits puts cursor
moves in the undo history, marks a file modified just by reading it, and fills
the change list. The insert state is for writing: there, moving across notes
opens slots for new ones. It is a state of tablature mode rather than Vim's
own insert mode so that `h`/`l` keep moving (in Vim's insert mode they would be
text, and arrow keys would be needed).

- **The state** (`tab/insert.vim`) is kept in `tab/state.vim`, valid only while
  `b:changedtick` is unchanged: the edits made in it (opening, filling, closing
  a slot) record it again (`insert#Keep`), and any other change (`u`, `x`, an
  operator) ends it without the other code having to know about it. Opening a
  slot enters it (`slots#Open`), so `a`/`i`, `c`, `o`/`O` and
  `:SongwriterNewTab` all do; `<Esc>` closes the slot and leaves it.
  Entering shows `-- TAB INSERT --`, after a `redraw` so that repeated state
  changes replace each other instead of piling up into a hit-enter prompt;
  `songwriter#keys#Mode()` is there for status lines.
- **`w`/`b`/`e`/`ge` (3.2)**: by word (a chain, see "Vim's units in a tab")
  on the current line: `w`/`b` stop on a word's first note, `e`/`ge` on its
  last (`model#Words`). Dashes and pipes are not stops; a two-digit fret is
  landed on at its first digit.
- **`l`/`h` in the normal state (3.3.1, 3.3.2)**: next/previous stop: a column
  where any string of the block has a note, or the middle dash of an empty bar
  (3.3.4), since a bar with no time column could otherwise never be reached.
  Pipes are not obstacles. With no stop that way, the cursor stays.
- **`l`/`h` in the insert state (3.3.3)**: the gaps between notes are stops
  too. On a note column, `l` is `a` and `h` is `i`. On the open slot, they close
  it and move on. Where a slot is, is a *position* (`stops#Step`): a column,
  the gap after or before a column (the side it was entered from), an empty
  bar, a new bar. The arrows carry a note through the same positions (3.6), so
  `l`/`h` and `<Right>`/`<Left>` go to the same places and open gaps the same
  way, by construction. From a slot, the move goes on from its position:
  towards the column it was opened from it lands back on it, away from it it
  goes to the next stop. A slot that is part of a bigger edit (`c`, `o`) has no
  position and goes on to the next stop. So from `3` in `3-5`, `l` `l` `l` gives slot, `5`, slot; each gap
  is visited once per direction, and a bar line needs no special case: from a
  bar's last note `l` opens a slot in that bar, then reaches the next bar's
  first note. Landing in an empty bar opens a slot in its middle
  (`slots#EmptyBar`). Elsewhere (the cursor moved off the stops with native
  keys), `l`/`h` move as in the normal state.
  - *End of the tab (5)*: `l` with no stop further right, from a slot in a bar
    with notes or from anywhere past the stops, in the last bar of a tab whose
    lines end with a pipe, appends a new bar `-----|` and lands on its middle
    dash, a slot like any other. On the new bar's slot (a bar with no note)
    `l` does nothing, so holding `l` never piles up bars.
- **`L`/`H` (3.3.5)**: the normal-state `l`/`h` in both states
  (`StepColumn`), so the insert state has a way through notes that does not
  stop on every gap. An open slot is closed first and the move goes on from
  its note as `l`/`h` would (`s:from_slot`); they never open one, not even in
  an empty bar or at the end of the tab. After an operator and in visual mode
  they are `l`/`h`. Vim's own `L`/`H` (bottom/top of the window) are little
  use in a tab, whose few lines all fit on screen.
- **`W`/`B`/`E` (3.5)**: by bar, as Vim's WORD motions are a bigger
  `w`/`b`/`e` (`stops#BarStop`, pure). `W` goes to the first time column of
  the next bar, `B` to the first of the cursor's bar or the previous one, `E`
  to the last of the cursor's bar or the next one, so they land where a note
  can be edited rather than on a pipe. Bars are read from the cursor line's
  pipes (aligned in a linted tab), time columns from the whole block; a bar
  with no note stands for its middle dash. Normal and visual mode only: after
  an operator `W` keeps the pipe motion, so `dW` stays "to the end of the
  bar" (`D`, 6.8.1).
- **`a`/`i` (3.1)**: open a slot for a new note on every string and land on it.
  `a` anchors on the rightmost note end, on any string, among the notes of the
  cursor's bar that start at or before the cursor: the note column under (or
  left of) the cursor, found even when the cursor line is an empty string. It
  inserts as many dashes as needed for the slot to sit exactly one dash after
  the anchor while the next note, on any string, keeps a 1-dash gap (the next
  pipe, 2 dashes): `e|--3--5--|` with the cursor on 3 -> `e|--3---5--|`. `i`
  mirrors this to the left of the leftmost note of the bar ending at or after
  the cursor, keeping the previous note 1 dash and the previous pipe 2 dashes
  away. Gaps are checked on every string, since a note on another string
  occupies the column just as much.
  No anchor note: no-op, not even the lint: `a`/`i` lint first (4.2, below), but
  that lint is part of opening the slot (`edit#Do`'s `open`).
- **Digits (3.4)**: a digit on a dash replaces it; on a note it replaces the
  whole note (both digits of a `12`). To type a two-digit fret, a digit typed
  straight after another is appended to it instead (3.4.1): `EnterNote` records
  `b:songwriter_typing = {line, col, tick}` after each digit, and the next
  digit appends only when the cursor and `b:changedtick` still match. Any move
  or edit ends the run, so coming back to a note replaces it. The block is then
  linted (4.1, below), which fixes the spacing. `x` on a dash enters a muted
  note the same way (3.4.3); on a note it stays the erase of spec 6.7. Off tablature mode or a tab
  line, digits keep their count meaning. Digits work in both states and keep
  the state they are typed in.
- **Typing a run of notes (3.4.1.1-3.4.1.3)**: in the insert state the next
  note is the common case, so a digit straight after a note opens a slot after
  it (`AddNote(1)`, what `l` does) unless appending it makes a real fret (no
  leading zero, at most `g:songwriter_max_fret`). The fret range resolves the
  `12`-or-`1 2` ambiguity: only `1` and `2` (up to 24) can start a two-digit
  fret, and `<Space>`, which is `l` in the insert state, ends a `1` that is
  meant alone. The cursor stays on the typed note rather than moving to the
  next slot right away, so `j`/`k` still build a chord on the note's column,
  and nothing is opened that would have to be closed again. The normal state
  keeps the plain append of 3.4.1: there a digit edits the note under the
  cursor, it never adds one.
  Separators are typed the same way: straight after a note (`JustTyped`, a
  dispatch context of its own in `keys.vim`), `h p b r t s / ~` write a
  separator in a new column (on every string, so later notes keep their gap),
  and `typing.separator` makes the next digit go in a new column right after
  it. Those keys lose their meaning only for that one keystroke, where moving
  or pasting is rare; `\` is left out as it is the default `<leader>`.

- **Carrying a note with the arrows (3.6)** (`tab/carry.vim`): the arrows are
  free in tablature mode (`hjkl` are taken), and moving a note is a drag, so it
  belongs to the insert state, next to typing. The first arrow lifts the note
  as `x` erases it; the rest of the tab, the *base*, is kept with the carry
  state (tied to `b:changedtick`, so any other edit ends the carry). Each arrow
  moves a position over the base along the insert-state stops of `l`/`h`
  (`stops#Step`, shared with them), and the tab is rendered again from the base
  with the note there. A gap is opened from the side it is entered, as `a`
  (`<Right>`) or `i` (`<Left>`) would; it is named after the column before it
  only to recognise the start position. Rendering
  from the base rather than editing the last result is what puts back a note
  the carried one replaced and closes a gap it opened, with no bookkeeping of
  what was overwritten; the start position renders the original lines, so
  coming back leaves no trace. Moves after the first are joined to its undo
  step. The base keeps as many bars as the tab had, even when the lifted note
  leaves the last ones empty (which lint would drop): they stay stops for the
  note to go back to (3.3.4). Back from a new bar, the note goes to the gap
  after the last column, where it came from, rather than onto that column as
  `h` does from the new bar's slot (5): `h` lands the cursor on a note, but a
  carried note would replace it. Off a note the arrows keep their meaning (`carry#Key` returns the
  arrow itself), so they still move the cursor out of a slot.
- **Duplicating a note (3.7)**: `<leader>k`/`<leader>j` are a carry whose
  base is the whole tab, note included (`carry#Copy`), started one string
  away. Rendering the copy over that base never touches the original, and
  carrying the copy back onto it renders the tab as it was, so nothing new is
  needed beyond the carry's render. Positioning the copy is the next thing
  done, so the move follows at once with `hjkl` as the arrows: a dispatch
  context of its own (`s:moving` in `keys.vim`, checked first), active while
  the carry is marked `moving`, the insert state is on and the cursor is on
  the copy (`carry#Moving`). It needs no state of its own to end: any edit,
  cursor move off the copy or leaving the insert state (`<Esc>`, or a lone
  `<leader>`, `carry#EndMove`) gives `hjkl` back. A lone `<leader>` map makes
  Vim wait 'timeoutlen' after it, as any leader prefix already does. A leader
  that is also a context key (`<Space>`, which is `l` in the insert state)
  has only the context map, which replaces the `<leader>` one, so `Dispatch`
  recognises the leader itself while a copy is moved.

### Linting after edits (spec [Tablature][[Editing]] 4)

Tablature-mode edits lint the block:

- **4.1**: a digit enters the note, then the block is linted.
- **4.2**: `a`/`i` lint, then open the slot. `l`/`h` opening a slot in the
  insert state are the same operation (`AddNote`), so they lint too, as does
  `l` adding a bar at the end of the tab (5, `AddBarSlot`).
- **4.3, closing a slot**: an open slot is remembered in `b:songwriter_slot`
  (`tab/state.vim`), so it counts only while `b:changedtick` is unchanged: any
  other buffer change (undo, `x`…) drops it, since the block it pointed to may
  no longer be there. The next `h`/`l`/`w`/`b`/`W`/`B`/`E`/`a`/`i`/`<Esc>`
  closes it first (`slots#Abandon`); `j`/`k` are not mapped, so the slot
  survives them. A digit fills the slot and forgets it.
  - *A slot opened by moving, `a`/`i` or a new bar is undone*: closing it gives
    the tab back exactly as it was before, including the lint of 4.2, so that
    wandering in the insert state leaves no trace. `slots#Mark`, taken before
    anything changes, records the block's lines, the cursor column and the undo
    sequence number. Closing runs `:undo` when the slot's change is the last
    undo step and that step holds nothing else (its sequence number differs
    from the one before it). Then no undo step is left behind and a file saved
    before `a` is unmodified again. Inside `:normal`, a macro or a mapping,
    several keys share one undo step, and `:undo` would take earlier changes
    with it: then (or if undoing did not give the lines back) the recorded
    lines are written instead.
  - *A motion closing a slot keeps the lint (4.3.3)*: otherwise walking an
    unlinted tab with `l`/`h` would lint it at every slot and unlint it at
    every close, and the whole tab would jump at each step. `AddNote` and
    `AddBarSlot` record the linted lines in the mark (`slots#Linted`); the
    motions call `slots#Abandon(1)`, which undoes the slot as above and then
    writes the linted lines back, an undo step of its own. `<Esc>` and the
    other closers still give back the tab from before the lint.
  - *A slot that is part of a bigger edit is linted*: `c` (6.6), `o`/`O` (8)
    and `:SongwriterNewTab` (9) open a slot in what they made; `<Esc>` there
    must keep the deletion or the new tab, so closing lints, leaving an empty
    bar as `|-----|`.
- **4.3.1**: a digit typed into a slot, or appended to a fret being typed, is
  joined to the previous undo step (`:undojoin`), so `a7` or `a12` is one undo
  step and `u` gives back the tab as it was before `a`.

**The cursor follows the music** (`lint#FollowColumn`): on a note it stays on
the same digit of that note; elsewhere in a bar it keeps its distance from the
nearest note starting at or before it (any string), clamped before the next
note and inside the bar. Notes before/after the cursor stay before/after it, so
`a`/`i` find the same anchor after the lint as before. `||` lints without
moving the cursor.

`<Esc>` is a context key like the others (`insert#Escape`). Outside tablature mode `Dispatch`
returns the key itself. Special keys are written in `<>` notation in the
tables, and the ftplugin passes them to `Dispatch` as `<lt>Esc>`, since
`<Esc>` would otherwise be translated in the map's right side.

### Operators and text objects (spec [Tablature][[Editing]] 6)

The spec items carry the behaviour; this records why, and how it is built.

- **The time column is the unit of editing.** Vertical alignment says which
  notes are played together, so in tablature mode no operator may change one
  string without the others. Native single-line edits followed by a lint are not
  safe: lint cannot tell an intended shift from an accidental one, and would
  keep a wrong alignment. Single-string editing stays available by leaving
  tablature mode.
- **Vim's grammar rather than one command per operation.** Operators (`d`, `y`,
  `c`) times targets (columns, bars, motions) give every combination, plus
  registers and `.`, for free. They run through `operatorfunc`/`g@`. A `<Cmd>`
  before `g@` lints the block first (its undo step is joined to the
  operation's with `:undojoin`); it consumes the count, so the count is given
  again after `g@` (`g@3w`). `v:register` is not reliable inside the
  operatorfunc, so the operator, register and "exact target" flag are kept in
  `s:pending`.
- **Spacing is rhythm.** The gap after a note belongs to it: `ac`, a snapped
  motion range and `x` on a lone note remove it with the note, so the
  previous note keeps its length and what follows moves earlier. Rests exist
  only where the user put them with `_`; erasing never creates one, except that
  `x` on a shared column leaves the other strings' timing intact. Other
  strings' music wins over the gap: `x` on a lone note removes only as much
  of its gap as leaves every other string's notes and separators untouched and
  apart (`columns.vim` `s:removable`), since a dash lost between `10` and `12`
  would turn them into `1012`, which no lint can undo; with no room at all the
  note becomes dashes, as on a shared column.
- **Across strings (6.2.4).** `j`/`k` after an operator move across strings,
  so `dj` acts where they go: the time column under the cursor, on the
  strings covered (`operator#Across`, an operator-pending map like the text
  objects). Its notes are erased as `x` erases each (`columns#EraseSet`, which
  `x`, the string motions and the note objects share), so the column goes with
  its gap only when no note is left on it. The register is one column, with
  the strings not erased as dashes (as `in`), rather than `x`'s one column per
  note: the notes were played together and should paste together.
- **The column is the tab's line.** A doubled operator acts on a line in text
  and on the time column in a tab: `dd`/`yy`/`cc` are `dac`/`yac`/`cac`, so
  `ddp` and `yyp` swap and duplicate columns as they do lines. The second key
  is an operator-pending map (`Doubled`), not a normal-mode `dd` map: this
  gives `d3d` and avoids waiting on `d` for a possible `dd`. Whole tabs are
  reached with `ap` (tabs are separated by blank lines) or any line-wise
  motion. `D`/`C` stop at the bar's end, the column-wise analogue of a line's
  end. `Y`/`D`/`C` return the operator followed by their target as a
  `<Cmd>`, since keys returned by a `noremap` would not reach our maps.
- **Notes.** `in`/`an`, `iw`/`aw` and the string motions (6.2.2) act on one
  string, but keep the register a full-height column with dashes elsewhere,
  the same shape as `x` writes, so a copied note pastes on its own string and
  as new time. Objects yank their exact range; a string motion yanks what `x`
  would write for each note it covers, one after the other, so `dl` and `x`
  fill the register alike. Either way, deleting erases each note as `x` does,
  right to left so that a removed column does not shift the next ones. `gp` is the other way
  to paste: onto an existing column, no time added, refusing to replace a
  note, since silently changing music is what these operations avoid.
- **`>>`/`<<`** nudge rhythm: a dash before the column, inserted or removed on
  every string, so what follows moves with it. Lint keeps two dashes after a
  pipe, so on a bar's first column they would be undone and do nothing.
- **Text object names.** `ic`/`ac` (column), `i|`/`a|` (bar, also
  `iW`/`aW`), `in`/`an` (note), `iw`/`aw` (word). Bare letters
  are motions after an operator (`db`), and `ib`/`ab` are Vim's parenthesis
  objects; `i|` follows Vim's delimiter objects (`i"`, `i(`). Our objects set an
  "exact" flag so the operator does not snap them (`ic` would otherwise grow
  into `ac`). Column counts stop at the bar's end, so a column object never
  contains a pipe.
- **Ranges that cross a bar line** (`d$`, `d2W`): the columns are removed and
  a pipe is put back where the range started, so the bar it started in is
  closed there and nothing is left after the final pipe (which lint drops).
- **Registers are plain blockwise registers**, so they interoperate with
  `<C-v>` and with editing outside tablature mode. Source string names are kept
  in `g:songwriter_register_names` with the register's content; they count only
  while the register still holds that content. Pasting between tabs with a
  different number of strings matches rows from the bottom (bass into guitar)
  and refuses when tuning names disagree, instead of silently putting notes on
  the wrong strings. A line-wise paste of tab lines next to a tab gets a blank
  line between them, or the two tabs would become one.
- **`c` opens its slot** with the existing `a`/`i` slot logic, anchored on the
  note column that was next to the deleted range (before the next one,
  else after the previous one, else an empty 5-dash bar), followed through the
  lint.
- **`.`** Operators repeat natively. `g@` records every operator, including a
  yank, so after `ya|` a `.` repeats the yank (native `y` is not repeatable);
  accepted rather than reimplementing redo. `x`, `p`, `P`, `>>`, `<<` are `<Cmd>`
  actions, invisible to redo: they record themselves in `b:songwriter_repeat`
  (`repeat#Record`) with the changedtick they left, and the `.` map runs
  them again while the buffer is unchanged since. The string moves (spec 7)
  record themselves the same way.
- **No counts in front of a command.** Digits enter notes in tablature mode
  (spec 3.4), so `3x` types a 3. Counts work after an operator (`d2ac`, `d3w`)
  and in visual mode, where digits are not mapped. The entry points still take
  a count.
- **Visual mode.** Text objects show the real (full-height) extent as a
  blockwise selection, and extend when repeated while the selection is still
  theirs; a plain `v` selection is widened at operator time instead, so `v`
  does not move the cursor off its string. `V` is a column selection (the
  common case in a tab), not line-wise: whole tabs are already `dap`/`yap`,
  and the native line-wise selection is one more `V` away (`VV`). `j`/`k`
  are clamped to the tab rather than blocked on a full-height selection, so a
  partial `<C-v>` still grows and shrinks natively.

### Rewriting a note in place (`<C-A>`/`<C-X>`, typing, spec [Tablature][[Editing]] 3.4, 11)

A note's text changes width (`9` -> `10`, `12` -> `5`) while it stays on its
time column. Splicing the new text into its line alone shifts everything after
it on that string by the difference, so the string drifts out of the time
columns it shared with the others (a different rhythm), and lint cannot tell:
it aligns pipes and splits overlaps, but has no memory of which notes were
together. So every edit that rewrites a note goes through one primitive,
`columns#SetNote`, and `test/songwriter_invariants_frets.vader` checks over the
corpus that the notes of each time column still start together afterwards.

- **Narrower: the chain closes up, dashes after it.** The note keeps its
  start; the rest of its chain follows it (`10h7` -> `9h7-`), because a dash
  inside a chain (`9-h7`) would detach the separator from the note it belongs
  to, and a chain is written as one unit. Its other notes move by the
  difference, the one place where a note leaves its column; notes outside the
  chain keep theirs (`10-7` -> `9--7`).
- **Wider: the gap first, then room for everyone.** The dashes after the note
  are used while one stays before its string's next chain (that dash is what
  keeps `10` and `7` two notes) and the note covers no other string's time
  column. What is still missing is inserted on every string between the note
  and the next time column, so all that follows moves together. Unlike
  `MakeRoom` (a note written onto a free column), the note is already there:
  no dash goes before it, and a separator right after it is not pushed off,
  since the chain must stay whole.
- **Visual `<C-A>` changes every fret selected**, so a riff is moved up the
  neck in one go, rather than Vim's first number per line, which means
  nothing in a tab. The notes change right to left: each one's room or
  closing-up only affects what lies to its right, which is already done.
- **`<C-A>` finds its note as Vim does** (under the cursor or next on the
  line), because that is what the key has always done in the buffer, and the
  cursor stays on the note's start, the column tablature mode works on.

### Moving notes between strings (spec [Tablature][[Editing]] 7)

`tab/strings.vim`: a pure `Move()` and its entry point `Change()`, which lints
before and after like the other tablature-mode edits.

- **Keys.** `s` keeps the fret, `S` keeps the pitch; then `k`/`j` move the note
  under the cursor, `K`/`J` its whole time column. `J`/`K` alone are left to
  the user (often remapped for navigation). Native `s` edits one string only,
  which tablature mode already rules out (spec 6). `S` is therefore not `cac`
  (spec 6.8): a lone `S` would wait for 'timeoutlen' to rule out `Sk`, and
  `cc` already does it. No count: digits enter notes
  (spec 6.12), and moving one string at a time is what is needed.
- **Chains move whole.** A hammer-on or slide cannot change strings halfway, so
  `s`/`S` take the chain under the cursor (spec 7.1). `K`/`J` act on a time
  column and refuse a chain that starts before it, rather than dragging notes
  from another column along.
- **One string per move.** A column moves as a whole, every note by one string,
  so its notes never collide with each other: sources are cleared first, then
  each note is written on its new string.
- **Pitch from the string names.** The interval between two neighbouring
  strings is the difference of their pitch classes (`pitch.vim`), modulo 12.
  This assumes strings listed from the highest to the lowest and less than an
  octave apart, which covers standard and drop tunings, basses and 7-strings.
  String names are one letter, so an evenly lowered tuning (E flat standard
  written `eBGDAE`) has the same intervals and works. Two strings with the same
  letter (`E` above `e`) give no interval and the move is refused, rather than
  guessing an octave.
- **Room, not overlap.** A note that gets wider (`7` -> `12`) could touch the
  next note on its new string and merge with it (`123`), which lint cannot
  undo. So dashes are inserted on every string, right after the note when it
  would touch the next note or the pipe, or right before the column when a
  note ends just before it there. Insertion points never cut a note in two on
  another string; the following lint normalises the spacing.

### Chords on a column (`=`, `==`, spec [Tablature][[Editing]] 10)

`tab/voicings.vim`: pure `Voicings()` (a chord name and string names in, the
voicings in their cycle order out) and `Place()`, and the entry points.

- **The root is on the cursor's string.** The string is already where the
  cursor is, and it is the choice a guitarist makes first (open Am from the A
  string, barre from the low E), so no other argument is needed to pick
  between open and barre shapes.
- **`==` cycles, ordered by how often a voicing is wanted.** Lower root strings
  come before higher ones (the E-string barre is the usual second choice after
  an A-string shape), lower frets first, and the 12th-fret repeats of open
  shapes last. `==` is one key read by `=` (`getchar()`), not a second map, so a
  lone `=` never waits for 'timeoutlen'. It works only straight after `=` or
  `==` (the voicing list is kept in `tab/state.vim` with its changedtick), and
  joins their undo step.
- **Fixed shapes for standard tuning, intervals for power chords.** Full chord
  shapes are only playable as the familiar fingerings in standard tuning, so
  they are tables of fret offsets (CAGED: E, A, D at any fret; C and G in open
  position only, where they are actually used) and other tunings are refused.
  A power chord is three strings and computes well from the string names, as
  `S` does (spec 7.3), so drop D gets its one-finger shape for free.
- **The chord replaces the column**, as a digit replaces a note: the notes
  starting on it go, and a two-digit fret gets room as a moved note does
  (`columns#MakeRoom`, spec 7.5). Unplayed strings stay dashes: muting marks are
  the user's call (`x`).
- **A quality alone changes the chord there** (10.7). The root is the note on
  the lowest string of the column: no chord recognition, so it works on any
  column, a single note included, and is right for every root-position
  voicing this module writes. Keeping the root's fret when a voicing has it
  keeps the chord where it was on the neck. A name is a quality when it is not
  a chord but `C` + it is, which separates `b` (B) from `m7` without a list.
- **`+` reads the column, not a remembered state** (10.8). Power, major,
  minor is the order a riff grows in, and checking which of them the column
  holds (exactly, rooted on the cursor's note) lets `+` go on from a chord
  typed with `=` or entered long before, with no state to keep in sync with
  edits. Unlike 10.7 the root is the cursor's note and must stay so: the chord
  must be rooted on that string at that fret, or `+` is refused, so the next
  `+` still finds its root under the cursor. Minor is the end: a third quality
  would have to be chosen arbitrarily, and `=` covers the rest.
- **Typing on.** In the insert state a chord counts as a typed note
  (`typing.chord`): a digit after it opens the next slot even when it would
  extend the root's fret (`1` then `2` is not `12`), and separators are not
  typed after it.

### Naming a column's chord (`<leader>?`, spec [Tablature][[Editing]] 13)

- **Computed from pitches, not looked up in the shapes.** The column's notes
  become MIDI pitches through the string names (`play#OpenPitches`, as for
  playing), so any tuning and any fingering is named, not only the CAGED
  voicings `=` writes. Matching the shapes first would add nothing: every
  shape is a root-position chord whose notes are exactly its quality's, so it
  is already the first name. Naming offline also keeps the plugin free of any
  network dependency.
- **Exact pitch-class sets, every root tried.** A chord fits when the
  column's pitch classes, seen from one of them, are exactly a quality's
  intervals; the fifth alone may be missing, and only from qualities where it
  says nothing (not `5`, `6`, `sus`, `dim`, `aug`), so `C E A` is `Am/C`, not
  also a fifthless `C6`. Every fitting chord is listed, since the same notes
  are often two chords (`C6`, `Am7/C`) and only the player knows which is
  meant. The one on the bass comes first; the rest go up from the bass.
- **Read-only**, like playing: no lint, no undo step, so it works outside
  tablature mode as well. The pure part is `chord#Identify` (pitches to
  names), independent of tabs, and `chordname#Message` (lines to message).

### New tab (`o`/`O`, `:SongwriterNewTab`, spec [Tablature][[Editing]] 8, 9)

`o`/`O` open a tab the way they open a line in text: under / over the whole
current tab, never between its strings. The new tab copies the string names, so
a bass or drop-D tab gets a matching one, and starts as the new bar of spec 5
does (`|-----|`, slot in the middle, `b:songwriter_slot`), in the insert
state. A digit fills it; closed without one, it is linted rather than undone
(4.3), so the new tab stays. The blank line keeps the two tabs separate blocks (as a
line-wise paste does, 6.3.2). The cursor keeps its string, so typing goes on
on the string being worked on. Outside tablature mode `o`/`O` stay native.

`:SongwriterNewTab` (spec 9) is the way in when there is no tab yet to press
`o` in. It builds the same empty tab from given string names (validated by
`grammar#IsStringNames`, the same single-letter name a tab line starts with),
and turns tablature mode on, since the slot it opens only means something
there. It is a command rather than a key: a key on a prose line would take a
native key away, and the command takes the tuning as its argument.

### Time column highlight ([[Rendering]] 4)

Column-wise operations act on the notes starting on the cursor's column, on
every string, which the cursor alone does not show. `tab/highlight.vim` keeps
a window match (`matchaddpos`, group `songwriterTimeColumn`, linked by default
to `CursorColumn`) on that column, on every string of the tab, notes and
dashes alike, as wide as its widest note: a full-height band shows the column
as one thing, and which strings are silent on it, where highlighting only its
notes would leave scattered cells. The note under the cursor decides the
column, so a cursor on the `2` of `12` still shows that note's column. On a
gap where no note starts, nothing is highlighted.
Buffer-local autocommands update it on every cursor move and text change,
and clear it when the window loses focus or shows another buffer (a window
match would otherwise stay on that buffer). Reading the block on each move is
cheap (a few short lines); the match is replaced only when the column
changes.

### Playing notes (`<leader>p`, spec [Tablature][[Editing]] 12)

- **An operator, not a set of keys.** Playing reuses the d/y/c machinery
  (`g@`, `s:pending`, the text objects, string motions, `j`/`k`, visual
  selections), so every target that can be yanked can be heard, and what is
  played is what `y` would reach. `play` is one more op in `ApplyRange`,
  `s:across` and `ApplyLines`, which branch before any edit; `Start` skips
  the pre-lint, so playing never changes the file (an invariant checks it).
  The doubled form is `<leader>pp` (the `p` operator-pending key), and
  `<leader>P` is `<leader>pin`, since one note is the most common case.
- **No dependencies but a player.** Vim has no portable audio (`+sound` is
  Linux-only and rarely built), so the plugin writes WAV files and starts a
  player command as a job: `afplay` ships with macOS, `paplay`/`aplay` with
  most Linux desktops. Windows is not supported. With no player the feature
  is inert; nothing else depends on it.
- **Karplus-Strong synthesis in Vim script.** A delay line of noise through
  a damping lowpass sounds like a plucked string and is a few lines of code.
  A first-order allpass, tuned for the note's frequency, covers the fraction
  of a sample in the period (rounding alone makes high frets tens of cents
  sharp), and the damping is set per pitch so notes die away in a guitar-like
  time (`s:t60`) instead of high notes vanishing at once. The noise is seeded
  by the pitch, so a pitch always gives the same file.
- **Cached per pitch.** A guitar spans about 50 pitches; each is generated
  once (1.2 s at 22.05 kHz) and kept in the cache directory, named with a
  synthesis version (`pluck1-…`) so a change to the synthesis makes new
  files. On Vim 9 the sample loop is compiled Vim9 script (`sound9.vim`),
  about 25 times faster than legacy script (a whole tab's first play: 0.2 s
  rather than 3 s); Vim 8.2 and Neovim use the legacy loop. A test checks
  both give the same bytes.
- **Timing with timers, mixing by the OS.** Each note is its own player job,
  started by a timer at its step (a beat at `g:songwriter_play_bpm`) plus
  a strum delay per string (80 ms by default, so each note of a chord is
  heard distinctly), so no mixing code is needed. The strum does not push
  the next column back: steps stay evenly spaced, and at fast tempos a wide
  chord's last notes may overlap the next column (a six-string strum takes
  400 ms of a 600 ms beat at 100 bpm). A note stops the
  previous job on its string (a string sounds one note at a time), and a new
  play stops everything first. Spacing is not read as rhythm: it is only a
  loose indication (spec 6), so every column gets the same length.
- **Pitches from the string names**, as the `S` moves read them (7.3), with
  the lowest string in [B1, A#2]: right for six- and seven-string guitars
  and drop tunings; a bass sounds an octave up, which is acceptable for
  checking notes by ear.
- **Testing.** Tests set `g:songwriter_player = []` (sound off) and read
  what would have played with `songwriter#sound#Last()`; the synthesis and
  the schedule are pure functions.

### Outside tablature mode

On a tab line, `w`/`b` stop on notes, string names and pipes but never on dashes
(spec [Tablature][[Motions]] 1-2), and `W`/`B` jump to the next/previous pipe
(3-4) using `search()`, which ignores `iskeyword`: on a tab line, Vim's own
`W`/`B` see the whole line as one WORD and are useless. `L`/`H` keep their
native meaning (5). Off a tab line every key keeps
its default behaviour.

## Chords

The chord grammar (`grammar#ParseChord`) is strict and anchored: a token is a
chord only if all of it is a root (`[A-G][#b]?`), a quality built from known
parts (`m`, `min`, `maj`, `M`, `dim`, `aug`, `sus`, `add`, digits, `#`, `b`,
`+`) and an optional `/bass` root. So `Bad` and `xAm` are not chords, while
`Am7b5`, `Dadd9` and `D/F#` are. The token under the cursor is the maximal run
of chord characters (`[A-Za-z0-9#/+]`) around it, so a slash chord is found
whole whichever part the cursor is on. Tab lines never hold chords (`B|` is a
string name).

The chord model in `chord.vim`:

- `s:chord_parse(name)` -> `{name, root, quality, bass}`, or `{}` for a
  non-chord; `root` and `bass` keep their spelling;
- `s:chord_build(root, quality, bass)`;
- `s:chord_transpose(parsed, semitones)`: root and bass both move; flats are
  normalised to sharps, the single spelling in the chromatic scale;
- `s:splice_chord(line, found, new)`.

A chord action is: find the chord under the cursor, parse, transform root or
quality, build, splice back. The public actions differ only in the transform,
and are no-ops off a chord, except `<Ctrl-A>`/`<Ctrl-X>`: they transpose by
their count, and off a chord they run Vim's own increment/decrement, so numbers
in prose and frets in tabs still work. On a tab line `nrformats` gets
`unsigned` for that call, since a dash before a fret is not a minus sign. In
tablature mode a tab line goes to `tab/frets.vim` instead (see "Rewriting a
note in place"): Vim's increment splices one line and would shift that
string's later notes off their time columns.
In visual mode they act per selected line: the chords the selection touches are
transposed (spliced right to left, so a wider chord does not shift the others'
columns before they are found), and a line where it touches none gets Vim's
visual increment on its selected part, again unsigned on tab lines. Unlike
Vim's, the selection is kept afterwards (same corners, cursor on the same end),
so pressing `<Ctrl-A>` again keeps transposing.
`<leader>m` treats a leading `m` or `min` (but not `maj`) as minor.
Highlighting stays permissive and accepts false positives such as the word "A"
(spec [Chords][[Rendering]]); it is separate from the editing grammar.

## Testing

- Vader, `make test`; the pre-commit hook enforces a green suite. Each test
  file runs in its own Vim, in parallel (`JOBS`, one per CPU by default), so
  a slow file holds the whole run: keep files under a second or so, and
  split one that grows past that.
- Buffer transformations use `Given songwriter` / `Execute` or `Do` / `Expect`,
  so the before/after tab is visible; cursor positions and pure functions use
  `Assert*`.
- Vader reuses one buffer across the cases of a file, so buffer state (the
  tablature-mode flag) is reset in a `Before:` block wherever keys are typed.
- Key mappings are exercised end-to-end with `normal` where the result is
  observable; `Dispatch` and `b:undo_ftplugin` have their own tests.
- **Invariants** (`test/songwriter_invariants_*.vader`) are checked over a corpus
  of tabs and every relevant cursor position rather than one example: lint is
  idempotent and keeps each string's notes, the normal state never edits, an
  abandoned slot and a carried-back note leave no trace, each edit is one
  undo step and leaves the tab linted, a rewritten note leaves every note on
  its time column. They catch the interactions between
  features that hand-written cases miss. The main corpus is linted, so an
  edit's own lint shows no difference; unlinted tabs go only where the
  invariant must hold for them too (lint, 4.3). Keys are typed with
  `feedkeys(…, 'xt')` under `silent!` (one undo step per key sequence, and
  no hit-enter prompt reading stdin). A case that breaks an invariant
  because of a bug in the spec's [[Bugs]] is listed as a known exception,
  which must keep failing: fixing the bug means removing it from the list.
  Positions are limited to note starts and the dash after each note, and
  the corpus kept small. The corpus and helpers are in
  `test/invariants/setup.vader`, which each invariant file includes; the
  edit invariant is one body (`test/invariants/edits.vader`) included by
  files that each check a share of the keys, so that they run in parallel.
