# Goal

Get the 3.3 `l`/`h` motion to its final, cross-bar behaviour after the user's
clarification:

- `l`/`h` advance to the next/previous note column, **block-wide** — a pipe is
   not an obstacle, so a plain move may land on a note in a neighbouring bar.
- The ONE special case (3.3.2): when `l` sits on the **last note of the current
   bar**, it does *not* skip that bar — it behaves as `a`, opening a new-note
   slot on every string. Pressing `l` again (now on the slot, not a note) does the
   normal block-wide advance to the next note, which may be in a later bar.
- `h` (3.3.3/3.3.4) advances block-wide and has **no** `i`-style append at a bar
   start; it is a no-op at the tablature's first note.
- No linting on the move (spec item 4 out of scope): `||` tidies on demand.
- Empty-string edge: an empty string at the last-note column still opens a slot.

# The balance the user is after

"Easy to add a note in a bar" (the auto-created blank slot) *vs* "easy to move
on" (from the blank space just go to the next note, even across the bar). The
append is **bar-scoped** (it fires at the last note of the *bar*); the plain move
is **block-wide** (it crosses bars). That is the whole design.

# Decisions

- **Bar-aware append.** `s:append_note_right` now bounds its "last note" to the
  cursor's current bar (new `s:bar_end` helper: the first pipe strictly right of
  the cursor). So appending at the end of a *non-final* bar widens the space after
   *that* bar's last note and keeps its pipe aligned, instead of using the
   block-wide last note. Single-bar 3.1 cases are identical (bar_end-1 >= the
   note, same `e`).
- **MoveColumn model.** `cols` = all note columns block-wide. `last_in_bar` = the
   max note column inside the cursor's current bar (via `s:in_bar`). `l`
   appends when `col == last_in_bar`, otherwise advances block-wide (or appends at
   the very end). `h` advances block-wide, no-op at the first note, no append.
- No lint on the move (item 4 stays out of scope).

# Steps

- [x] 1. TDD: `songwriter_tab_movebar.vader` — l on last note of bar 1 opens the
      slot in bar 1 (no skip to bar 2); a second l from the slot advances to bar
      2; h crosses back. — check: the l-append case is RED before the fix.
- [x] 2. Add `s:bar_end`; make `s:append_note_right` bar-bound (`e` = last note end
          within the current bar); fix a stray `a:col` (the fn's arg is `block`, so
          use `l:col`). — check: movebar l cases pass, 3.1 `a`/`i` still pass.
- [x] 3. Rewrite `MoveColumn` to the cross-bar model (bar-aware append on the last
          note of the bar; block-wide advance otherwise; `h` no-op at first note).
          — check: `make test` green.
- [x] 4. Update `design.md` (cross-bar move + bar-scoped append) and `PLAN.md`;
          spec 3.3 already reads "last note of the bar" and matches.
          — check: `make test` still green.

# Done when

- `make test` green incl. the cross-bar append/advance tests.
- `l` opens a slot at a bar's end and still advances to the next bar's note on the
  next press; `h` is a no-op at the first note.
- Design/spec recorded; one commit per green phase.

# Result

All green (81/81). On `e|--4--|--2--|` / `b|------|------|`, `l` on bar 1's last
note gives `e|--4----|--2--|` / `b|--------|------|` (slot in bar 1, no skip); a
second `l` from that slot advances to bar 2's `2` (col 13). `a`/`i` 3.1 unchanged.
