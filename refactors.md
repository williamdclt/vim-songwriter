# Refactors

Planned architecture changes, in the order they are meant to be done. Each
entry says what is wrong now, what to change, and what it buys. Unlike
design.md, this file describes work not done yet: when a refactor lands,
delete its entry here and record the resulting design in design.md. Refactors
must not change behaviour (AGENTS.md); where one would, it says so, and the
change is checked with the user first.

The safety net for all of them is `test/songwriter_invariants.vader`, on top of
the per-feature tests: run `make test` after every step.

## 1. Slots and carrying on one position model

**Now.** `tab/carry.vim` has a pure position model (`col`, `gap`, `bar`,
`newbar`; `Step`, `Render`), and `carry#Step` encodes the insert-state stops of
`l`/`h` (spec 3.3.3). `tab/motion.vim` does the same traversal imperatively
for `l`/`h`/`L`/`H` in the insert state (`s:insert_column`, `s:leave_slot`,
`s:from_slot`, `s:land`, with `slots#AddNote` and `slots#AddBarSlot`). A slot
is a carry with no note, and the slot's recorded `before` lines are the carry's
base. Compared step by step, the two agree on where they go, including on a
new bar and at bar lines; the one difference is how a gap is opened: `h` on a
note in the insert state opens the slot before that note (`slots#Prepend`, as
`i`), while carrying names a gap after the column before it (`s:canonical`)
and renders it with `slots#Append`, which can put the dashes differently.
[[Bugs]] 2 is in the carry's base, not its steps: going back from a new bar
lands on the last column, as `h` does from the new bar's slot.

**Change.** Make the insert state's cursor a position over a base: `l`/`h`
step the position (`carry#Step`) and render it with no note (`Render` minus the
note), the arrows render it with the carried note. Closing a slot renders the
base. Keep the undo handling of spec 4.3 (no undo step left) as it is.

**Buys.** `l` and `<Right>` agree by construction; one copy of the stop logic
to fix. It changes behaviour where a gap is opened from its right (`h`, or
`<Left>`): which of `Append`/`Prepend` both use must be decided with the user
first.

## 2. Groundwork for the open spec items

- **6.2.4 (`dj`/`dk`)**: generalise `columns#EraseNotes` from "the notes of one
  line in a range" to a set of `(lin, col)` notes. `x`, `dl`, `dw`, `dan` and
  `dj` all become "pick the notes, erase each as `x` does", and 6.2.4 is mostly
  picking the notes. Fix [[Bugs]] 1 (erasing a lone column merges or cuts
  notes on other strings) in that erase first, since every caller shares it.
- **[[Rendering]] 4 (highlight the time column)**: needs a `CursorMoved`
  hook that reads the block on every move. Cache `model#Read` per
  `b:changedtick` and line range (as `tab/state.vim` does for state) so that
  it stays cheap.
