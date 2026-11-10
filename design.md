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
| `autoload/songwriter/grammar.vim` | The format's patterns (tab line, note, fret, separator, chain, chord, highlighting). The only place regexes for the format are written. |
| `autoload/songwriter/tab/model.vim` | Tab block model: parse, queries, the column-insertion primitive, and `Read`/`Write` (the buffer edges). |
| `autoload/songwriter/tab/edit.vim` | The buffer side of a tablature edit: `Commit` a pure function's result (write, cursor, lint and follow, message or refusal), `Run` a whole edit at the cursor. |
| `autoload/songwriter/tab/slots.vim` | Slots: where a new note's room goes (pure) and the buffer's one open slot, with how to close it. |
| `autoload/songwriter/tab/insert.vim` | The insert state of tablature mode: entering, keeping, leaving it, and `<Esc>`. |
| `autoload/songwriter/tab/state.vim` | Buffer state valid only while `b:changedtick` is unchanged (slot, insert state, digit being typed, `.`). |
| `autoload/songwriter/tab/lint.vim` | The linter, as a pure function over a block's lines. |
| `autoload/songwriter/tab.vim` | Tab operations and motions: buffer entry points around the model. |
| `autoload/songwriter/tab/columns.vim` | The column model behind tablature-mode operators, pure: text object ranges, snapping, delete, extract, paste with row matching, erase. |
| `autoload/songwriter/tab/operator.vim` | Tablature-mode operators, text objects, `x`/`p`/`P`, `>>`/`<<`, `gp`: buffer entry points around `columns.vim`. |
| `autoload/songwriter/tab/visual.vim` | Tablature-mode visual mode: selections, motions, operators on a selection. |
| `autoload/songwriter/tab/register.vim` | Blockwise tab registers and the string names of their source tab. |
| `autoload/songwriter/tab/repeat.vim` | `.` for actions that are not operators. |
| `autoload/songwriter/tab/voicings.vim` | Whole chords on a time column: voicings of a chord name in their cycle order, placing one (pure), and `=`/`==`. |
| `autoload/songwriter/tab/strings.vim` | Moving notes and time columns to another string, keeping the fret or the pitch: pure `Move()` and its entry point. |
| `autoload/songwriter/chord.vim` | Chord model and chord editing. |
| `autoload/songwriter/pitch.vim` | Pitch classes: note names to semitones and back (sharp spelling). Shared by chords and tab string intervals. |
| `autoload/songwriter/keys.vim` | Context-dependent keys: tables and `Dispatch()`, tablature-mode flag and state (`Mode()`), tab-line `w`/`b`/`W`/`B`. |
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
0.5+): no mode change (visual `W`/`B`/`E` stay in visual mode), no command-line
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
- **Note**: a fret (a run of digits; `12` is one note spanning two columns) or
  `x`. There is one note model: motions, time columns, operators and the
  linter all use `model#Notes`.
- **Separator**: anything else between notes (`h`, `/`, `b`, `~`, unknown
  notation). A separator is closer to a dash than to a note: `5h7` can be a
  long 5 before the hammer-on, so the 7 has its own moment in time and a note
  on another string can line up under it. It takes up space and is preserved.
  Being the default class, notation the plugin has never heard of is safe.
- **Chain**: a run of notes and separators with no dash. Used by string moves
  only, since a hammer-on stays on one string; everything else works on notes.
  Decoration around a note (`(5)`, `<12>`) is separators too, so erasing the 5
  leaves `()`; digits that are not frets (`7b1/2`) read as notes.
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

**Separators are kept** (spec 1.5). They are placed alongside the notes of their
string, keeping the same distance from what precedes them, so a pushed note
leaves its separator behind (`5h--7`). They count for the bar's edges but not
for overlaps between strings, since they occupy no time. Everything else in a
bar (dashes, whitespace) is re-rendered as dashes.

**Empty bar** (no note on any string) becomes `|-----|`: five dashes rather
than the two of a bar edge, so that a slot opened in it is its middle dash and
a note typed there (`|--7--|`) needs no reflow.

**Empty bars at the end are deleted** (spec 1.4): a trailing empty bar is
leftover space, not music. All of them go, not just the very last one, so that
lint stays idempotent (linting twice changes nothing); empty bars between
notes are rests and are kept. A tab keeps at least one bar, so an all-empty tab
lints to `|-----|`. This applies to every lint, so `cap` leaves a single bar. A cursor that was in a deleted
bar lands on the tab's last pipe.

**Overlapping notes** (spec 1.3, two-digit notes). Each note gets a natural output
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

### Vim's units in a tab

Text is one-dimensional; a tab has two axes, time (left to right) and strings
(top to bottom). Each of Vim's units is mapped onto the axis where it means
something, so that its keys keep their instinctive sense:

| Vim unit  | In a tab | Keys |
|-----------|----------|------|
| character | the time column as a position, the note as content | `l` `h`, `x`, `ic`/`ac`, `in`/`an` |
| word      | a chain on one string: a dash is the space between words | `w` `b` `e` `ge`, `iw`/`aw` |
| WORD      | a bar | `W` `B` `E`, `i\|`/`a\|` (`iW`/`aW`) |
| line      | for editing, the time column; for moving, the string | `dd` `yy` `>>`; `j` `k` |
| sentence  | nothing: the format marks no phrases or beats | native |
| paragraph | a tab (tabs are separated by blank lines) | native `{` `}` `ip`/`ap` |

- **A word is a chain**: Vim's word is a run of non-blanks, and a chain is a
  run of notes and separators with no dash, so `5h7` is one word, as it is one
  unit for the string moves (spec 7.1). `l` still reaches its 7, which has its
  own time column, so `l` <= `w` <= `W` in reach.
- **The line splits in two.** A text line is both the unit `j`/`k` move
  across and the record `dd`/`yy`/`>>` act on. Across strings, a string cannot
  be that record (nobody means to delete the G string), so editing goes to the
  time column (see "Operators and text objects") and moving stays on strings.
  `D`/`C` need an end, which a column does not have: they borrow the bar's.
- **An operator's reach follows its motion** (spec 6.2). The string motions
  (`l` `h` `w` `b` `e` `ge`) move along one string, so after an operator they
  erase notes on that string, each as `x` does; `dl` is `x`, as in Vim.
  Widening `dw` to every string would delete every other string's notes up to
  wherever this string plays next, which in a sparse tab is much more than a
  word. Column-wide targets (`ac`, `a|`, `dd`, `dW`, `d$`, `f`/`t`) act on
  time columns.

### Tablature mode (`<leader>t`, spec [Tablature][[Editing]] 3)

A buffer-local flag, `b:songwriter_tabmode`, set on by the ftplugin when a
buffer is opened (and unset by `b:undo_ftplugin`); unset means off.

**Two states, as in Vim.** In the normal state moving never changes the file:
Vim's contract is that motions only move, and a motion that edits puts cursor
moves in the undo history, marks a file modified just by reading it, and fills
the change list. The insert state is for writing: there, moving across notes
opens slots for new ones. It is a state of tablature mode rather than Vim's
own insert mode so that `h`/`l` keep moving (in Vim's insert mode they would be
text, and arrow keys would be needed).

- **The state** (`tab/insert.vim`) is kept in `tab/state.vim`, valid only while
  `b:changedtick` is unchanged: the edits made in it (opening, filling, closing
  a slot) record it again (`insert#Keep`), and any other change (`u`, `x`, an
  operator) ends it without the other code having to know about it. Opening a
  slot enters it (`slots#Open`), so `a`/`i`, `c`, `o`/`O` and
  `:SongwriterNewTab` all do; `<Esc>` closes the slot and leaves it.
  Entering shows `-- TAB INSERT --`, after a `redraw` so that repeated state
  changes replace each other instead of piling up into a hit-enter prompt;
  `songwriter#keys#Mode()` is there for status lines.
- **`w`/`b`/`e`/`ge` (3.2)**: by word (a chain, see "Vim's units in a tab")
  on the current line: `w`/`b` stop on a word's first note, `e`/`ge` on its
  last (`model#Words`). Dashes and pipes are not stops; a two-digit fret is
  landed on at its first digit.
- **`l`/`h` in the normal state (3.3.1, 3.3.2)**: next/previous stop: a column
  where any string of the block has a note, or the middle dash of an empty bar
  (3.3.4), since a bar with no time column could otherwise never be reached.
  Pipes are not obstacles. With no stop that way, the cursor stays.
- **`l`/`h` in the insert state (3.3.3)**: the gaps between notes are stops
  too. On a note column, `l` is `a` and `h` is `i`. On the open slot, they close
  it and move on. The slot remembers which side of its note it was opened on
  (`side`), and the move goes on from where the cursor was before it opened
  (`from`): towards that note it lands back on it, away from it it goes to the
  next stop. So from `3` in `3-5`, `l` `l` `l` gives slot, `5`, slot; each gap
  is visited once per direction, and a bar line needs no special case: from a
  bar's last note `l` opens a slot in that bar, then reaches the next bar's
  first note. Landing in an empty bar opens a slot in its middle
  (`slots#EmptyBar`). Elsewhere (the cursor moved off the stops with native
  keys), `l`/`h` move as in the normal state.
  - *End of the tab (5)*: `l` with no stop further right, from a slot in a bar
    with notes or from anywhere past the stops, in the last bar of a tab whose
    lines end with a pipe, appends a new bar `-----|` and lands on its middle
    dash, a slot like any other. On the new bar's slot (a bar with no note)
    `l` does nothing, so holding `l` never piles up bars.
- **`L`/`H` (3.3.5)**: the normal-state `l`/`h` in both states
  (`StepColumn`), so the insert state has a way through notes that does not
  stop on every gap. An open slot is closed first and the move goes on from
  its note as `l`/`h` would (`s:from_slot`); they never open one, not even in
  an empty bar or at the end of the tab. After an operator and in visual mode
  they are `l`/`h`. Vim's own `L`/`H` (bottom/top of the window) are little
  use in a tab, whose few lines all fit on screen.
- **`W`/`B`/`E` (3.5)**: by bar, as Vim's WORD motions are a bigger
  `w`/`b`/`e` (`columns#BarStop`, pure). `W` goes to the first time column of
  the next bar, `B` to the first of the cursor's bar or the previous one, `E`
  to the last of the cursor's bar or the next one, so they land where a note
  can be edited rather than on a pipe. Bars are read from the cursor line's
  pipes (aligned in a linted tab), time columns from the whole block; a bar
  with no note stands for its middle dash. Normal and visual mode only: after
  an operator `W` keeps the pipe motion, so `dW` stays "to the end of the
  bar" (`D`, 6.8.1).
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
  linted (4.1, below), which fixes the spacing. `x` on a dash enters a muted
  note the same way (3.4.3); on a note it stays the erase of spec 6.7. Off tablature mode or a tab
  line, digits keep their count meaning. Digits work in both states and keep
  the state they are typed in.
- **Typing a run of notes (3.4.1.1-3.4.1.3)**: in the insert state the next
  note is the common case, so a digit straight after a note opens a slot after
  it (`AddNote(1)`, what `l` does) unless appending it makes a real fret (no
  leading zero, at most `g:songwriter_max_fret`). The fret range resolves the
  `12`-or-`1 2` ambiguity: only `1` and `2` (up to 24) can start a two-digit
  fret, and `<Space>`, which is `l` in the insert state, ends a `1` that is
  meant alone. The cursor stays on the typed note rather than moving to the
  next slot right away, so `j`/`k` still build a chord on the note's column,
  and nothing is opened that would have to be closed again. The normal state
  keeps the plain append of 3.4.1: there a digit edits the note under the
  cursor, it never adds one.
  Separators are typed the same way: straight after a note (`JustTyped`, a
  dispatch context of its own in `keys.vim`), `h p b r t s / ~` write a
  separator in a new column (on every string, so later notes keep their gap),
  and `typing.separator` makes the next digit go in a new column right after
  it. Those keys lose their meaning only for that one keystroke, where moving
  or pasting is rare; `\` is left out as it is the default `<leader>`.

### Linting after edits (spec [Tablature][[Editing]] 4)

Tablature-mode edits lint the block:

- **4.1**: a digit enters the note, then the block is linted.
- **4.2**: `a`/`i` lint, then open the slot. `l`/`h` opening a slot in the
  insert state are the same operation (`AddNote`), so they lint too, as does
  `l` adding a bar at the end of the tab (5, `AddBarSlot`).
- **4.3, closing a slot**: an open slot is remembered in `b:songwriter_slot`
  (`tab/state.vim`), so it counts only while `b:changedtick` is unchanged: any
  other buffer change (undo, `x`…) drops it, since the block it pointed to may
  no longer be there. The next `h`/`l`/`w`/`b`/`W`/`B`/`E`/`a`/`i`/`<Esc>`
  closes it first (`slots#Abandon`); `j`/`k` are not mapped, so the slot
  survives them. A digit fills the slot and forgets it.
  - *A slot opened by moving, `a`/`i` or a new bar is undone*: closing it gives
    the tab back exactly as it was before, including the lint of 4.2, so that
    wandering in the insert state leaves no trace. `slots#Mark`, taken before
    anything changes, records the block's lines, the cursor column and the undo
    sequence number. Closing runs `:undo` when the slot's change is the last
    undo step and that step holds nothing else (its sequence number differs
    from the one before it). Then no undo step is left behind and a file saved
    before `a` is unmodified again. Inside `:normal`, a macro or a mapping,
    several keys share one undo step, and `:undo` would take earlier changes
    with it: then (or if undoing did not give the lines back) the recorded
    lines are written instead.
  - *A slot that is part of a bigger edit is linted*: `c` (6.6), `o`/`O` (8)
    and `:SongwriterNewTab` (9) open a slot in what they made; `<Esc>` there
    must keep the deletion or the new tab, so closing lints, leaving an empty
    bar as `|-----|`.
- **4.3.1**: a digit typed into a slot, or appended to a fret being typed, is
  joined to the previous undo step (`:undojoin`), so `a7` or `a12` is one undo
  step and `u` gives back the tab as it was before `a`.

**The cursor follows the music** (`lint#FollowColumn`): on a note it stays on
the same digit of that note; elsewhere in a bar it keeps its distance from the
nearest note starting at or before it (any string), clamped before the next
note and inside the bar. Notes before/after the cursor stay before/after it, so
`a`/`i` find the same anchor after the lint as before. `||` lints without
moving the cursor.

`<Esc>` is a context key like the others (`insert#Escape`). Outside tablature mode `Dispatch`
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
- **Notes.** `in`/`an`, `iw`/`aw` and the string motions (6.2.2) act on one
  string, but keep the register a full-height column with dashes elsewhere,
  the same shape as `x` writes, so a copied note pastes on its own string and
  as new time. Objects yank their exact range; a string motion yanks what `x`
  would write for each note it covers, one after the other, so `dl` and `x`
  fill the register alike. Either way, deleting erases each note as `x` does,
  right to left so that a removed column does not shift the next ones. `gp` is the other way
  to paste: onto an existing column, no time added, refusing to replace a
  note, since silently changing music is what these operations avoid.
- **`>>`/`<<`** nudge rhythm: a dash before the column, inserted or removed on
  every string, so what follows moves with it. Lint keeps two dashes after a
  pipe, so on a bar's first column they would be undone and do nothing.
- **Text object names.** `ic`/`ac` (column), `i|`/`a|` (bar, also
  `iW`/`aW`), `in`/`an` (note), `iw`/`aw` (word). Bare letters
  are motions after an operator (`db`), and `ib`/`ab` are Vim's parenthesis
  objects; `i|` follows Vim's delimiter objects (`i"`, `i(`). Our objects set an
  "exact" flag so the operator does not snap them (`ic` would otherwise grow
  into `ac`). Column counts stop at the bar's end, so a column object never
  contains a pipe.
- **Ranges that cross a bar line** (`d$`, `d2W`): the columns are removed and
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
- **Chains move whole.** A hammer-on or slide cannot change strings halfway, so
  `s`/`S` take the chain under the cursor (spec 7.1). `K`/`J` act on a time
  column and refuse a chain that starts before it, rather than dragging notes
  from another column along.
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

### Chords on a column (`=`, `==`, spec [Tablature][[Editing]] 10)

`tab/voicings.vim`: pure `Voicings()` (a chord name and string names in, the
voicings in their cycle order out) and `Place()`, and the entry points.

- **The root is on the cursor's string.** The string is already where the
  cursor is, and it is the choice a guitarist makes first (open Am from the A
  string, barre from the low E), so no other argument is needed to pick
  between open and barre shapes.
- **`==` cycles, ordered by how often a voicing is wanted.** Lower root strings
  come before higher ones (the E-string barre is the usual second choice after
  an A-string shape), lower frets first, and the 12th-fret repeats of open
  shapes last. `==` is one key read by `=` (`getchar()`), not a second map, so a
  lone `=` never waits for 'timeoutlen'. It works only straight after `=` or
  `==` (the voicing list is kept in `tab/state.vim` with its changedtick), and
  joins their undo step.
- **Fixed shapes for standard tuning, intervals for power chords.** Full chord
  shapes are only playable as the familiar fingerings in standard tuning, so
  they are tables of fret offsets (CAGED: E, A, D at any fret; C and G in open
  position only, where they are actually used) and other tunings are refused.
  A power chord is three strings and computes well from the string names, as
  `S` does (spec 7.3), so drop D gets its one-finger shape for free.
- **The chord replaces the column**, as a digit replaces a note: the notes
  starting on it go, and a two-digit fret gets room as a moved note does
  (`columns#MakeRoom`, spec 7.5). Unplayed strings stay dashes: muting marks are
  the user's call (`x`).
- **Typing on.** In the insert state a chord counts as a typed note
  (`typing.chord`): a digit after it opens the next slot even when it would
  extend the root's fret (`1` then `2` is not `12`), and separators are not
  typed after it.

### New tab (`o`/`O`, `:SongwriterNewTab`, spec [Tablature][[Editing]] 8, 9)

`o`/`O` open a tab the way they open a line in text: under / over the whole
current tab, never between its strings. The new tab copies the string names, so
a bass or drop-D tab gets a matching one, and starts as the new bar of spec 5
does (`|-----|`, slot in the middle, `b:songwriter_slot`), in the insert
state. A digit fills it; closed without one, it is linted rather than undone
(4.3), so the new tab stays. The blank line keeps the two tabs separate blocks (as a
line-wise paste does, 6.3.2). The cursor keeps its string, so typing goes on
on the string being worked on. Outside tablature mode `o`/`O` stay native.

`:SongwriterNewTab` (spec 9) is the way in when there is no tab yet to press
`o` in. It builds the same empty tab from given string names (validated by
`grammar#IsStringNames`, the same single-letter name a tab line starts with),
and turns tablature mode on, since the slot it opens only means something
there. It is a command rather than a key: a key on a prose line would take a
native key away, and the command takes the tuning as its argument.

### Outside tablature mode

On a tab line, `w`/`b` stop on notes, string names and pipes but never on dashes
(spec [Tablature][[Motions]] 1-2), and `W`/`B` jump to the next/previous pipe
(3-4) using `search()`, which ignores `iskeyword`: on a tab line, Vim's own
`W`/`B` see the whole line as one WORD and are useless. `L`/`H` keep their
native meaning (5). Off a tab line every key keeps
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
visual increment on its selected part, again unsigned on tab lines. Unlike
Vim's, the selection is kept afterwards (same corners, cursor on the same end),
so pressing `<Ctrl-A>` again keeps transposing.
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
