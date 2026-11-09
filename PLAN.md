# Goal

Get the 3.3 `l`/`h` motion to its final behaviour after the user's clarifications:

* `l`/`h` move to the next/previous note column **within the current bar** (on any
  string); the bar-scoping stays.
* `l` at the **last note of the bar** appends a new-note slot on every string
  (3.3.2) — it must open slot at the *bar* end, not skip to the next bar's note.
* No linting on the move (spec item 4, lint-on-edit, is out of scope): the linter
  does not run on `l`/`h`; leftover dashes stay until `||` tidies.
* Empty-string bug fixed: when the cursor is on an empty string's last-note column
  (the last note lives on a neighbouring string), `l` still opens a slot on it.

# Decisions

- **Bar-scoped search, end-of-bar append.** `MoveColumn` collects digit-run
  columns in the current bar (`s:in_bar`) across every string and moves to the
  nearest on the asked side. `l` with no in-bar note to its right
   (`s:append_note_right`) appends a slot; `h` with none to the left is a no-op
    (3.3.3, no `i` mirror).
- **No lint on the move.** Removed the `SongwriterLint()` calls; the `||` key
  still tidies on demand, and leftover dashes are acceptable to the user.
   (Spec item 4 "an edit should trigger linting" is genuinely not implemented and
    stays that way.)
- **Empty-string bug.** `s:append_note_right` / `s:prepend_note_left` anchor `N`
   on the **block-wide** last/first note column, not the cursor line's, so an
    empty string is widened just like its neighbours:
     `e|--4--|` / `b|------|` + `l` -> `e|--4----|` / `b|--------|` (col 7).
- **Regression guard the user reported.** `l` at the last note of an *earlier* bar
   (`e|--4--|--2--|`, col 5) appends in bar 1 — `e|--4----|--2--|` — and does **not**
    skip to bar 2's `2`.

# Steps

- [x] 1. Reproduce: `l` at end of bar 1 in a 2-bar block jumped to bar 2 (block-wide
   change had broken 3.3.2); empty-string case was the earlier TDD target.
- [x] 2. TDD: add/fail the "end of an earlier bar appends in that bar" test.
- [x] 3. Rework `MoveColumn` back to bar-scoped (restore `s:in_bar`), drop the
        lint calls, keep the block-wide anchored `s:append_note_right`. — check:
          `make test` green.
- [x] 4. Update `design.md` (bar-scoped, end-of-bar append, no lint, empty-string
        edge), tick spec `3.3.x`; the earlier "block-wide" wording was reverted.
          — check: `make test` still green.

# Done when

- `make test` green incl. the end-of-bar append and empty-string tests.
- `l`/`h` bar-scoped, no on-move lint, empty-string slot opens.
- Design + spec recorded; one commit per green phase.

# Result

All green (78/78). `l` at end of bar 1 of `e|--4--|--2--|` gives `e|--4----|--2--|`
(col 7, no skip to bar 2); the empty-string edge still opens a slot; a plain move
no longer lints.
