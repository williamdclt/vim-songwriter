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
