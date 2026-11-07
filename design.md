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

