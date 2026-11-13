# Refactors

Planned architecture changes, in the order they are meant to be done. Each
entry says what is wrong now, what to change, and what it buys. Unlike
design.md, this file describes work not done yet: when a refactor lands,
delete its entry here and record the resulting design in design.md. Refactors
must not change behaviour (AGENTS.md); where one would, it says so, and the
change is checked with the user first.

The safety net for all of them is `test/songwriter_invariants_*.vader`, on top of
the per-feature tests: run `make test` after every step.

## 1. Column maps: every edit says where the tab went

**Wrong now.** A pure edit returns the new lines and a cursor column, and
nothing else: where the rest of the tab went is lost. Lint alone reports
moves, and only for notes (`lint#Lint`'s `moves`, used by `FollowColumn` for
the cursor). Anything placed by time column outside the strings (annotations,
spec [Tablature][[Annotations]]) cannot follow an edit without guessing from a
diff, and a diff guesses wrong in a repeated riff (`0 0 0 0`, `dd` on the
second column looks like a deletion of the fourth).

**Change.**

- A new pure module, `autoload/songwriter/tab/colmap.vim`. A column map says,
  for each column of a block's lines before an edit, where it is after: a
  column, or 0 when it was deleted. It is a list of steps applied in order, so
  composing is concatenating and the identity is `[]`:
  - `Insert(offset, n)`: n columns inserted after byte offset `offset`;
  - `Delete(s, e)`: columns [s, e] removed (they map to 0);
  - `Resize(s, old, new)`: the `old` columns from `s` become `new` columns,
    each keeping its offset from `s`, clamped to the new width (an empty bar
    filled to five dashes, spec 3.3.4: what is above it is not deleted);
  - `Table(cols, tail)`: a lookup for a re-flow (lint), with `tail` the shift
    of every column past the table.
  `Then(a, b)` composes, `At(map, col)` looks a column up. A column past the
  end of the lines follows the steps like any other, so text after the last
  pipe keeps its distance from it.
- The primitives return a map with their lines, relative to their input:
  `model#InsertColumns` (it returns `{'lines', 'map'}` instead of a bare
  list), `columns#DeleteRange` (a put-back pipe is an insertion),
  `slots#AppendBar` (an insertion at the end), `slots#EmptyBar` (a resize),
  `paste`'s row insertion, and `lint#Lint`. Lint's map is a table built from
  its moves and the top string's pipes with the rule `FollowColumn` applies
  between notes (the distance from the nearest time column at or before,
  clamped before the next one and inside the bar): `FollowColumn` and the map
  share that rule rather than restating it. A trailing empty bar that lint
  drops maps to 0. Per-string splices (`Splice`, `Blank`, a note rewritten by
  `SetNote`, padding a short line) move no time column, so they add no step.
- Every pure function that returns `lines` returns `map` relative to the lines
  it was given, composing the maps of what it calls with `Then`:
  `columns.vim` (`EraseNote`, `EraseSet`, `EraseNotes`, `ShiftColumn`,
  `MakeRoom`, `PutNote`, `SetNote`, `ClearNotes`), `slots.vim` (`Append`,
  `Prepend`), `strings#Move`, `voicings#Place`, `frets#Add`, `paste.vim`
  (`Paste`, `PasteAt`, `Overlay`), `edit#Linted`, the actions in `typing.vim`
  and `operator.vim`, and `carry.vim` (`Lift`: origin to base; `Render`: base
  to the rendered tab, except back at the origin, which is the origin itself).

**Tests.** `colmap` unit tests; a map test for each primitive; and a new
invariant (`test/songwriter_invariants_maps.vader`) over the corpus, calling
the pure edits at every key position: every note the edit did not rewrite is,
after it, at `At(map, its column)` on its string with the same text. A step
forgotten anywhere shifts every later column, so it shows in the corpus's
other bars.

**Buys.** Exact following, by construction, for anything placed on time
columns; the next refactor and the annotations build on it.

## 2. Drafts: one way to write a block

**Wrong now.** A block reaches the buffer by several paths, each with bare
lines: `edit.vim`'s writes, `model#Write` called from `tab.vim`, `frets.vim`
and `operator.vim` (`cap`), and `setline` in `slots.vim` (a slot put back, or
its lint kept, spec 4.3). A slot or a carry that gives the tab back as it was
writes lines it saved, with no link to what is in the buffer now. There is no
single place that could carry anything else of the block along with its
strings.

**Change.**

- A *draft* is what an edit writes: `{'base', 'lines', 'map'}`, the new lines
  and where the columns of `base` went in them. `base` is the block state the
  edit started from: by default the block being written, or a saved one
  (`model#Save(block)`). Giving a saved block back is a draft from that saved
  state with the identity map; a carry renders from its saved base.
- `edit#Write(block, draft)` is the one writer of a block. It composes nothing
  itself: `edit#Do`, `Commit`, `LintAndFollow` and `Apply` build the draft
  (the prelint's map, then the edit's, then the lint's), slots save their mark
  with `model#Save`, and the carry keeps its origin and base saved. A draft
  without a map is an error (thrown), so no path can skip it. `model#Write`
  only writes lines.
- A result (see `edit.vim`) may give `'base'` with its `lines` and `map` when
  its map is not from the block it was given (the carry).

**Tests.** The suite as it is: behaviour does not change. The error on a
missing map makes every write path the suite covers prove it has one.

**Buys.** The block can grow parts other than its strings (annotation lines)
with one place to keep them in step, and exact restores (slots, carry) stay
exact for those parts too.
