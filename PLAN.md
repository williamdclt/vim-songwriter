# Goal

Implement spec `[Tablature → Editing] 3`: a buffer-local "tablature mode",
entered with `<leader>t`, in which the standard motions `w b l h` become
tab-aware:
- **3.1** `w` / `b` — advance to the next / previous *note* on the current line,
  skipping dashes and pipes.
- **3.2** `l` / `h` — advance to the next / previous column that *any* line in the
  block has a note in, skipping dashes and pipes.

# Assumptions / decisions (recorded, since the motion semantics are underspecified)

- **What is a "note".** A digit run (`[0-9]+`). A two-digit fret like `12` is one
  note; the cursor lands on its *first* digit (its start column). Reuses the
  atom model of the linter (`s:extract_atoms`).
- **A "note column" for 3.2** is the *start* column (first digit) of a digit run on
  *any* line of the tab block. `l` picks the smallest such column strictly right of
  the cursor; `h` the largest strictly left. Duplicate columns across lines are
  deduped by min/max, which is all we need.
- **Mode state** is a buffer variable `b:songwriter_tabmode` (default off via
  `get(b:, 'songwriter_tabmode', 0)`). `<leader>t` toggles it and echoes the state.
- **Scope / gating.** A motion only acts on a tab block. The ftplugin mapping glue
  gates each motion on "tab mode ON **and** on a tab line", so outside that context
  the keys fall back to the previous behaviour (tab-line + no mode → the existing
  `w`/`b` `search('[0-9a-zA-Z|]')`; everywhere else → default `w`/`b`/`l`/`h`).
  `MoveNote`/`MoveColumn` also no-op off a tab line as a guard.
- **`l`/`h` keep the current line.** 3.2 moves the *column* (the horizontal
  playhead), not the string line: within an aligned block every string shares the
  same width, so moving to a column that has a note on *another* string is
  unambiguous and the reading line is unchanged. This is the one place the spec is
  silent; "move to the column where *any* line has a note" is read as a column move.
- **No wrap / no fallback jump.** If there is no note in the requested direction on
  the line (3.1) or in the block (3.2), the cursor stays put.
- **Mapping glue is untested by design** (as with `||` and `_`); the underlying
  functions `songwriter#tab#MoveNote` / `MoveColumn` are tested, and the tab-mode
  motions are exercised end-to-end via `normal` after setting `b:songwriter_tabmode`,
  matching `test/songwriter_tab_motion.vader`.

# Steps

- [ ] 1. Add `test/songwriter_tab_mode.vader` with failing Vader tests for 3.1
      (`w`/`b` next/prev note on line) and 3.2 (`l`/`h` next/prev column where any
      line has a note) plus edge cases (no-op off a tab line). — check: new tests
      FAIL.
- [ ] 2. Implement `s:digit_run_starts()` (reuse `s:extract_atoms`) and the public
      `songwriter#tab#MoveNote(dir)` / `songwriter#tab#MoveColumn(dir)` in
      `autoload/songwriter/tab.vim`. — check: `make test` (tab_mode green, rest
      green).
- [ ] 3. Wire the ftplugin mappings: `<leader>t` toggle `b:songwriter_tabmode`
      (with state echo), plus `<expr>` `w`/`b`/`l`/`h` that branch on the flag and
      tab-line while preserving the existing `w`/`b` `search` behaviour when off. —
      check: `make test` full suite green (50 → more).
- [ ] 4. Record the decisions in `design.md` (a "Tablature mode" section) and tick
      the `3 / 3.1 / 3.2` boxes in `specification.song.txt`. — check: `make test`
      still green.

# Done when

- `make test` is green with the new tab-mode tests included.
- Decisions above are in `design.md`; spec `3 / 3.1 / 3.2` marked done.
- One commit after a green `make test`.

# Tablature mode 3.1/3.2 — done (2026)

`<leader>t` toggles a buffer-local `b:songwriter_tabmode` (default 0). In that
mode the motions become note-level:

- **3.1** w/b move to the next/prev *note* on the current line — the start column
  of a digit run `[0-9]+`, skipping dashes/pipes; no-op on a prose line
  (`songwriter#tab#MoveNote`, `s:digit_run_starts`).
- **3.2** l/h move to the next/prev *column where any line has a note* (a
  horizontal playhead), computed across the whole block; no-op off a tab block
  (`songwriter#tab#MoveColumn`, `s:note_columns`).

Mappings in `ftplugin/songwriter.vim` are written **inline** (as the L/H maps
already are): the w/b search stays inline with `\|` escaped. A helper-function
`<expr>`-map that returned the `:call …<CR>` string did not execute reliably, so
the maps must do the branching themselves. Off a tab line, w/b/l/h fall back to
their defaults; the toggle is `SongwriterToggleTabMode`. Details in
`design.md -> Tablature mode (spec item 3)`.

## Steps

1. [x] TDD: `test/songwriter_tab_mode.vader` (MoveNote/MoveColumn forward/back,
   two-digit fret, cross-string l, no-op on prose) via the public wrappers. —
   check: new tests fail.
2. [x] `songwriter#tab#MoveNote`, `MoveColumn`, `s:digit_run_starts`,
   `s:note_columns`; thin wrappers `SongwriterMoveNote`/`SongwriterMoveColumn` in
   `plugin/songwriter.vim`. — check: new tests green.
3. [x] `ftplugin/songwriter.vim`: `<leader>t` toggle (`b:songwriter_tabmode`)
   plus inline `<expr>` `w`/`b`/`l`/`h` that branch on the flag + tab-line while
   preserving the existing `search('[0-9a-zA-Z|]')` `w`/`b` behaviour when off.
   — check: full suite green (63/63).
4. [x] Recorded the decisions in `design.md` (a "Tablature mode" section) and
   ticked `3 / 3.1 / 3.2` in `specification.song.txt`. — check: `make test`
   still green (63/63).

# Tablature mode 3.3/3.4 — done (2026)

Same `b:songwriter_tabmode` toggle; two more note-entry operations.

- **3.3** A digit in tab mode enters a fret in the cell under the cursor:
  *replace* a dash (literal spec), or *append* to a digit so a two-digit fret
  (10-19) types one key at a time. `songwriter#tab#EnterNote`; thin wrapper
  `SongwriterEnterNote`. Digit maps bake the fret as a bare number so the
  single-quoted `<expr>` ex-command has no inner quotes. No-op off a tab line.
- **3.4** `a`/`i` (`SongwriterAddNote(±1)`) open three dashes on every string of
  the block (right / left of the cursor) and land on the 2nd new dash, giving the
  next fret room and spacing; no-op off a tab block.

## Steps

1. [x] TDD: `test/songwriter_tab_edit.vader` — EnterNote replace / append /
   prose-no-op, AddNote a/i across two strings + prose-no-op, plus `a` and a digit
   mapping smoke tests. — check: 8 new assertions fail.
2. [x] `songwriter#tab#EnterNote`, `songwriter#tab#AddNote`; thin wrappers
  `SongwriterEnterNote`/`SongwriterAddNote` in `plugin/songwriter.vim`. — check:
   new tests green.
3. [x] `ftplugin/songwriter.vim`: inline `<expr>` digit maps (0-9, bare number) +
   `a`/`i` that branch on tab mode + tab line, falling back to count/append/insert
   otherwise. — check: full suite green (71/71).
4. [x] Recorded the decisions in `design.md` (extended "Tablature mode") and
   ticked `3.3 / 3.4` in `specification.song.txt`. — check: `make test` green
   (71/71).

