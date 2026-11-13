# Refactors

Planned architecture changes, in the order they are meant to be done. Each
entry says what is wrong now, what to change, and what it buys. Unlike
design.md, this file describes work not done yet: when a refactor lands,
delete its entry here and record the resulting design in design.md. Refactors
must not change behaviour (AGENTS.md); where one would, it says so, and the
change is checked with the user first.

The safety net for all of them is `test/songwriter_invariants_*.vader`, on top of
the per-feature tests: run `make test` after every step.

## 1. Drafts: one way to write a block

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
