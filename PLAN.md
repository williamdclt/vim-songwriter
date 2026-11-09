# Goal

Adjust the 3.3 `l`/`h` motion per the user's clarifications: (1) drop the on-move
linting (spec item 4 is out of scope — leftover dashes after a note insert are
fine), (2) make `l`/`h` **block-wide** (not bar-scoped) — `l` moves to the next
note column on any line and **appends a slot only at the last note of the whole
block**, (3) fix the bug where, when the cursor is on the last note's column on an
**empty** string (the last note lives on a neighbouring string), `l` opened no slot.

# Decisions

- **No lint on move.** Remove the `SongwriterLint()` calls from `MoveColumn`.
  Leftover dashes after a note insert are acceptable (spec item 4, out of scope);
  the `||` key still tidies on demand.
- **Block-wide, not bar-scoped.** `l`/`h` consider note columns on **every** line
  of the block and may cross a pipe. `l` appends (behaves as `a`, block-wide) only
  when there is no note column to the right anywhere in the block; `h` is a no-op
    when there is none to the left (3.3.4, no `i` mirror). `s:in_bar` is deleted.
- **Empty-string bug.** `s:append_note_right` / `s:prepend_note_left` anchor on the
  **block's** last/first note column, not the cursor line's. So an empty string at
   the last-note column gets the same widening as its neighbours:
   `e|--4--|` / `b|------|` + `l` -> `e|--4----|` / `b|--------|` (col 7).

# Steps

- [x] 1. Reproduce the bug; capture ground truth for the working / empty-line /
   no-mirror / no-lint / cross-pipe cases (`/tmp/exp3.txt`).
- [x] 2. Add the failing case to `test/songwriter_tab_move.vader` (empty last-note
   string still gets a slot; block-wide l/h), plus block-wide integration tests;
   confirm they fail.
- [x] 3. Rework `MoveColumn` (block-wide, no lint, append at block end) and
   `s:append_note_right` / `s:prepend_note_left` (block-wide note anchor); delete
     `s:in_bar`. — check: `make test` green (77/77).
- [x] 4. Update `design.md` (block-wide motion, no lint-on-move, empty-string edge,
     item-4 out of scope) and tick spec `3.3.x`. — check: `make test` still green.

# Done when

- `make test` green, including the new empty-string append test.
- `l`/`h` are block-wide, no on-move lint, and the empty-string bug is fixed.
- Design + spec recorded; one commit per green phase.

# Result

All steps done and green (77/77). The empty-string bug is fixed and verified by
`/tmp/exp3.txt` (both empty-line variants now open a slot on every string, col 7);
`l` crosses a pipe to a later note; `h`'s no-mirror no-op is verified; a plain `l`
leaves the line unchanged (no lint).
