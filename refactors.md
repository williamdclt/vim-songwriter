# Refactors

Planned architecture changes, in the order they are meant to be done. Each
entry says what is wrong now, what to change, and what it buys. Unlike
design.md, this file describes work not done yet: when a refactor lands,
delete its entry here and record the resulting design in design.md. Refactors
must not change behaviour (AGENTS.md); where one would, it says so, and the
change is checked with the user first.

The safety net for all of them is `test/songwriter_invariants.vader`, on top of
the per-feature tests: run `make test` after every step.

## 1. One pipeline for an edit

**Now.** Spec [Tablature][[Editing]] 4 sets the rules of an edit: whether it
closes an open slot (and whether it keeps the lint, 4.3.3), whether it lints
first, whether it joins the previous undo step, whether it keeps the insert
state, whether `.` records it. Nothing enforces them; about fifteen entry points
write them out by hand:

- `silent! undojoin` is called in six places, each under its own condition
  (`tab#EnterNote` twice, `tab#EnterSeparator`, `carry#Move`,
  `operator#Opfunc`, `voicings` `s:put`).
- `insert#Keep()` and `slots#Forget()` are called by hand after edits.
  Forgetting `Keep` silently ends the insert state, since it is tied to
  `b:changedtick`.
- `slots#Abandon()` or `Abandon(1)` is picked case by case in eight places.
- `tab#EnterNote` is a 50-line function with four branches and a recursive
  call.

The pure functions are only half pure: `edit#Commit` writes the buffer and then
lints it, so a prelint, the operation and the post-lint are three `setline`s,
which is why undo has to be stitched back together. Supposedly pure code reads
the cursor (`slots#Mark` and `slots#Linted` read `col('.')`; the
`operator#Erase` loop reads `getline('.')`/`col('.')` again after each
`Commit`). `edit#LintAndFollow` writes even when lint changes nothing, which
leaves an undo step (spec [[Bugs]] 4).

**Change.**

- Pure steps take and return one value, `{lines, lin, col}` plus the tick-bound
  state they need. Lint-and-follow becomes a pure step on it
  (`lint#Lint` + `lint#FollowColumn`), so prelint, operation and post-lint are
  composed before a single write, and nothing is written when the lines are
  unchanged.
- One runner, e.g. `edit#Do(Fn, opts)`, takes the spec 4 choices as data:
  `{'slot': 'abandon' | 'keep-lint' | 'fill', 'prelint': 1, 'join':
  'continuing', 'repeat': fmt}`. The result may carry the state to record next
  (`typing`, `slot`, `carry`, `voicing`). The runner alone decides undo
  joining, re-stamps the insert state, and records state and `.`.
- `EnterNote` becomes a pure function of (ctx, typing state, digit) returning a
  result, plus a thin entry point.

**Buys.** Removes the class of bugs where one entry point forgets one rule;
whole edits become testable without a buffer; fewer writes and simpler undo.
Fixing [[Bugs]] 4 (a no-op `a`/`i` writing) falls out of "write nothing when
unchanged", but it is a behaviour change: do it as its own step, with the user's
go-ahead.

## 2. One parsed tab, queried

**Now.** AGENTS.md says to parse a block once and query the model, but
`tab/columns.vim` takes raw `lines` and calls `model#Notes` again in nested
loops (`Snap` twice, `EraseNote`, `ShiftColumn`, `s:column_end`). Helpers
exist twice: `columns#Columns` and `model#NoteColumns`; `operator.vim`'s
`s:on_note` and `model#NoteAt`; `columns.vim`'s `s:pad` and the padding in
`model#InsertColumns`. "The notes of this bar, on any string" is written again
in `slots#Append`, `slots#Prepend`, `columns#ShiftColumn`, `tab.vim`'s
`s:bar_has_notes`, `operator.vim`'s `s:slot_anchor`, `carry#Lift` and
`columns.vim`'s `s:bar_stops`. Writing text into a line at a column is inline
slicing in about eight places, some with `[a : b]` and some with `strpart`.

**Change.** Give the model the queries these share: a bar index per line (each
bar's pipes, time columns and notes), `ColumnEnd`, `GapEnd`, `ColumnFor`,
`IsShared(column, except lin)`; and one `Splice(lines, lin, col, len, text)`
(plus "blank this note") for every in-place write. `columns.vim` and the slot
code take the parsed tab instead of raw lines. Fits inside 1, since its pure
steps take the parsed tab.

**Buys.** Fewer off-by-one errors, one definition of each notion, less
re-scanning (the suite's time is dominated by repeated parsing and lint).

## 3. Slots and carrying on one position model

**Now.** `tab/carry.vim` has a clean pure position model (`col`, `gap`,
`bar`, `newbar`; `Step`, `Render`), and `carry#Step` already encodes the
insert-state stops of `l`/`h` (spec 3.3.3). `tab.vim` does the same traversal
imperatively for `l`/`h`/`L`/`H` in the insert state: `s:insert_column`,
`s:leave_slot`, `s:from_slot`, `s:land`, `tab#AddBarSlot`. A slot is a carry
with no note, and the slot's recorded `before` lines are the carry's base.
[[Bugs]] 2 (carrying back from the end of a tab loses a note) lives in the
carry copy (`Step` from `newbar`, and the lint of the base dropping empty
bars).

**Change.** Make the insert state's cursor a position over a base: `l`/`h`
step the position (`carry#Step`) and render it with no note (`Render` minus the
note), the arrows render it with the carried note. Closing a slot renders the
base. Keep the undo handling of spec 4.3 (no undo step left) as it is.

**Buys.** `l` and `<Right>` agree by construction; one copy of the stop logic
to fix. This is the largest and riskiest step: unifying may expose small
differences between `l`/`h` and the arrows, each of which is a behaviour change
to check with the user. Do it after 1 and 2.

## 4. Module boundaries

**Now.** `tab.vim` (the most-changed file) mixes typing, motions, new tabs and
simple commands. `tab/columns.vim` holds text objects, motion ranges (`Stops`,
`BarStop`, `StringMotion`), register row matching and pasting (`MatchRows`,
`Paste`, `PasteAt`, `Overlay`) and `MakeRoom`. `tab/model.vim` holds motion
concerns (`Stops`, `EmptyBarStops`, `InLastBar`, `Advance`). In `keys.vim`,
the operator-pending and visual tables repeat the same text-object keys.

**Change.** Split `tab.vim` into `tab/typing.vim` (`EnterNote`,
`EnterSeparator`, `JustTyped`), `tab/motion.vim` (word, bar, column motions and
the insert-state stops) and `tab/newtab.vim`; split `columns.vim` into
`tab/objects.vim` (objects, `Snap`), `tab/motions.vim` (pure stops and motion
ranges, with the model's `Stops`/`Advance`), `tab/paste.vim`, and what is left
(delete, extract, erase, shift, `MakeRoom`). Generate the `o` and `x` object
entries in `keys.vim` from one list. Low risk; can be done alongside the
others. Update design.md's module table.

## 5. Groundwork for the open spec items

- **6.2.4 (`dj`/`dk`)**: generalise `columns#EraseNotes` from "the notes of one
  line in a range" to a set of `(lin, col)` notes. `x`, `dl`, `dw`, `dan` and
  `dj` all become "pick the notes, erase each as `x` does", and 6.2.4 is mostly
  picking the notes. Fix [[Bugs]] 1 (erasing a lone column merges or cuts
  notes on other strings) in that erase first, since every caller shares it.
- **[[Rendering]] 4 (highlight the time column)**: needs a `CursorMoved`
  hook that reads the block on every move. Cache `model#Read` per
  `b:changedtick` and line range (as `tab/state.vim` does for state) so that
  it stays cheap.
