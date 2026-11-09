# Design

Lasting design decisions and their rationale, by topic. Keep this file in sync
with the code: edit the relevant section in place (see AGENTS.md).

## Constraint: plain text first

A `.song.txt` must stay readable by someone with a plain text editor who has
never heard of this plugin (README). The plugin only highlights and edits; it
never relies on concealing or rendering.

## Architecture

### Modules

| File | Role |
|---|---|
| `autoload/songwriter/grammar.vim` | The format's patterns (tab line, note, chord root/token, chord highlighting). The only place regexes for the format are written. |
| `autoload/songwriter/tab/model.vim` | Tab block model: parse, queries, the column-insertion primitive, and `Read`/`Write` (the buffer edges). |
| `autoload/songwriter/tab/lint.vim` | The linter, as a pure function over a block's lines. |
| `autoload/songwriter/tab.vim` | Tab operations and motions: buffer entry points plus pure helpers (`AppendSlot`, `PrependSlot`). |
| `autoload/songwriter/chord.vim` | Chord model and chord editing. |
| `autoload/songwriter/keys.vim` | Context-dependent keys: tables and `Dispatch()`, tablature-mode flag, tab-line `w`/`b`/`L`/`H`. |
| `plugin/songwriter.vim` | `:Songwriter*` commands and `<Plug>(songwriter-*)` maps. |
| `ftplugin/songwriter.vim` | Buffer options and key bindings, with a complete `b:undo_ftplugin`. |
| `syntax/songwriter.vim` | Highlighting, with patterns taken from the grammar. |

There are no global functions: everything public is `songwriter#…` and
autoloads on first use.

### Data flow

An operation is a thin buffer entry point around pure logic:

1. `songwriter#tab#model#Read()` parses the block around the cursor (or returns
   `{}` off a tab line, which every entry point treats as a no-op);
2. a pure function computes the result: new lines and/or a cursor column
   (`{'lines': [...], 'col': n}`, `{}` for "nothing to do");
3. the entry point writes it back (`model#Write`, `cursor()`).

Pure functions are testable without buffer setup and composable: spec item 4
(lint after an edit) is "edit, then lint, then follow the moved note", which is
why `lint#Lint` reports where every note moved.

### Keys

Keys whose meaning depends on context are declared in tables in `keys.vim` and
mapped as `<expr>` maps calling `songwriter#keys#Dispatch(key)`, which picks, in
order: the tablature-mode action (mode on and cursor on a tab line), the
tab-line action, or the key's default. Actions run through `<Cmd>…<CR>` (Vim
8.2.1978+ / Neovim 0.5+): no mode change, no command-line echo, and valid as an
operator-pending motion. Plain keys (`||`, `_`, `<C-A>`, `<leader>m`…) map to
`<Plug>(songwriter-*)` so users can rebind them.

Visual-mode `L`/`H` still use a `:call …<CR>` map, which leaves visual mode (a
known defect, kept as-is until it is fixed deliberately).

`||` is not a double bar line (the format has none); it is the key that lints
the block.

## Format grammar

- **Tab line**: a string name immediately followed by a pipe, `^\a[|]`. Tab
  features are scoped to such lines explicitly; anything else is prose.
  Highlighting uses the broader `^\s*[A-Ga-g]|` (both live in the grammar; they
  are not unified because that would change behaviour).
- **Tab block**: the contiguous run of tab lines around a line.
- **Note**: a run of digits; a two-digit fret such as `12` is one note spanning
  two columns. Other symbols (`h`, `p`, `/`, `x`…) are not notes (see the lint
  bug in the spec).
- **Bar**: the region between two pipes. On a line, the bar around column `c` is
  bounded by the nearest pipes strictly left and right of `c`
  (`model#BarAt`).

## Tablature

### Block model

`model#Parse(start, lines)` gives `{start, lines, strings}` with each string's
notes (`{col, len, text}`) and pipe columns. Columns are 1-indexed byte columns,
as `col()` returns (tab lines are ASCII). Queries: `NoteColumns` (block-wide,
sorted, unique), `BarAt`, `InBar`. The single mutation primitive is
`InsertColumns(lines, offset, n, char)`: pad every line with dashes up to
`offset`, then insert `n` copies of `char` after it, on every string, so pipes
and notes stay vertically aligned.

### Column insertion (`_`, `:SongwriterAddBar`)

`_` (spec [Tablature][[Editing]] 2) inserts a dash, `:SongwriterAddBar` a pipe,
after the cursor column (at column `col+1`) on every string of the block.
`:SongwriterAddDashes` appends `--` to every string.

### Linter (`||`, spec [Tablature][[Editing]] 1)

The linter works on the block around the cursor, bar by bar. It is a re-flow,
not a full formatter.

**Note order is sacred.** Relative note order on each string defines when notes
are played: `e|---5--4--|` is a sequence, and collapsing the two notes onto one
column would change the music. So the invariant is: never move a note onto the
same column as another note of the same string. A bar keeps its width
`max_col - min_col + 5` (two leading dashes, the note span, two trailing
dashes).

**Two leading / two trailing dashes are per bar, not per string.** The bar's
leftmost note (on any string) sits two dashes after the shared left pipe; other
strings, whose first note comes later, keep their extra leading dashes, which
preserves the order across strings. Likewise the rightmost note sits two dashes
before the right pipe, and shorter strings are padded so the pipes line up.

**Empty bar** (no note on any string) becomes `|--|`.

**Overlapping two-digit notes** (spec 1.3). Each note gets a natural output
offset `c0 - mincol + 2`, then a fixed-point pass enforces:

- *same-string order*: a note keeps its original gap to the previous note on
  its string;
- *cross-string de-overlap*: a note starting strictly after a note on another
  string but inside that note's span is pushed right to leave exactly one dash
  after it. Notes starting on the same column are aligned and never split; a
  single digit lining up with the first digit of a `12` is left alone.

The pass is capped at 200 iterations (never reached in practice): pushing one
note can collide with another on a neighbouring string.

**Output**: `lint#Lint(lines)` returns `{lines, moves}`; `moves` lists every
note's line and its column before and after, so callers can keep the cursor on
the same note. Only the string name's first character is kept, and anything
after the final pipe is dropped.

### Tablature mode (`<leader>t`, spec [Tablature][[Editing]] 3)

A buffer-local flag, `b:songwriter_tabmode`, off by default; no teardown needed.

- **`w`/`b` (3.2)**: next/previous note start on the current line, skipping
  dashes and pipes; a two-digit fret is landed on at its first digit.
- **`l`/`h` (3.3)**: next/previous column where any string of the block has a
  note. A pipe is not an obstacle: the move may land in a neighbouring bar.
  - *3.3.2, the one special case*: on the last note column of the cursor's
    bar, `l` does not skip ahead; it opens a slot as `a` does, so a note can be
    appended to that bar. Pressing `l` again (now on the slot, not on a note)
    moves on to the next note, possibly in the next bar. `l` with no note further
    right also opens a slot. This is the balance sought: easy to append within a
    bar, easy to keep moving.
  - `h` never opens a slot (no mirror of 3.3.2) and is a no-op before the first
    note.
  - Moving does not lint, except to abandon an open slot (4.3, below).
- **`a`/`i` (3.1)**: open a slot for a new note on every string and land on it.
  `a` anchors on the rightmost note end, on any string, among the notes of the
  cursor's bar that start at or before the cursor: the note column under (or
  left of) the cursor, found even when the cursor line is an empty string. It
  inserts as many dashes as needed for the slot to sit exactly one dash after
  the anchor while the next note, on any string, keeps a 1-dash gap (the next
  pipe, 2 dashes): `e|--3--5--|` with the cursor on 3 -> `e|--3---5--|`. `i`
  mirrors this to the left of the leftmost note of the bar ending at or after
  the cursor, keeping the previous note 1 dash and the previous pipe 2 dashes
  away. Gaps are checked on every string, since a note on another string
  occupies the column just as much.
  No anchor note: no-op. `a`/`i` lint first (4.2, below).
- **Digits (3.4)**: a digit on a dash replaces it; on a digit it is appended to
  its right, so a two-digit fret is typed one key at a time; the block is then
  linted (4.1, below), which fixes the spacing. Off tablature mode or a tab
  line, digits keep their count meaning.

### Linting after edits (spec [Tablature][[Editing]] 4)

Tablature-mode edits lint the block:

- **4.1**: a digit enters the note, then the block is linted.
- **4.2**: `a`/`i` lint, then open the slot. `l` opening a slot (3.3.2) is the
  same operation as `a` (`MoveColumn` calls `AddNote(1)`), so it lints too.
- **4.3**: an opened slot is remembered in `b:songwriter_slot` as
  `{line, tick}`. The next `h`/`l`/`w`/`b`/`a`/`i`/`<Esc>` lints the slot's
  block before doing its own job (`LintAbandonedSlot`). A digit fills the slot
  and clears it. `j`/`k` are not mapped, so the slot survives them and a later
  abandon still lints. The slot counts only while `b:changedtick` is unchanged:
  any other buffer change (undo, `x`…) drops it, since the block it pointed to
  may no longer be there.

**The cursor follows the music** (`lint#FollowColumn`): on a note it stays on
the same digit of that note; elsewhere in a bar it keeps its distance from the
nearest note starting at or before it (any string), clamped before the next
note and inside the bar. Notes before/after the cursor stay before/after it, so
`a`/`i` find the same anchor after the lint as before. `||` lints without
moving the cursor.

`<Esc>` is a context key like the others. Outside tablature mode `Dispatch`
returns the key itself. Special keys are written in `<>` notation in the
tables, and the ftplugin passes them to `Dispatch` as `<lt>Esc>`, since
`<Esc>` would otherwise be translated in the map's right side.

### Outside tablature mode

On a tab line, `w`/`b` stop on notes, string names and pipes but never on dashes
(spec [Tablature][[Motions]] 1-2), and `L`/`H` jump to the next/previous pipe
(3-4) using `search()`, which ignores `iskeyword`. Off a tab line every key keeps
its default behaviour.

## Chords

The chord model in `chord.vim`:

- `s:chord_parse(name)` -> `{name, root, quality}`; `root` keeps its spelling,
  `quality` is everything after it;
- `s:chord_build(root, quality)`;
- `s:chord_transpose(parsed, semitones)`: flats are normalised to sharps, the
  single spelling in the chromatic scale;
- `s:splice_chord(line, bounds, new)`.

A chord action is: find the chord under the cursor, parse, transform root or
quality, build, splice back. The public actions differ only in the transform.
The chord found under the cursor is any token of chord characters around a root
letter, which is permissive (see the chord-detection bug in the spec).
Highlighting accepts false positives such as the word "A" (spec [Chords]
[[Rendering]]).

## Testing

- Vader, `make test`; the pre-commit hook enforces a green suite.
- Buffer transformations use `Given songwriter` / `Execute` or `Do` / `Expect`,
  so the before/after tab is visible; cursor positions and pure functions use
  `Assert*`.
- Vader reuses one buffer across cases and files, so buffer state (the
  tablature-mode flag) is reset in a `Before:` block wherever keys are typed.
- Key mappings are exercised end-to-end with `normal` where the result is
  observable; `Dispatch` and `b:undo_ftplugin` have their own tests.
