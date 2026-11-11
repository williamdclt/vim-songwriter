# Refactors

Planned architecture changes, in the order they are meant to be done. Each
entry says what is wrong now, what to change, and what it buys. Unlike
design.md, this file describes work not done yet: when a refactor lands,
delete its entry here and record the resulting design in design.md. Refactors
must not change behaviour (AGENTS.md); where one would, it says so, and the
change is checked with the user first.

The safety net for all of them is `test/songwriter_invariants.vader`, on top of
the per-feature tests: run `make test` after every step.

## 1. Groundwork for the open spec items

- **6.2.4 (`dj`/`dk`)**: generalise `columns#EraseNotes` from "the notes of one
  line in a range" to a set of `(lin, col)` notes. `x`, `dl`, `dw`, `dan` and
  `dj` all become "pick the notes, erase each as `x` does", and 6.2.4 is mostly
  picking the notes.
- **[[Rendering]] 4 (highlight the time column)**: needs a `CursorMoved`
  hook that reads the block on every move. Cache `model#Read` per
  `b:changedtick` and line range (as `tab/state.vim` does for state) so that
  it stays cheap.
