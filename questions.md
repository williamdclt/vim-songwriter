# Open questions

Behaviours that made the implementation harder than it should be, found
while refactoring. Complex code is often the sign of an irregular behaviour
(refactors.md), so each entry is a question for the user: is this the right
behaviour, or would a more regular rule be better? Each says what is awkward
now, where it shows in the code, and the alternatives. When one is decided,
delete its entry: a change goes to the spec (and refactors.md if it needs
one), a "keep it" to design.md, with the reason.

Roughly ordered by how much a change would simplify.

## 1. Abandoned slots remove themselves with `:undo`

**Now.** Spec [Tablature][[Editing]] 4.3: an abandoned slot leaves no trace
and no undo step. The slot is written to the buffer, then removed with
`silent undo` (`slots#Abandon`, `s:revert`), falling back to writing the
saved tab back when undo steps were merged (macros, `:normal`); a slot closed
by a motion keeps the lint of 4.2 as an undo step of its own (4.3.3,
`slots#Linted`). It is the most fragile code of the plugin, and [[Bugs]] 5
(E790, `undojoin` after undo) comes from it.

**Alternative.** Never write a slot: show it as virtual text (text
properties in Vim, extmarks in Neovim) with the cursor on its anchor, and
insert the dashes only when a digit is typed. `slots#Mark`, `s:revert`,
`slots#Linted` and `slots#InBar` would go. Costs: a dependency on text
properties or extmarks, and a cursor standing on a column that does not
exist yet.

## 2. Tabs that are not linted have no time columns

**Now.** Columns stand for time only once the pipes are aligned, but every
edit maps columns as if they did. Lint's column map follows the top
string's pipes, wrong for the other strings of a misaligned tab; check mode
can only check each string's notes in order there (`check.vim`
`s:music_kept`); the fuzzer classifies any check failure on a tab that
started unlinted as known. [[Bugs]] 6 (an edit acting beside the note under
the cursor) is the same problem.

**Alternative.** The first tablature-mode edit on an unlinted tab only lints
it, as an undo step of its own, and the key is pressed again. Edits then
only ever see linted tabs. Loses doing it in one keystroke on a messy tab.

## 3. Separators belong to notes in several ways

**Now.** A separator belongs to the note after it (`/5`), to the note before
it (`7~`), or to neither when it joins two notes (`h` of `5h7`). Slots
(3.1.3), `x` (6.7.4), carries (3.6.1), lint (1.5), `columns#WriteNote` and
check mode each apply these rules. Two consequences:

- **A narrower fret moves another note off its time column.** `10h7` ->
  `9h7-` (11.2): the 7 moves one column left, the one exception to "every
  note keeps its time column", which check mode needs declared specially
  (`WriteNote`'s moved notes). Alternatives: `9-h7` (the `h` then belongs
  to the 7, as 3.1.3 says of a separator after a dash) or `9h-7` (the
  hammer-on unhooked).
- **`>>` inside a chain unhooks a hammer-on.** `>>` on the 7 of `5h7` gives
  `5h-7` (6.13). Splitting a chain is deliberate elsewhere (`a` on the 5
  opens `5--h7`, 3.1.3), so check mode cannot treat it as a broken rule.
  Should `>>`/`<<` inside a chain be refused, or move the whole chain?

## 4. `gp` can add time

**Now.** Spec 6.14 says `gp` writes a column register "without adding
time". To stop it joining a note to the one before it (`12` and `4` giving
`124`), it writes each note as a carry does (`columns#PutNote`), which
inserts a dash on every string when a note would touch the one before it:
time is added.

**Alternative.** Refuse instead (`gp would join a note on string e`),
keeping the promise of 6.14. The dash was chosen to match carries and
chords.

## 5. `x` with a count lints between erasures

**Now.** `3x` erases a note, lints, then erases the next one
(`actions.vim` `s:erase`), while `d3l` erases them all and lints once
(`columns#EraseSet`). The lint in between made it the hardest edit to
declare for check mode: each erased note is found back in the tab as it was
by search (`colmap#Before`). It also showed that what `x` writes to the
register for each note depended on the order of the erasures, until
`EraseSet` read each note's row from the tab as it was.

**Alternative.** `3x` is `d3l`: one rule, one function, and `colmap#Before`
goes.

## 6. Operators lint in a command of their own

**Now.** Operators work on a linted tab (decided: a motion must never reach
differently because the tab was not linted). The lint is a separate `<Cmd>`
before `g@` (`operator#Start`, `Prelint`), whose undo step the operation
joins through the changedtick, and which consumes the count, typed again
after `g@` (`g@3w`).

**Alternative.** Lint at other moments so that a tab being worked on is
almost always linted already (leaving the insert state, entering tablature
mode on a tab), and the operator's lint becomes a rare no-op. The rule that
operators see a linted tab stays.

## 7. Smaller oddities

- **`cap` on several tabs is several edits.** An edit touches one block, so
  each tab is cleared in an edit of its own, joined into one undo step by
  hand (`operator#ApplyLines`). Could an edit cover several blocks?
- **Two units for the cursor column.** On an annotation line it is a display
  column, on a string a byte column, told apart by the sign of `lin` in
  `edit#Do`. Unifying them was judged not to simplify (refactor 6).
- **Lifetimes used loosely.** The `typing` state was read with two lifetimes,
  which hid an undo bug (fixed). The table of lifetimes in `state.vim` now
  makes each read say which one it means; worth watching whether other
  "straight after" behaviours really mean "until the buffer changes".
