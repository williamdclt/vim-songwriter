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

