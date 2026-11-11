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
to check with the user.

## 2. Module boundaries

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

## 3. Groundwork for the open spec items

- **6.2.4 (`dj`/`dk`)**: generalise `columns#EraseNotes` from "the notes of one
  line in a range" to a set of `(lin, col)` notes. `x`, `dl`, `dw`, `dan` and
  `dj` all become "pick the notes, erase each as `x` does", and 6.2.4 is mostly
  picking the notes. Fix [[Bugs]] 1 (erasing a lone column merges or cuts
  notes on other strings) in that erase first, since every caller shares it.
- **[[Rendering]] 4 (highlight the time column)**: needs a `CursorMoved`
  hook that reads the block on every move. Cache `model#Read` per
  `b:changedtick` and line range (as `tab/state.vim` does for state) so that
  it stays cheap.
