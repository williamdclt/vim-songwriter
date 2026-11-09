## Module layout (autoload)
The implementation lives under `autoload/songwriter/`, split by concern; each
module keeps its own private helpers as `s:` script-locals:
- `songwriter#util` - the shared tab-line concern: `s:TabLinePat`,
  `songwriter#util#IsTablatureLine()`, `songwriter#util#find_tab_block()`, and
  `songwriter#util#insert_char_at_col()`. Used by both `tab` and `chord`.
- `songwriter#tab` - tablature editing: `AddDashes`, `AddDash`, `AddBar`, `Lint`,
  `TabChord`, plus the private linter helpers `s:extract_atoms` /
  `s:parse_tab_lines` / `s:relax_bar` / `s:render_bar` / `s:lint_block`.
- `songwriter#chord` - chord parsing/transpose: the `s:Chromatic` /
  `s:FlatToSharp` / `s:RootPat` constants and `s:chord_parse` / `s:chord_build`
  / `s:chord_transpose` / `s:splice_chord` / `s:find_chord_at_cursor`, plus
  `TransposeChord`, `ChordAbove`, `ChordQuality`, `ToggleMinorMajor`.

`plugin/songwriter.vim` is now thin: a `g:loaded_songwriter_plugin` guard, the
`Songwriter*()` global wrappers (kept so the test-suite and the ftplugin
mappings bind unchanged), and the `:command` definitions. `ftplugin` keeps its
buffer motions and delegates its tab-line test to
`songwriter#util#IsTablatureLine`. Because `rtp` includes the repo, every public
name autoloads on first use.

## Architecture: shared helpers

### Tab-block scanner + single tab-line pattern (`s:find_tab_block` / `s:TabLinePat`)

Every tab operation (add bar, add dash, add dashes, lint, insert chord above)
needs "the contiguous block of tab lines around the cursor." This was
previously copy-pasted into all five functions. It is now one helper,
`s:find_tab_block()`, which returns `[start, end, lines]`, or `[0, 0, []]` when
the cursor is not on a tab line. Callers guard with
`if empty(l:block[2]) | return | endif` and use `l:block[0]` (start line) and
`l:block[2]` (lines).

The "is this a tab line?" predicate — a string name immediately followed by a
bar pipe — is defined **once** as `s:TabLinePat = '^\a[|]'` and is used by
`s:find_tab_block`. The ftplugin gate `SongwriterIsTablatureLine` now uses the
same `^\a[|]` literal (it previously used the narrower `^[eEaAdDgGbB][|]`).
All test inputs (`e|…` and prose) match both, so no motion test changes; this
was a behavioural unification towards the design-documented `^\a[|]`.

### Column-op helper (`s:insert_char_at_col`)

`SongwriterAddDash` (insert `-`) and `SongwriterAddBar` (insert `|`) differed
only in the character inserted; the "insert one char at the cursor column on
every string, padding short lines with dashes first" logic is shared as
`s:insert_char_at_col(char)`, and the two commands are now thin wrappers over
it. Insertion lands *after* the character at the cursor column (i.e. `col+1`,
1-indexed), preserving the original `AddBar`/`AddDash` behaviour. `SongwriterAddDashes`
still appends `--` to the whole line, which is a different operation, so it is
not folded in. This shape also makes spec `[Tablature → Editing] 3` ("press a
number replaces the dash") a small addition of a `replace_dash_at_col` variant
later, when that feature is built.

### Chord model (parse / build / transpose / splice)
`TransposeChord`, `ChordQuality`, `ToggleMinorMajor`, and `TabChord` each needed
the chord at the cursor, its root spelling, its quality, and a way to splice a new
chord token back into a line — copy-pasted across the four, with the chromatic
scale and the flat-to-sharp table declared twice. Centralised into a small model:

- `s:Chromatic`, `s:FlatToSharp`, `s:RootPat` — shared constants; one spelling per
  pitch, sharp-based.
- `s:chord_parse(name)` -> `{name, root, quality}`. `root` keeps its raw spelling
  (a flat stays a flat); `quality` is everything after it; no letter means empty
  root/quality.
- `s:chord_build(root, quality)` -> a chord token.
- `s:chord_transpose(parsed, semitones)` -> new token (flats normalized to
  sharps, the single unambiguous spelling in `s:Chromatic`).
- `s:splice_chord(line, bounds, newc)` -> the string replacement shared by every
  chord-editing feature.

A new chord action is now: find the chord (`s:find_chord_at_cursor`),
`s:chord_parse`, transform root/quality, `s:chord_build`, `s:splice_chord` back.
The four public chord functions differ only in how they transform the parsed chord,
which is the one thing worth keeping small and explicit. Note: the parsed dict in
`s:chord_parse` must stay on one line — a multi-line `{` `}` without `\`
continuations is an error (E723).

## Tablatures

Motions and editing capabilities should be scoped to tablature lines explicitly using `getline('.') =~# '^\a[|]'`, when possible. If not possible, this should be documented in the specifications file.

## Design decisions

### Linter (`SongwriterLint` / `s:lint_block`)

The linter operates on the contiguous block of tab lines surrounding the
**cursor's current line** (found the same way as the bar-alignment helpers),
not the whole buffer, and is a no-op on non-tab lines. It is a bar-aligned
re-flow, not a full auto-formatter.

**Why per-bar, not whole-buffer.** Relative note order on each string is
fundamental: it defines when notes play. Two adjacent notes on the same string
(e.g. `e|---5--4--|`, a 7-5 run) carry a distinct temporal relationship that is
meaningless if the notes are collapsed onto the same column. A formatter that
packed notes into one column would silently alter the score. The invariant,
therefore, is: *never move a note to the same column as another note on the
same string.* Concretely, a bar keeps its width `max_col - min_col + 5` (two
leading + two trailing dashes + the note span) instead of collapsing to width 5.

**Two leading / two trailing are per-BAR, on the bar's global first/last note**
— not per-string. The 2 left dashes attach to the bar's globally leftmost note
(equivalently every string in the bar shares one left pipe and the leftmost note
of the whole bar sits 2 from it); other strings, whose first note arrives later,
simply get more leading dashes, which is exactly what preserves relative
order-across-strings. Likewise the bar's globally rightmost note sits 2 from the
shared right pipe, and shorter strings are padded with trailing dashes so their
pipes line up. This reuses the block-alignment model of `SongwriterAddDashes`
(shared width per bar).

**Empty bar** (no note on *any* string in that bar, e.g. a rest bar) degenerates
to width 2 (`|--|`). `--` vs `----` for a truly empty bar is cosmetic and left
as the minimal `--`.

**Structure (decomposed).** `s:lint_block` is now a thin orchestrator over three
documentable steps, each named after the model stage it implements:
- `s:parse_tab_lines(lines)` -> `[regions, P, NL]`: split each line on pipes into
  bar-region strings (dropping the string-name prefix and anything after the
  final pipe), and find the widest bar count `P`.
- `s:relax_bar(atoms, mincol)` -> a list of note dicts carrying a final output
  column `start`; the fixed-point pass enforcing the two invariants above.
- `s:render_bar(work, NL)` -> one region string per line, each padded so the
  pipes line up (bar width = content span + two trailing dashes).

The per-bar atom collection (gather `atoms`, `mincol`, and whether the bar is
empty) stays in `s:lint_block`, which then calls `relax_bar` + `render_bar` for
each non-empty bar and assembles the lines. This is a like-for-like decomposition
of the previous single function; the 21 lint assertions are the behaviour oracle.

**Pipes vs `||`.** A single `|` is a bar boundary. Typing `||` does not denote a
double bar-line (this format has no double pipes); it is the *trigger* that
lints the current tab block. A buffer-local `||` mapping lives in
`ftplugin/songwriter.vim` and is intentionally untested by design.

**Malformed input.** A line that cannot be split into bar regions (no pipe /
not a tab line) is left alone; the linter only touches well-formed tab lines.

## Tab dash insertion (`_`)

`_` on a tab block inserts one `-` at the cursor column on every string of the
contiguous block (spec [[Editing]] 2), implemented as `SongwriterAddDash` and
mirroring `SongwriterAddBar` block-for-block: it scopes to the block found with
`getline('.') =~# '^\a[|]'`, reads the cursor column, and inserts via
`strpart(line, 0, col) . '-' . strpart(line, col)` — so the new dash lands after
the character at the cursor column (column `col+1`), exactly as `SongwriterAddBar`
places its `|`. Short lines are padded with dashes first. No-op on non-tab lines.

The buffer-local `_` normal-mode mapping lives in `ftplugin/songwriter.vim` and,
like the `||` mapping, is intentionally untested by design; the function is tested.

### Overlapping two-digit notes (`spec 1.3`)

Notes are parsed as *atoms* — maximal runs of digit characters — so a two-digit
fret number like `12` is a single atom spanning two columns, not two notes. A
note is re-flowed to a natural output column of `c0 - mincol + 2` (two dashes
after the bar's left pipe), then a fixed-point relaxation enforces two
invariants per bar:

* **Same-string order** — a string's notes keep their *original relative gap*
  (`prev.start + (c0 - prev.c0)`), so sequential notes are never collapsed onto
  one column. This preserves the re-flow model of 1.1/1.2.
* **Cross-string de-overlap** — when a note starts strictly after a note on a
  *different* string but still inside that note's column span (`other.start <
  start <= other.end`), the two numbers overlap without being aligned; the later
  one is pushed right until exactly one dash separates them
  (`start = other.end + 2`).

`Aligned` two-note numbers (same start column) are an explicit exception and are
never split: the condition `other.start < start` is false for two notes that
begin on the same column, so they stay stacked. The same property means a
single-digit note that merely lines up with the first digit of a neighbouring
`12` is also left alone — only a *second* digit that lands inside another
number's span is ever pushed. Resolution runs to a fixed point (capped at 200
iterations, never exceeded in practice) because pushing one note can in turn
collide with a later one on a neighbouring string.

## Tablature mode (`<leader>t`; spec item 3)

`<leader>t` toggles a buffer-local `b:songwriter_tabmode` (default 0). In that mode
the key motions w/b/l/h become note-level (the actual movement lives in
`s:digit_run_starts`, `songwriter#tab#MoveNote`, `songwriter#tab#MoveColumn`):

- **3.1 w/b — the note on the current line.** A *note* is the start column of a
  digit run `[0-9]+` (the two-digit frets 10-19 read as one run, so we land on
  the left digit). w goes to the next run start to the right of the cursor, b the
  one to the left, in either case ignoring the dashes and pipes between. The
  guard `!SongwriterIsTablatureLine(getline('.'))` no-ops on a prose line.
- **l/h — across notes within the current bar (spec 3.3).** `MoveColumn` collects
   the digit-run start columns within the **current bar** — the notes strictly
   between the pipes that bound the cursor on the current line (`s:in_bar`) — on
   *every* string, and moves to the nearest one on the requested side
   (`SongwriterMoveColumn(+1/-1) = l/h`). The motion is bar-local: it never crosses
   a pipe, so `w`/`b` (current-line notes) and `L`/`H` (next/previous pipe) remain
   how you move across strings and between bars.
   - **3.3.1** l/h land on the nearest in-bar note column on any string.
   - **3.3.2** at the **last note of the bar**, `l` finds no in-bar note to its
     right and so *behaves as `a`* — it appends a new-note slot on every string
     (`s:append_note_right`), not a cross-bar jump. `h` is symmetric: at the first
     note it is a no-op (there is no mirror of the `a` append, 3.3.4).
   - **3.3.3** a plain move (a note was found) then runs `SongwriterLint` on the
     block so the edited bar is aligned.
   - **The lint-vs-append tension.** The linter forces exactly two dashes at a pipe
     (spec 1.2) and would collapse the very slot `a` just opened, so the append
     case (3.3.2) is the *result* and is not linted in the same step; only the
     plain move lints. This keeps "easily append a note" working, as 3.3.2 intends.

- **3.3 digits — enter a note.** A digit 0-9 in tablature mode on a tab line
  goes into the cell under the cursor: on a dash/blank it is a straight
  *replace* (`songwriter#tab#EnterNote`, the literal spec wording); on a digit it
  *appends* to the right so a two-digit fret (10-19) can be typed one key at a
  time (the 1.3 de-overlap linting then fixes the spacing). The digit maps bake
  the fret as a bare *number* (`… ? ':call SongwriterEnterNote(4)<CR>' : '4'`)
  so the ex-command has no inner quotes to fight the single-quoted fallback; the
  wrapper coerces it back to a string with `a:digit . ''`. Off a tab line the
  digit is a no-op (it falls back to its default count behaviour). Because `0`-`9`
  are otherwise count-prefics, the map guard `get(b:,'songwriter_tabmode',0) &&
  SongwriterIsTablatureLine()` keeps them as ordinary counts everywhere else.
- **a/i — open a note slot on every string (spec 3.1, formerly 3.4).** `a`
   `SongwriterAddNote(1)` opens a slot to the **right** of the current note on
    every string (s:append_note_right): it inserts as many dashes as are needed so
    the slot sits **exactly one dash from the current note** *and* the following pipe
    (or next note) keeps its **two-dash** gap. e.g. `e|--4--|` -> `e|--4----|`. The
    old "always three dashes, land on the second on the near side" behaviour is
    obsolete: it ignored the following pipe/next note (the removed "Old requirement").
    `i` (`AddNote(-1)`, s:prepend_note_left) mirrors to the **left**: one dash before
    the current note, two after the preceding pipe. The cursor lands on the new slot
    itself, which is a dash the user then fills with a digit. No-op when there is no
    digit run in the asked direction. `a`/`i` do not auto-lint themselves: the slot
    *is* the new space, and the existing `||` lint key (and, for `l`, 3.3.3) is what
    tidies it afterwards. Note: spec 4.2 ("lint when a note is inserted with a or i,
    before the space is inserted") is not yet wired up and is out of scope for 3.1.

### Why the maps are inline, not function-calling

The motion mappings are written as fully inline `<expr>` maps — `get(b:,
'songwriter_tabmode',0) && SongwriterIsTablatureLine() ?
':call SongwriterMoveNote(1)<CR>' : 'w'` — just like L/H below. They must *not*
call a helper that returns the ex-command string: an `<expr>` map whose RHS is a
function returning a `:call ...<CR>` string did not execute reliably, while the
equivalent inline form in L/H does. As a corollary, the w/b search pattern
`[0-9a-zA-Z|]` stays inline and its `|` is escaped as `\|`, exactly as it was
before this change.

Off a tab line every one of these keys falls back to its default behaviour
(`w`/`b` are still the usual tab-line `search('[0-9a-zA-Z|]', ...)`; `l`/`h`
stay character-wise), so nothing outside tablature mode is disturbed. The toggle
(`SongwriterToggleTabMode`) just flips the flag and echoes the new state; because
`b:` is buffer-local and defaults to 0, no teardown is needed.

## Bar-line jumps (L/H)

L/H jump to the next/previous bar pipe `|` on the current tab line. They use
`search('|', 'W'/'bW')` so the pipe is always found (the `W` flag ignores
`iskeyword`); off a tab line the mapping falls back to the default `L`/`H`.


