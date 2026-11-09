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
| `autoload/songwriter/grammar.vim` | The format's patterns (tab line, note, note group, chord, highlighting). The only place regexes for the format are written. |
| `autoload/songwriter/tab/model.vim` | Tab block model: parse, queries, the column-insertion primitive, and `Read`/`Write` (the buffer edges). |
| `autoload/songwriter/tab/edit.vim` | The buffer side of a tablature edit: `Commit` a pure function's result (write, cursor, lint and follow, message or refusal), `Run` a whole edit at the cursor. |
| `autoload/songwriter/tab/slots.vim` | Slots: where a new note's room goes (pure) and the buffer's one open slot. |
| `autoload/songwriter/tab/state.vim` | Buffer state valid only while `b:changedtick` is unchanged (slot, digit being typed, `.`). |
| `autoload/songwriter/tab/lint.vim` | The linter, as a pure function over a block's lines. |
| `autoload/songwriter/tab.vim` | Tab operations and motions: buffer entry points around the model. |
| `autoload/songwriter/tab/columns.vim` | The column model behind tablature-mode operators, pure: text object ranges, snapping, delete, extract, paste with row matching, erase. |
| `autoload/songwriter/tab/operator.vim` | Tablature-mode operators, text objects, `x`/`p`/`P`, `>>`/`<<`, `gp`: buffer entry points around `columns.vim`. |
| `autoload/songwriter/tab/visual.vim` | Tablature-mode visual mode: selections, motions, operators on a selection. |
| `autoload/songwriter/tab/register.vim` | Blockwise tab registers and the string names of their source tab. |
| `autoload/songwriter/tab/repeat.vim` | `.` for actions that are not operators. |
| `autoload/songwriter/tab/strings.vim` | Moving notes and time columns to another string, keeping the fret or the pitch: pure `Move()` and its entry point. |
| `autoload/songwriter/chord.vim` | Chord model and chord editing. |
| `autoload/songwriter/pitch.vim` | Pitch classes: note names to semitones and back (sharp spelling). Shared by chords and tab string intervals. |
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
3. the entry point writes it back (`edit#Commit` lints and follows too;
   `edit#Apply` only writes and moves the cursor). `edit#Run` is the whole
   sequence for an edit at the cursor.

Pure functions are testable without buffer setup and composable: spec item 4
(lint after an edit) is "edit, then lint, then follow the moved note", which is
why `lint#Lint` reports where every note moved.

### Keys

Keys whose meaning depends on context are declared in tables in `keys.vim`, one
set per mode (normal, operator-pending, visual), and mapped as `<expr>` maps
calling `songwriter#keys#Dispatch(key, mode)`, which picks, in order: the
tablature-mode action (mode on and cursor on a tab line), the tab-line action,
or the key's default. Actions run through `<Cmd>…<CR>` (Vim 8.2.1978+ / Neovim
0.5+): no mode change (visual `L`/`H` stay in visual mode), no command-line
echo, and valid as an operator-pending motion or text object. An action written
`=expr` returns keys instead; operators use it to return `g@`. Plain keys
(`||`, `_`, `<C-A>`, `<leader>m`…) map to `<Plug>(songwriter-*)` so users can
rebind them.

`||` is not a double bar line (the format has none); it is the key that lints
the block.

## Format grammar

- **Tab line**: a string name immediately followed by a pipe, `^\a[|]`. Tab
  features are scoped to such lines explicitly; anything else is prose.
  Highlighting uses the broader `^\s*[A-Ga-g]|` (both live in the grammar; they
  are not unified because that would change behaviour).
- **Tab block**: the contiguous run of tab lines around a line.
- **Note**: a run of digits; a two-digit fret such as `12` is one note spanning
  two columns. Motions, `a`/`i` and digit entry work on notes.
- **Note group** (`TabAtom`): any run of characters that are not dashes, pipes
  or whitespace: a note with its playing techniques (`5h7`, `3/5`, `12b14`) or a
  stand-alone mark (`x`). The linter works on note groups so that it never
  loses a technique; it keeps each group verbatim.
- **Bar**: the region between two pipes. On a line, the bar around column `c` is
  bounded by the nearest pipes strictly left and right of `c`
  (`model#BarAt`).

## Tablature

### Block model

`model#Parse(start, lines)` gives `{start, end, lines, strings}` with each string's
notes (`{col, len, text}`) and pipe columns. Columns are 1-indexed byte columns,
as `col()` returns (tab lines are ASCII). Queries: `NoteColumns` (block-wide,
sorted, unique), `BarAt`, `InBar`, `Advance` (through a list of stops); and
`Cursor`, the cursor as `{block, lin, col, line}`. Pure functions address the
cursor as `lin` (0-indexed in the block) and `col`. The width of a line's
prefix is known only to `Name`, `Names` and `BodyOffset`. The single mutation primitive is
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

**An unclosed last bar is closed first.** A line with anything but whitespace
after its final pipe (`e|--3--5--`) gets a pipe appended before parsing, so its
last bar is linted rather than discarded. Appending at the end keeps every
earlier column, so note moves and the cursor-following (FollowColumn) still
refer to the caller's original columns.

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

**Note groups, not just digits.** The linter places note groups (see Format
grammar), so `5h7` or `x` moves as a unit and comes out unchanged. Everything
else in a bar (dashes, whitespace) is re-rendered as dashes.

**Empty bar** (no note on any string) becomes `|--|`.

**Empty bars at the end are deleted** (spec 1.4): a trailing empty bar is
leftover space, not music. All of them go, not just the very last one, so that
lint stays idempotent (linting twice changes nothing); empty bars between
notes are rests and are kept. A tab keeps at least one bar, so an all-empty tab
lints to `|--|`. This applies to every lint, so an abandoned new-bar slot (spec
5) disappears, and `cap` leaves a single bar. A cursor that was in a deleted
bar lands on the tab's last pipe.

**Overlapping notes** (spec 1.3, two-digit notes or longer note groups). Each note gets a natural output
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
note's line, bar, width and column before and after, so callers can keep the cursor on
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
    moves on to the next note, possibly in the next bar. This is the balance
    sought: easy to append within a bar, easy to keep moving.
  - *End of the tab (5)*: `l` with no note further right, in the last bar of a
    tab whose lines end with a pipe (cursor anywhere after the last note, or on
    the closing pipe), appends a new bar `-----|` to every string and lands on
    its middle dash, a slot like any other: a digit gives `|--7--|`. It lints
    first (4.2) and is remembered as a slot (4.3), so abandoning it leaves an
    empty bar `|--|`. So from the last note, `l` opens a slot in the bar (3.3.2)
    and a second `l` starts the next bar. Elsewhere, `l` with no note further
    right opens a slot as `a` does; a line with no closing pipe has no bar to
    close, so it never gets a new bar.
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
- **Digits (3.4)**: a digit on a dash replaces it; on a note it replaces the
  whole note (both digits of a `12`). To type a two-digit fret, a digit typed
  straight after another is appended to it instead (3.4.1): `EnterNote` records
  `b:songwriter_typing = {line, col, tick}` after each digit, and the next
  digit appends only when the cursor and `b:changedtick` still match. Any move
  or edit ends the run, so coming back to a note replaces it. The block is then
  linted (4.1, below), which fixes the spacing. Off tablature mode or a tab
  line, digits keep their count meaning.

### Linting after edits (spec [Tablature][[Editing]] 4)

Tablature-mode edits lint the block:

- **4.1**: a digit enters the note, then the block is linted.
- **4.2**: `a`/`i` lint, then open the slot. `l` opening a slot (3.3.2) is the
  same operation as `a` (`MoveColumn` calls `AddNote(1)`), so it lints too, as
  does `l` adding a bar at the end of the tab (5, `AddBarSlot`).
- **4.3**: an opened slot is remembered in `b:songwriter_slot` as
  `{line, tick}`. The next `h`/`l`/`w`/`b`/`a`/`i`/`<Esc>` lints the slot's
  block before doing its own job (`slots#Abandon`). A digit fills the slot
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

### Operators and text objects (spec [Tablature][[Editing]] 6)

The spec items carry the behaviour; this records why, and how it is built.

- **The time column is the unit of editing.** Vertical alignment says which
  notes are played together, so in tablature mode no operator may change one
  string without the others. Native single-line edits followed by a lint are not
  safe: lint cannot tell an intended shift from an accidental one, and would
  keep a wrong alignment. Single-string editing stays available by leaving
  tablature mode.
- **Vim's grammar rather than one command per operation.** Operators (`d`, `y`,
  `c`) times targets (columns, bars, motions) give every combination, plus
  registers and `.`, for free. They run through `operatorfunc`/`g@`. A `<Cmd>`
  before `g@` lints the block first (its undo step is joined to the
  operation's with `:undojoin`); it consumes the count, so the count is given
  again after `g@` (`g@3w`). `v:register` is not reliable inside the
  operatorfunc, so the operator, register and "exact target" flag are kept in
  `s:pending`.
- **Spacing is rhythm.** The gap after a note belongs to it: `ac`, a snapped
  motion range and `x` on a lone note remove it with the note, so the
  previous note keeps its length and what follows moves earlier. Rests exist
  only where the user put them with `_`; erasing never creates one, except that
  `x` on a shared column leaves the other strings' timing intact.
- **The column is the tab's line.** A doubled operator acts on a line in text
  and on the time column in a tab: `dd`/`yy`/`cc` are `dac`/`yac`/`cac`, so
  `ddp` and `yyp` swap and duplicate columns as they do lines. The second key
  is an operator-pending map (`Doubled`), not a normal-mode `dd` map: this
  gives `d3d` and avoids waiting on `d` for a possible `dd`. Whole tabs are
  reached with `ap` (tabs are separated by blank lines) or any line-wise
  motion. `D`/`C` stop at the bar's end, the column-wise analogue of a line's
  end. `Y`/`D`/`C` return the operator followed by their target as a
  `<Cmd>`, since keys returned by a `noremap` would not reach our maps.
- **Notes.** `in`/`an` act on one string, but keep the register a
  full-height column with dashes elsewhere, the same shape as `x` writes, so a
  copied note pastes on its own string and as new time. `gp` is the other way
  to paste: onto an existing column, no time added, refusing to replace a
  note, since silently changing music is what these operations avoid.
- **`>>`/`<<`** nudge rhythm: a dash before the column, inserted or removed on
  every string, so what follows moves with it. Lint keeps two dashes after a
  pipe, so on a bar's first column they would be undone and do nothing.
- **Text object names.** `ic`/`ac` (column), `i|`/`a|` (bar), `in`/`an`
  (note). Bare letters
  are motions after an operator (`db`), and `ib`/`ab` are Vim's parenthesis
  objects; `i|` follows Vim's delimiter objects (`i"`, `i(`). Our objects set an
  "exact" flag so the operator does not snap them (`ic` would otherwise grow
  into `ac`). Column counts stop at the bar's end, so a column object never
  contains a pipe.
- **Ranges that cross a bar line** (`d$`, `d2w`): the columns are removed and
  a pipe is put back where the range started, so the bar it started in is
  closed there and nothing is left after the final pipe (which lint drops).
- **Registers are plain blockwise registers**, so they interoperate with
  `<C-v>` and with editing outside tablature mode. Source string names are kept
  in `g:songwriter_register_names` with the register's content; they count only
  while the register still holds that content. Pasting between tabs with a
  different number of strings matches rows from the bottom (bass into guitar)
  and refuses when tuning names disagree, instead of silently putting notes on
  the wrong strings. A line-wise paste of tab lines next to a tab gets a blank
  line between them, or the two tabs would become one.
- **`c` opens its slot** with the existing `a`/`i` slot logic, anchored on the
  note column that was next to the deleted range (before the next one,
  else after the previous one, else an empty 5-dash bar), followed through the
  lint.
- **`.`** Operators repeat natively. `g@` records every operator, including a
  yank, so after `ya|` a `.` repeats the yank (native `y` is not repeatable);
  accepted rather than reimplementing redo. `x`, `p`, `P`, `>>`, `<<` are `<Cmd>`
  actions, invisible to redo: they record themselves in `b:songwriter_repeat`
  (`repeat#Record`) with the changedtick they left, and the `.` map runs
  them again while the buffer is unchanged since. The string moves (spec 7)
  record themselves the same way.
- **No counts in front of a command.** Digits enter notes in tablature mode
  (spec 3.4), so `3x` types a 3. Counts work after an operator (`d2ac`, `d3w`)
  and in visual mode, where digits are not mapped. The entry points still take
  a count.
- **Visual mode.** Text objects show the real (full-height) extent as a
  blockwise selection, and extend when repeated while the selection is still
  theirs; a plain `v` selection is widened at operator time instead, so `v`
  does not move the cursor off its string. `V` is a column selection (the
  common case in a tab), not line-wise: whole tabs are already `dap`/`yap`,
  and the native line-wise selection is one more `V` away (`VV`). `j`/`k`
  are clamped to the tab rather than blocked on a full-height selection, so a
  partial `<C-v>` still grows and shrinks natively.

### Moving notes between strings (spec [Tablature][[Editing]] 7)

`tab/strings.vim`: a pure `Move()` and its entry point `Change()`, which lints
before and after like the other tablature-mode edits.

- **Keys.** `s` keeps the fret, `S` keeps the pitch; then `k`/`j` move the note
  under the cursor, `K`/`J` its whole time column. `J`/`K` alone are left to
  the user (often remapped for navigation). Native `s` edits one string only,
  which tablature mode already rules out (spec 6). `S` is therefore not `cac`
  (spec 6.8): a lone `S` would wait for 'timeoutlen' to rule out `Sk`, and
  `cc` already does it. No count: digits enter notes
  (spec 6.12), and moving one string at a time is what is needed.
- **One string per move.** A column moves as a whole, every note by one string,
  so its notes never collide with each other: sources are cleared first, then
  each note is written on its new string.
- **Pitch from the string names.** The interval between two neighbouring
  strings is the difference of their pitch classes (`pitch.vim`), modulo 12.
  This assumes strings listed from the highest to the lowest and less than an
  octave apart, which covers standard and drop tunings, basses and 7-strings.
  String names are one letter, so an evenly lowered tuning (E flat standard
  written `eBGDAE`) has the same intervals and works. Two strings with the same
  letter (`E` above `e`) give no interval and the move is refused, rather than
  guessing an octave.
- **Room, not overlap.** A note that gets wider (`7` -> `12`) could touch the
  next note on its new string and merge with it (`123`), which lint cannot
  undo. So dashes are inserted on every string, right after the note when it
  would touch the next note or the pipe, or right before the column when a
  note ends just before it there. Insertion points never cut a note in two on
  another string; the following lint normalises the spacing.

### New tab (`o`/`O`, spec [Tablature][[Editing]] 8)

`o`/`O` open a tab the way they open a line in text: under / over the whole
current tab, never between its strings. The new tab copies the string names, so
a bass or drop-D tab gets a matching one, and starts as the new bar of spec 5
does (`|-----|`, slot in the middle, `b:songwriter_slot`), so the same rules
fill or abandon it. The blank line keeps the two tabs separate blocks (as a
line-wise paste does, 6.3.2). The cursor keeps its string, so typing goes on
on the string being worked on. Outside tablature mode `o`/`O` stay native.

### Outside tablature mode

On a tab line, `w`/`b` stop on notes, string names and pipes but never on dashes
(spec [Tablature][[Motions]] 1-2), and `L`/`H` jump to the next/previous pipe
(3-4) using `search()`, which ignores `iskeyword`. Off a tab line every key keeps
its default behaviour.

## Chords

The chord grammar (`grammar#ParseChord`) is strict and anchored: a token is a
chord only if all of it is a root (`[A-G][#b]?`), a quality built from known
parts (`m`, `min`, `maj`, `M`, `dim`, `aug`, `sus`, `add`, digits, `#`, `b`,
`+`) and an optional `/bass` root. So `Bad` and `xAm` are not chords, while
`Am7b5`, `Dadd9` and `D/F#` are. The token under the cursor is the maximal run
of chord characters (`[A-Za-z0-9#/+]`) around it, so a slash chord is found
whole whichever part the cursor is on. Tab lines never hold chords (`B|` is a
string name).

The chord model in `chord.vim`:

- `s:chord_parse(name)` -> `{name, root, quality, bass}`, or `{}` for a
  non-chord; `root` and `bass` keep their spelling;
- `s:chord_build(root, quality, bass)`;
- `s:chord_transpose(parsed, semitones)`: root and bass both move; flats are
  normalised to sharps, the single spelling in the chromatic scale;
- `s:splice_chord(line, found, new)`.

A chord action is: find the chord under the cursor, parse, transform root or
quality, build, splice back. The public actions differ only in the transform,
and are no-ops off a chord, except `<Ctrl-A>`/`<Ctrl-X>`: they transpose by
their count, and off a chord they run Vim's own increment/decrement, so numbers
in prose and frets in tabs still work. On a tab line `nrformats` gets
`unsigned` for that call, since a dash before a fret is not a minus sign.
In visual mode they act per selected line: the chords the selection touches are
transposed (spliced right to left, so a wider chord does not shift the others'
columns before they are found), and a line where it touches none gets Vim's
visual increment on its selected part, again unsigned on tab lines.
`<leader>m` treats a leading `m` or `min` (but not `maj`) as minor.
Highlighting stays permissive and accepts false positives such as the word "A"
(spec [Chords][[Rendering]]); it is separate from the editing grammar.

## Testing

- Vader, `make test`; the pre-commit hook enforces a green suite.
- Buffer transformations use `Given songwriter` / `Execute` or `Do` / `Expect`,
  so the before/after tab is visible; cursor positions and pure functions use
  `Assert*`.
- Vader reuses one buffer across cases and files, so buffer state (the
  tablature-mode flag) is reset in a `Before:` block wherever keys are typed.
- Key mappings are exercised end-to-end with `normal` where the result is
  observable; `Dispatch` and `b:undo_ftplugin` have their own tests.
