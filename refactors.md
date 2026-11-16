# Refactors

Planned architecture changes, in the order they are meant to be done. Each
entry says what is wrong now, what to change, and what it buys. Unlike
design.md, this file describes work not done yet: when a refactor lands,
delete its entry here and record the resulting design in design.md. Refactors
must not change behaviour (AGENTS.md); where one would, it says so, and the
change is checked with the user first. Such changes are welcome when they make
the implementation simpler: complex code is often the sign of an illogical or
inconsistent behaviour, so an entry points out where behaviour could be made
more regular, as a question for the user.

The safety net for all of them is `test/songwriter_invariants_*.vader`, on top of
the per-feature tests: run `make test` after every step.

## 2. Annotations parsed once, with explicit anchors, and one layout

**Now.** A block's `above` is raw strings, and `annotations#Words` re-parses
them wherever they are read: `Follow`, `Label`, `Add`, `Room`, `ChordLabel`,
`Over`, `highlight.vim`, `voicings.vim` (`=` on a label), `annotate.vim`.
`model.vim` parses the strings once; annotations do not. Four routines decide
the spacing of a line, each its own way: `s:render` (Follow), `Retype` (a word
replaced), the fit check of `Add`, and `Room`. Display and byte columns are
converted in many places (`Bytes`, `s:byte_at`, `virtcol`).

**Change.** The block model parses its annotation lines once into
`block.annotations`: rows (0 right above the strings) of words, each with an
explicit anchor: a time column for a label, its first and last columns for a
span, a free position for a word in a gap or past the last pipe. One pure
layout turns rows of anchored words back into lines (a line none of whose
words moved kept byte for byte, as now), and replaces the four routines.
Queries (`ChordLabel`, `Over`, the word under a display column) work on the
model. Display columns are converted to bytes only when lines are read and
written.

**Buys.** One place that decides where a word goes, so the routines cannot
disagree; no re-parsing; anchors that are data, which refactors 3 to 5 build
on. No behaviour change.

## 3. A label is never moved off its column: the tab makes room

**Now.** When words would run into each other after an edit, the layout
pushes the later one right (spec [[Annotations]] 4.4). A pushed label is no
longer over its column, and as the text is the only record of the link, it is
lost: [[Bugs]] 4. Chord names written by `=`, `+`, `=<CR>` and
`:SongwriterTabChord` avoid it by widening the tab (`annotations#Room`,
`edit.vim` `s:make_room`), but only them.

**Change.** The layout of refactor 2 never displaces an anchored word: it
returns the room it needs (columns to insert, and where), and the edit
pipeline inserts dashes there, the annotations following. `Room` and
`s:make_room` become this general case. A new annotation line remains only
where widening cannot help (two words anchored on one column of one line, a
span over the column). Words with a free position may still be pushed.

**Behaviour change (to check with the user).** Spec [[Annotations]] 4.4 no
longer pushes labels: `dd` between `Am7` and `G` leaves the tab a column wider
than now, rather than moving `G` into a gap. Fixes [[Bugs]] 4.

**Buys.** The invariant of refactor 1 holds by construction.

## 4. One vocabulary for annotation changes in a draft

**Now.** A draft changes annotations three ways (`put`, `label`, `above`),
each handled in its own place in `edit.vim` (`Derive`, `s:snapshot`,
`s:resolve` mapping their columns through the lint), plus the `s:make_room`
pass that derives the snapshot twice. `actions.vim` `s:erase` follows and
cuts annotations by hand at each step of a counted `x`.

**Change.** A draft carries a list of annotation operations (add words, set a
column's chord label, replace all), applied by one pure function,
`annotations#Apply(rows, map, ops)`, which gives the new rows and the room
they need (refactor 3). `edit.vim` inserts that room and writes; the special
cases go.

**Buys.** A new annotation feature is a new operation, not a new draft field
threaded through `edit.vim`.

## 5. The cursor on an annotation line, inside the edit pipeline

**Now.** `edit#Do`'s cursor is on the strings only. `=` on a label
(`voicings.vim` `s:on_label`) moves the cursor to a string, runs the edit,
then puts it back by converting bytes; `cia` keeps its own state
(`b:songwriter_annotating`, prefix and rest matched on leaving insert mode);
`annotate#Delete` writes the line itself.

**Change.** The cursor of `edit#Do` may be on an annotation row, held as a
word and an offset in it, and follows that word through the edit. `=` on a
label, `dia` and the end of `cia` become ordinary edits (with refactor 4's
operations).

**Buys.** Undo, `.`, state and the cursor work the same on annotation lines
as on strings, with no round trips.

## 6. Later: the same layer for chords over lyrics

**Now.** `[Chord annotations]` (chords above lyrics) has editing features to
come, and `:SongwriterChordAbove` places a chord by hand.

**Change.** Once refactors 2 to 4 are in, the anchored words and their layout
do not depend on tabs: anchor them to character positions of a lyric line to
give chords over lyrics the same following and room-making.

**Buys.** One annotation engine for both formats instead of a second one.
