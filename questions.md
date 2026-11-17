# Open questions

Behaviours that made the implementation harder than it should be, found
while refactoring. Complex code is often the sign of an irregular behaviour
(refactors.md), so each entry is a question for the user: is this the right
behaviour, or would a more regular rule be better? Each says what is awkward
now, where it shows in the code, and the alternatives. When one is decided,
delete its entry: a change goes to the spec (and refactors.md if it needs
one), a "keep it" to design.md, with the reason.

Ordered by importance: how many bugs a behaviour can cause, and how much it
gets in the way of new features. Each entry says why it stands where it
does.

## 2. `x` with a count lints between erasures

**Why second.** Local to one function, but it is a second rule for something
`d3l` already does, and it needed the most special handling in check mode.

**Now.** `3x` erases a note, lints, then erases the next one
(`actions.vim` `s:erase`), while `d3l` erases them all and lints once
(`columns#EraseSet`). The lint in between made it the hardest edit to
declare for check mode: each erased note is found back in the tab as it was
by search (`colmap#Before`). It also showed that what `x` writes to the
register for each note depended on the order of the erasures, until
`EraseSet` read each note's row from the tab as it was.

**Alternative.** `3x` is `d3l`: one rule, one function, and `colmap#Before`
goes.

## 3. `gp` can add time

**Why third.** A spec decision with no bug risk either way: the code is the
same, only the outcome differs.

**Now.** Spec 6.14 says `gp` writes a column register "without adding
time". To stop it joining a note to the one before it (`12` and `4` giving
`124`), it writes each note as a carry does (`columns#PutNote`), which
inserts a dash on every string when a note would touch the one before it:
time is added.

**Alternative.** Refuse instead (`gp would join a note on string e`),
keeping the promise of 6.14. The dash was chosen to match carries and
chords.

## 4. Smaller oddities

- **Column ranges leave a note's separators behind.** A separator belongs
  to a note and goes where it goes (spec [Tablature]), but `ac`, `dd` and
  the other column ranges are time columns, from the column's first fret to
  the next column: `dac` on the 7 of `5h7--9` gives `5h-9`, the `h` passing
  to the 5. Should a column range start at the separators of its notes
  (refused, or shrunk, where another string has a note under them)?

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
