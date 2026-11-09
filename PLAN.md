# Goal

Implement the changed spec `[Tablature → Editing]` items **3.1** (`a`/`i` open a
1-dash-gap slot for a note on every string, cursor one dash from the current
note, 2 dashes kept before/after the pipe) and **3.3** (`l`/`h` move across
notes within the current bar; `l` at the last note of the bar behaves as `a` to
append; `l`/`h` trigger linting; `h` does not mirror). The obsolete "always 3
dashes / land on the second" `a`/`i` behaviour is deleted.

# Decisions (recorded — the motion/append semantics are underspecified)

- **3.1 slot rule.** The new-note slot sits **one dash from the current note** on
  a side, and keeps the **2-dash gap** at the pipe. `a` opens right (`+1`),
  `i` mirrors left (`-1`), across every string. N dashes are inserted as needed
  (not a fixed 3). A string with no digit run in the asked direction is a no-op.
- **"current note".** For `a` (right): the last digit run starting at/left of the
  cursor. For `i` (left): the first digit run starting at/right of the cursor.
- **3.3 bar-scoped.** `l`/`h` consider only notes inside the **current bar**
  (between the pipes bounding the cursor on the current line). 3.3.2 literally says
  "last note of the bar", so the motion is bar-local. `w` still moves note-to-note
  within the current *line* (across pipes); `L`/`H` jump bars.
- **3.3.3 linting vs 3.3.2 append — the one real tension.** The linter forces
  exactly 2 dashes adjacent to a pipe (1.2), so a naive "lint after append"
  destroys the just-opened slot. Resolution: the plain `l`/`h` *move* (a note is
  found in the bar) triggers `SongwriterLint` after the move; the end-of-bar case
  (`l` finds no note to its right in the bar) *is* the append ("behave as `a`"),
  and its opened slot is the result, so it is **not** linted away. `h` at the
  first note of the bar is a no-op (no left-append mirror, 3.3.4).
- **`i` linting.** Out of scope (item 4 unchanged); the standalone `a`/`i` keys do
  not lint themselves — only `l`/`h` moves do, per 3.3.3.

# Steps

- [x] 1. 3.1: rewrite `AddNote` and add `s:current_note_end` / `s:current_note_start`
       / `s:append_note_right` / `s:prepend_note_left` in `autoload/songwriter/tab.vim`;
       update the obsolete `a`/`i` assertions in `test/songwriter_tab_edit.vader`.
       — check: `make test` green (71/71).
- [x] 2. 3.3: rework `songwriter#tab#MoveColumn` to be in-bar, append on `l`
       end-of-bar, lint on plain moves, and add `test/songwriter_tab_move.vader`.
       — check: `make test` green.
- [x] 3. Record the decisions in `design.md`; tick `3.1`/`3.3` boxes and remove the
       obsolete "Old requirement" lines in `specification.song.txt`.
       — check: `make test` still green.

# Done when

- `make test` green with the new a/i/l/h tests.
- Decisions in `design.md`, spec `3.1`/`3.3` ticked, obsolete lines removed.
- One commit per green phase.
