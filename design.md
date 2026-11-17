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
| `autoload/songwriter/tab/colmap.vim` | Column maps: where each column of a block went through an edit, pure. |
| `autoload/songwriter/tab/annotations.vim` | Annotation lines, pure: parsed into anchored words, placed through an edit's column map and its operations (`Apply`), the room the tab must make for its labels (`Room`), and the one layout (`Render`). |
| `autoload/songwriter/tab/model.vim` | Tab block model: parse, queries (notes, time columns, bars), `Splice`/`Blank` and the column-insertion primitive, snapshots, and `Read`/`Write` (the buffer edges). |
| `autoload/songwriter/tab/edit.vim` | The buffer side of a tablature edit: `Do`, the one pipeline every edit of a tab goes through (slot, first lint, the pure edit, lint, one write with its undo join, then the follow-ups: selection, state for the next key, register, slot, `.`, insert state); the pure `Linted`; `JoinUndo` for the changes that are not tab edits. |
| `autoload/songwriter/tab/slots.vim` | Slots: where a new note's room goes (pure), the buffer's one open slot with how to close it, and `a`/`i` and the new bar's slot (`AddNote`, `AddBarSlot`). |
| `autoload/songwriter/tab/mode.vim` | The states of tablature mode (normal, insert, move): the current one, entering and leaving them, their messages, `m`. |
| `autoload/songwriter/tab/typing.vim` | Typing notes and separators: digits, `x` on a dash, separators after a note (`EnterNote`, `EnterSeparator`). |
| `autoload/songwriter/tab/motion.vim` | Tablature-mode motions at the cursor (`w`/`b`/`e`/`ge`, `l`/`h`, `L`/`H`, `W`/`B`/`E`), and the slots the insert state opens on the way. |
| `autoload/songwriter/tab/stops.vim` | Where motions stop and what string motions cover after an operator, pure (`Stops`, `Advance`, `BarStop`, `StringMotion`), and the insert state's positions and how `l`/`h` step through them (`Step`). |
| `autoload/songwriter/tab/carry.vim` | Carrying notes across strings: the pure carry (`Lift`, `Copy`, `Step`, `Render`, `Move`), `<leader>k`/`<leader>j` and `s`/`S`, copies, visual carries and the move state (`m`). |
| `autoload/songwriter/selection.vim` | The visual selection, for actions that change the text from visual mode and select again (`Get`, `Spans`, `Select`). |
| `autoload/songwriter/tab/newtab.vim` | New tabs: `o`/`O` and `:SongwriterNewTab`. |
| `autoload/songwriter/tab/state.vim` | The buffer's named states (slot, insert and move states, digit being typed, carry, `.`, visual object...) and the one table of how long each holds, which `Get` honours. |
| `autoload/songwriter/tab/check.vim` | The rules of the music, checked on every edit in check mode (`g:songwriter_check`, set by the test suite): pure `Errors`, and `Edit`, which throws. |
| `autoload/songwriter/tab/lint.vim` | The linter, as a pure function over a block's lines. |
| `autoload/songwriter/tab/highlight.vim` | The time column under the cursor, highlighted in tablature mode. |
| `autoload/songwriter/tab/unlinted.vim` | The string names of the tabs with no time columns, highlighted. |
| `autoload/songwriter/tab.vim` | The tab commands that work outside tablature mode too: `_`, `\|\|`, `:SongwriterAddBar`, `:SongwriterAddDashes`, `:SongwriterTabChord`. |
| `autoload/songwriter/tab/columns.vim` | Editing time columns, pure: extract, delete, erase (any set of notes, `EraseSet`), shift, make room for a note, rewrite a note in place (`SetNote`), and the guards that keep chains apart (`KeepApart`, `WriteNote`). |
| `autoload/songwriter/tab/frets.vim` | `<C-A>`/`<C-X>` in tablature mode: pure `Add()` and the normal and visual entry points. |
| `autoload/songwriter/tab/objects.vim` | Text object ranges and the snapping of other ranges, pure. |
| `autoload/songwriter/tab/paste.vim` | Pasting blockwise registers, pure: row matching, insert, overlay. |
| `autoload/songwriter/tab/operator.vim` | Tablature-mode operators (`g@`, motions, text objects, ranges): buffer entry points around the pure modules. |
| `autoload/songwriter/tab/actions.vim` | The edits at the cursor that are not operators: `x`, `p`/`P`, `>>`/`<<`, `gp`. |
| `autoload/songwriter/tab/visual.vim` | Tablature-mode visual mode: selections, motions, operators on a selection. |
| `autoload/songwriter/tab/register.vim` | Blockwise tab registers and the string names of their source tab. |
| `autoload/songwriter/tab/repeat.vim` | `.` for actions that are not operators. |
| `autoload/songwriter/tab/voicings.vim` | Whole chords on a time column: voicings of a chord name in their cycle order, placing one (pure), and `=`/`==`. |
| `autoload/songwriter/tab/chordname.vim` | Naming the chord on a time column (`=?<CR>`), and writing that name as its label (`=<CR>`): the column's pitches, named by `chord#Identify`. |
| `autoload/songwriter/tab/play.vim` | Playing a tab: the steps a target plays (pure), handed to `sound.vim`. |
| `autoload/songwriter/sound.vim` | Plucked-string synthesis into cached WAV files, the player command, and the timers and jobs that play steps. |
| `autoload/songwriter/sound9.vim` | The synthesis loop in compiled Vim9 script, used on Vim 9. |
| `autoload/songwriter/chord.vim` | Chord model, chord editing, and naming the chord of some pitches (`Identify`). |
| `autoload/songwriter/pitch.vim` | Pitch classes: note names to semitones and back (sharp spelling). Shared by chords and `tuning.vim`. |
| `autoload/songwriter/tuning.vim` | What a tab's string names mean, pure: the open strings' pitches and whether they are standard tuning (`Of`), the interval in frets between two strings (`Interval`). The one place string names become pitches: carries (`S`), chords on a column (`=`), naming (`=?`) and playing use it. |
| `autoload/songwriter/config.vim` | The plugin's options: one table of `g:songwriter_*` names and their defaults, read through `Get`. A default that depends on the system (the player found, the cache directory) is `v:null` there and computed where the option is used. |
| `autoload/songwriter/keys.vim` | Context-dependent keys: tables per mode of tablature mode and `Dispatch()`, tablature-mode flag, `Mode()` for status lines, tab-line `w`/`b`/`W`/`B`. |
| `plugin/songwriter.vim` | `:Songwriter*` commands and `<Plug>(songwriter-*)` maps. |
| `ftplugin/songwriter.vim` | Buffer options and key bindings, with a complete `b:undo_ftplugin`. |
| `syntax/songwriter.vim` | Highlighting, with patterns taken from the grammar. |

There are no global functions: everything public is `songwriter#…` and
autoloads on first use.

### Data flow

An operation is a thin buffer entry point around pure logic:

1. `songwriter#tab#model#Read()` parses the block around the cursor (or returns
   `{}` off a tab line, which every entry point treats as a no-op);
2. a pure function computes the result: new lines with their column map
   (see "Column maps") and/or a cursor column (`{'lines': [...], 'map': [...],
   'col': n}`, `{}` for "nothing to do"), and what to record (`state`,
   `register`) or open (`open`, a slot);
3. the result is written back.

`edit#Do(Fn, opts)` is the one way an edit of a tab reaches the buffer, and the
one place that applies the rules of spec 4 (linting after edits) and 4.3
(slots): what happens to an open slot (closed, closed keeping the lint,
filled), whether the edit joins the previous undo step, lints before and
after, opens a slot, keeps the insert state, and records itself for `.`. An
entry point states these as options instead of writing them out, so a rule is
never forgotten in one place. It runs in stages: prepare (the slot, the first
lint), the pure edit, write (the lint, the column map, the undo step), then
the follow-ups, each a small function (the selection, the state for the next
key, the register, a slot opened, `.`, the insert state). The lints and the
edit are computed in memory (`edit#Linted` is lint plus cursor-following,
pure) and written once, and `model#Write` sets only the lines that differ: an
edit that changes nothing leaves no undo step, and the undo join happens only
on an actual write.

Every entry point goes through it, with options for what it is not: an edit
of another block than the cursor's (`lnum`: a slot closed from elsewhere,
each tab of a line-wise `cap`, each block of a visual `<C-A>`), one that keeps
the tab as it is (`prelint` and `lint` off: `_`, `:SongwriterAddBar`, the
slot of a line-wise `cap`), an operator's edit (no first lint: `g@` runs
after the lint of its own `<Cmd>`; no lint after:
the operator lints its own result, to put the cursor on what the lint left),
a lint alone (`||`, the operators' first lint: an edit that does nothing).
A slot that is part of a bigger edit (`c`, 6.6) is the result's `open` (the
side, as `i`, `a` or an empty bar): `Do` opens it once the rest is linted and
room made, in the same write, so `c` is one edit like any other. A visual edit hands over
its selection (`selection`, `selection.vim`), which is selected again once
written, its ends where the edit says they went (`sel`), followed through the
column map: visual carries are a step like any other. `undojoin` is only in
`edit.vim`; `JoinUndo` is there for the changes that are not edits of a tab
but belong with one made in an earlier command: the trailing spaces trimmed
when Vim's insert mode is left after `cia` typed somewhere unexpected.

**The cursor may be on an annotation line.** `Do`'s cursor line counts from
the block's first string, so an annotation line is a negative one (-1 right
above the strings), and on it the cursor column is a display column. It
follows the edit's column map (and the lint's, and the room made) like a
string's, so a cursor on a label stays on it, and it becomes bytes only when
written back. An edit started from an annotation line (`=` on a label, the
end of `cia`) is thus an ordinary edit, with its undo step, state and `.`,
and no moving of the cursor to a string and back. The two units stay
(display columns on annotation lines, bytes on strings): unifying them was
judged to give no simpler code, since labels are placed by display column
and strings are cut by byte.

**Drafts and snapshots.** What reaches the buffer is a draft: the block's new
lines, and where each column of its base went in them (`{'lines', 'map',
'base'}`). The base is the snapshot (`model#Snapshot`, the block as written:
its first line and lines) the edit started from: by default the block being
written; for a carry, the origin or the base it saved, since it renders from
those rather than from what is in the buffer. `edit#Do` turns a draft into
a snapshot (`edit#Derive`) and `model#Write` writes it; restoring a saved
snapshot (a slot closed, 4.3) writes it as it is. A draft without a map is an
error, thrown, so no write path can lose track of where the tab went; every
part of a block other than its strings is kept in step in `Derive` and
`model#Write`, and nowhere else.

**Checking the rules.** Each primitive keeps the rules of the music on its
own (a note's time column, chains kept apart), so a primitive that forgets
one breaks the music silently. With `g:songwriter_check` set (the Makefile
sets it for every test), `edit#Do` checks the result of every edit against
the lines it was given, through its column map (`tab/check.vim`): every note
it did not erase is a note with the same text where the map puts it (so
notes that started together still do, and none was joined to another), two
of them that were in different chains still are, and every lint leaves the
tab with time columns (`model#Timed`); a broken rule throws, naming the edit. What an edit changes
on purpose it says in its result: `erased` (notes of the lines it was given)
and `written` (where the notes it writes start, in its lines; a written note
must be a note of its own, so a note written right after another one is
caught). Composed edits carry written positions forward with
`colmap#Positions`; erasures are declared on the input lines, so an edit
erases first and lints after, rather than lint between erasures. A tab with no time columns cannot be edited but by
`||` (see "Tabs with no time columns"), so of that lint only each string's
notes in order are checked. The
lint's fixed point and the room made for labels throw in check mode when
they hit their pass cap rather than stop silently. `Do` also throws, in
check mode, on a result key or an option it does not know (the lists at the
top of `edit.vim`), so a misspelt key is not silently ignored.

**Refusals.** A pure function that can refuse returns a dict, with 'error'
(a message without the plugin's name) on a refusal, whatever it returns
otherwise (`{'notes'}`, `{'voicings'}`, a result), so callers test one key
rather than a type; `edit#Error` (and `edit#Do` for an edit's result) shows
it with the `songwriter: ` prefix, added in that one place.

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
rebind them. `]`/`[` are a second binding of `<C-A>`/`<C-X>`, easier to reach
and easier to repeat; Vim's own `]`/`[` commands (`[[`, `]s`, `[z`…) mean
little in a song file.

`||` is not a double bar line (the format has none); it is the key that lints
the block.

### State and how long it holds

What a key leaves for the keys that follow (the open slot, the insert state,
the digit being typed, the action `.` repeats...) is a named state of
`tab/state.vim`, and how long it holds is declared once, by name, in its
table: `Get` returns the value only while it holds, so no reader writes the
rule out again and a new state is one line of the table. The lifetimes are
the ones the features need:

| Lifetime | Holds | States |
|---|---|---|
| `change` | until the buffer changes | the slot (4.3), the insert state, `.`, `gk`'s origin (`upward`) |
| `continuation` | straight after an action: buffer unchanged, cursor where the action left it | the digit being typed, the carry run, `==` cycling voicings or names |
| `on-note` | while the cursor is on a note of a tab line in tablature mode, edits included | the move state |
| `selection` | while visual mode and the selection are the ones recorded, edits included | the visual object (`vobj`) |
| `read-once` | until read | the word `cia` changes, read when insert mode is left |

Tying a state to `b:changedtick` rather than clearing it at each place that
changes the buffer means any change, `u` included, ends it without the other
code having to know. `Expire` drops a state that no longer holds, for the
one place that shows its end (the move state's message). Each read names
the lifetime it means; a new "straight after" behaviour should be checked
against both `change` and `continuation`, since reading one state with two
lifetimes once hid an undo bug.

Two states are not there, because Vim puts them elsewhere: the pending
operator (`s:pending` in `operator.vim`), since `'operatorfunc'`
takes no arguments, and the string names of a register
(`g:songwriter_register_names`), since registers are global and hold while
their content is the one recorded, which no buffer tick says.

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
  Decoration around a note (`(5)`, `<12>`) is separators too, which belong to
  the note (`model#NoteSpan`, 3.1.3), so erasing or carrying the 5 takes them
  with it; digits that are not frets (`7b1/2`) read as notes.
- **The separators of a note.** Every separator belongs to one note: the next
  one of its chain, or, with none after it, the previous one (`/5` and the
  `h` of `5h7` belong to the note after them, the `~` of `7~` to the 7). The
  next note is the default because a technique between two notes (`h`, `/`,
  `b`) says how the second one is played, and because it gives one rule
  everywhere: a note's separators go wherever it goes, and are never left
  between two notes that belong to neither, which every edit near a
  separator had to treat as a case of its own. `model#Spans` is the one
  definition (`NoteSpan` for one note), used by the linter (a pushed note
  takes them, 1.5), the slots (a slot goes past them and keeps a dash from
  those of the next note, 3.1.3), carries and `x` (they go with the note,
  6.7.4), `>>`/`<<` (the dash goes before them, 6.13) and `WriteNote` (a
  narrower fret leaves its dashes after them, 11.2) and column ranges
  (`ac`, `dd`, `dW`: `columns#DeleteColumns` turns the separators before
  their notes into dashes, as `x` does, and ends before those of the next
  note, 6.2.3), which stay time columns rather than start at the separators
  so that no range is refused where another string has a note under them.
- **Bar**: the region between two pipes. On a line, the bar around column `c` is
  bounded by the nearest pipes strictly left and right of `c`
  (`model#BarAt`).

## Tablature

### Block model

`model#Parse(start, lines)` gives `{start, end, lines, strings}` with each string's
notes (`{col, len, text}`) and pipe columns. Columns are 1-indexed byte columns,
as `col()` returns (tab lines are ASCII). Queries on a parsed block:
`NoteColumns` (block-wide, sorted, unique), `ColumnEnd`, `IsShared`,
`BarColumns` (a bar and its time columns), `BarNotes`, `GapEnd`; on a line,
`BarAt`, `InBar`, `NoteAt`, `NoteSpan`; on a list, `ColumnFor`;
and `Cursor`, the cursor as `{block, lin, col, line}`. The pure column code
(`columns.vim`, `objects.vim`, `paste.vim`) takes a block's lines and parses them
once on entry. Pure
functions address the cursor as `lin` (0-indexed in the block) and `col`. The
width of a line's prefix is known only to `Name`, `Names` and `BodyOffset`.
Text is written into a line with `Splice` (`Blank` turns a note into dashes);
the single mutation primitive across strings is
`InsertColumns(lines, offset, n, char)`: pad every line with dashes up to
`offset`, then insert `n` copies of `char` after it, on every string, so pipes
and notes stay vertically aligned.

### Column maps

Every pure edit that returns `lines` also returns `map`: where each column of
the lines it was given is in the lines it returns, or 0 when the edit deleted
it (`tab/colmap.vim`). Anything placed by time column outside the strings
follows an edit through it, exactly, rather than guessing from a diff (which
cannot tell which of the columns of a repeated riff `dd` deleted).

- **A map is a list of steps**, so composing is concatenating (`Then`) and the
  identity is `[]`: `Insert` (columns inserted after an offset), `Delete` (a
  range removed), `Resize` (a region given a new width, each column keeping its
  offset, clamped: an empty bar filled to five dashes, whose content is not
  deleted), `Func` (a re-flow, looked up only when asked, so an edit nobody
  follows costs nothing). Columns past the end follow the steps too, so text
  after a tab's last pipe keeps its distance from it.
- **The primitives make the steps** (`model#InsertColumns`,
  `columns#DeleteRange`, the row insertion of `paste.vim`, `slots#AppendBar`,
  `slots#EmptyBar`, `lint#Lint`); everything else composes the maps of what it
  calls. Splicing one string (`Splice`, `Blank`, a note rewritten by
  `SetNote`, a short line padded) moves no time column, so it adds no step.
- **Lint's map shares the cursor's rule.** A time column goes where its notes
  went, a pipe of the top string where that pipe went, any other column of a
  bar as `FollowColumn` moves the cursor there (the same distance from the
  nearest note starting at or before it, clamped before the next one and
  inside the bar: `s:in_bar`, used by both); a trailing empty bar lint drops
  is deleted. The top string stands for the block's pipes, which are aligned
  in any tab lint has seen once.
- `carry#Lift` keeps every column (the base only blanks the carried notes),
  and `carry#Render` maps the base to the rendered tab, except back at the
  origin, which is the origin itself.

### Annotations (spec [Tablature][[Annotations]])

Lines of free text right above a tab's strings (chord names, `PM-----|`) are
part of the tab, and follow its music through every edit.

- **Two leading spaces make an annotation line.** Prose and sections start in
  the first column; anything about time columns is indented past the string
  name and first pipe anyway, so the rule tells them apart without markup. A
  blank line ends the annotations, as it ends a tab.
- **Part of the block, not of its strings.** `Read` gives a block's `top` and
  `above`; `lines`, `lin` and every pure edit stay about strings only, so no
  edit had to learn about annotations. A block is identified by its `top`,
  which stays put when annotation lines come and go (a slot's revert, the
  carry). Line-wise targets (`dap`, `cap`), `P` and `O` go by the top.
- **Words, labels and spans.** A run of two or more of the same fill
  character is an extender, which stretches; everything else is rigid. A
  label is anchored on its first column, so `Am7` never splits; a span covers
  its columns, its rigid parts at its ends (`PM`, `|`). One fill character is
  not an extender, so `P.M.` and `1-2` are labels.
- **Parsed once, anchors explicit.** A block carries its annotation lines
  parsed (`block.annotations`, `annotations#Parse`): rows of words, each
  knowing whether it is anchored, i.e. starts on a time column, which it then
  stands for. Queries (`Over`, the word under the cursor) read the rows;
  display columns become bytes only where a line is read or written
  (`Bytes`).
- **A host, not a tab.** The layer knows nothing of tabs but its host
  (`annotations.vim`): the columns words stand for (`anchors`), the first
  column a word may start at (`first`), the last column of an anchor (`End`,
  which a label added over it must not run into) and where room can be made
  (`Fit`). A tab is one (`TabHost`: its time columns, column 3, dashes
  inserted where no note runs across), and the functions taking a host take
  a tab's lines for it. Chords over lyrics ([Chord annotations]) are meant to
  be another host: anchored to the lyric's characters, from column 1.
- **Following is the column map applied to words**, in two steps.
  `annotations#Apply` places each word where its column goes (a label is
  deleted with its column, as `x` deletes a note's gap with it; a span's ends
  go to the first and last columns it still covers), then does the draft's
  operations on annotations; `annotations#Render`
  lays each row out (`s:layout`, the one layout: left to right, a space
  between words, never in the first two columns, so that a line stays an
  annotation line). A line none of whose words moved is kept byte for byte,
  whitespace included: an edit that does not touch it leaves no trace in it.
  `edit#Derive` does both, so every write path has it.
- **One vocabulary for what an edit does to annotations.** Beyond following
  the map, a draft says what it does to the annotations as a list of
  operations (`annotations`): `put` (words it brings along: a paste, a
  register's rows), `label` (a chord label it writes), `clear` (`cap`).
  `edit.vim` only carries them, their columns following the lint and the
  room made like any column (`s:moved`), and `annotations#Apply` does them;
  a new kind of annotation edit is a new operation there, not a new draft
  field threaded through the pipeline.
- **A label is never moved off its column: the tab makes room.** The file is
  plain text, so a label's position is the only record of the column it
  stands for; pushing it right (as the layout would when it runs into the
  word before) loses that for good. So between placing and laying out,
  `annotations#Room` finds the first anchored word the layout would push and
  says where to insert dashes (right before its column, outside any note),
  and `edit.vim` (`s:make_room`, on the first lint and on the result) inserts
  them, the map, the cursor, the words put and the label following, until
  nothing is pushed. A tab is thus never narrower than its labels need: `<<`
  against a label changes nothing, a chord name too wide for its gap widens
  it. Words that stand for no column (in a gap) are still pushed, and so is a
  word whose room would widen the span before it, which no insertion helps.
- **Exact restores stay exact.** A slot's mark and a carry's origin are
  snapshots, annotations included, so giving the tab back gives them back. A
  carry renders from its base snapshot, which has the origin's columns, so
  its annotations are the origin's.
- **Registers carry the words a deletion takes.** A column or bar register
  has the annotations deleted with it (for a yank, those a deletion would
  delete) as rows above the strings' rows, so it stays a plain blockwise
  register, and `register.vim` records how many rows are annotations. A paste
  puts them back as `put` operations of its draft, above each copy. A register
  changed since (a native yank) has no annotation rows, and pastes as before.
  `gp` adds notes to a column that keeps its own annotations, so it leaves
  them out.
- **`:SongwriterTabChord` and the highlight** use the same lines: a chord
  replaces the column's chord label, else goes on the annotation line closest
  to the strings (the tab making room around it), and
  the time column highlight covers the annotations, converting their display
  columns to the bytes `matchaddpos` wants. Vim 8.2 takes at most 8 positions
  per match, so the highlight is added 8 lines at a time.
- **Reached from the strings, through Vim's grammar** (`tab/annotate.vim`):
  `ia`/`aa` are the annotation word above the cursor's column, so `cia`,
  `dia`, `yia` and `via` work without leaving the string, rather than
  dedicated commands. The tab-mode operators run through `g@` on time columns,
  so the object ends the pending operator and does it on the word itself
  (`operator#Pending` says which). `cia` hands over to Vim's own `c` (or
  `O`/`A`/`i` and padding spaces when there is no word yet): the keys are
  typed rather than the text set first, so the change and what is typed are
  one undo step. When insert mode is left, a `Do` edit joined to that undo
  step retypes the word: a `retype` operation of `annotations#Apply`, from
  the line as it was before the typing (the `annotating` state keeps it),
  so the next word is back where it was and the tab makes room for a label
  as it does for any edit; `dia` is the same operation with nothing typed.
  `.` does not repeat the typed text: Vim does not record what is typed after
  an operator function.
- **`gk`/`gj` keep the column** across short annotation lines and back to the
  string the moves started from, in tab/state.vim (`upward`, valid while the
  buffer is unchanged). With `nowrap`, Vim's own `gk`/`gj` are `k`/`j`, so
  nothing is lost. A context table of `keys.vim`, for annotation lines, gives
  them their meaning there.
- **Display columns.** Annotations may hold any text; tab lines are ASCII, so
  a display column of an annotation is the byte column of the strings under
  it.

### Keeping notes apart

Two chains of a string that touch are one chain: `10` next to `12` is the
fret `1012`, `5h` next to `9` a hammer-on onto the 9, and no lint can tell.
Every edit that removes or inserts columns, or writes a note, can make two
chains meet, so the rule lives in the three primitives those edits go
through, not in each edit:

- **Removing columns** (`columns#DeleteRange`: `dac`, `dd`, `d|`, `x` on a
  lone note, `<<`): where the range was, a dash is put back on every string
  when two chains of a string would meet (`columns#KeepApart`). `x` first
  removes less of a note's gap where another string needs it (6.7.2), so it
  rarely needs the dash.
- **Inserting columns** with content (`paste.vim`, `p`/`P`): `KeepApart` at
  each edge of each copy.
- **Writing a note** (`columns#WriteNote`, and so `SetNote`, `PutNote`,
  carries, chords, `gp`): on dashes, a dash is inserted before it when a
  chain ends right before its column; wider, it keeps a dash before the next
  chain.

Inserting dashes alone (`model#InsertColumns`: slots, `_`, room for a label)
never joins chains; it may split one, which is how a slot opens inside
`5h7` (3.1.3). Check mode (see "Checking the rules") catches any edit that
still makes two notes meet.

These guards replace a time-grid model (the tab parsed into time columns and
rendered back, the only code writing text), considered for the same purpose:
with them, every known way of joining notes is closed in one place each, and
check mode covers the rest on every test, whereas the grid would rewrite the
column code around separators (which belong to no column) for the same
guarantee. The linter moves time
columns as a whole for the same reason (see "Linter").

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

**Separators are kept** (spec 1.5). A note's separators before it are part of
its atom, written right before it wherever it goes, so a pushed note takes
them (`5--h7`); the others (after the last note of a chain, or with no note)
keep their distance from what precedes them. They count for the bar's edges
but not for overlaps between strings, since they occupy no time. Everything else in a
bar (dashes, whitespace) is re-rendered as dashes.

**Empty bar** (no note on any string) becomes `|-----|`: five dashes rather
than the two of a bar edge, so that a slot opened in it is its middle dash and
a note typed there (`|--7--|`) needs no reflow.

**Empty bars at the end are deleted** (spec 1.4): a trailing empty bar is
leftover space, not music. All of them go, not just the very last one, so that
lint stays idempotent (linting twice changes nothing); empty bars between
notes are rests and are kept. A tab keeps at least one bar, so an all-empty tab
lints to `|-----|`, and so does a tab with no bar at all (`e||`, left by
`da|` on the only bar). This applies to every lint, so `cap` leaves a single bar. A cursor that was in a deleted
bar lands on the tab's last pipe.

**Overlapping notes** (spec 1.3, two-digit notes). Each note gets a natural output
offset `c0 - mincol + 2`, then a fixed-point pass enforces:

- *same-string order*: a note keeps its original gap to the previous note on
  its string;
- *cross-string de-overlap*: a note starting strictly after a note on another
  string but inside that note's span is pushed right to leave exactly one dash
  after it, and its whole time column with it: notes starting on the same
  column are aligned and never split, so pushing one note pushes the others
  of its column, and with them what follows on their strings. A single digit
  lining up with the first digit of a `12` is left alone.

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

**Modes, as in Vim.** In the normal state moving never changes the file:
Vim's contract is that motions only move, and a motion that edits puts cursor
moves in the undo history, marks a file modified just by reading it, and fills
the change list. The insert state is for writing: there, moving across notes
opens slots for new ones. It is a state of tablature mode rather than Vim's
own insert mode so that `h`/`l` keep moving (in Vim's insert mode they would be
text, and arrow keys would be needed). The move state (`m`) is for building
chords: keys act on the note under the cursor (see "Carrying notes across
strings").

- **Two kinds of state.** *States* are what the user sees and enters and
  leaves explicitly: normal, insert and move, one at a time, owned by
  `tab/mode.vim` (`Current`, `Enter`, the message each shows) and recorded
  in `tab/state.vim` (see "State and how long it holds"). `keys.vim`
  picks its tables from the current state, each falling back to the normal
  one, so a key's meaning follows from one value and a new state is a table
  and its entry in `mode.vim`. *Continuations* (below) hold only straight
  after an action. The keys typed straight after a note (separators,
  3.4.1.3) are a continuation inside the insert state: its table is checked
  first there.
- **How long a state holds.** The insert state holds until the buffer
  changes (`change`): the edits made in it (opening, filling,
  closing a slot) record it again (`mode#Keep`), and any other change (`u`,
  `x`, an operator) ends it without the other code having to know about it.
  Opening a slot enters it (`slots#Open`), so `a`/`i`, `c`, `o`/`O` and
  `:SongwriterNewTab` all do; leaving it closes the slot (`<Esc>`). The
  state is entered before the slot is recorded: a slot that needed no room
  leaves the buffer unchanged, so the insert state still holds, and entering
  it again closes the open slot, which must be the previous one. The move
  mode holds while the cursor is on a note, edits included (`on-note`). Entering a state
  leaves the current one, so `m` leaves the insert state; a digit run in the
  normal or move state borrows the insert state to open its slot (3.4.1.1) and
  goes back to the state it was typed in. Entering shows the state
  (`-- TAB INSERT --`), after a `redraw` so that repeated changes replace each
  other instead of piling up into a hit-enter prompt; `songwriter#keys#Mode()`
  is there for status lines.
- **Continuations.** Several keys carry on from the last action when pressed
  straight after it: the carry run (3.6.2), the digit being typed (3.4.1),
  `==` cycling voicings or names (10.4, 10.10). "Straight after" has one
  definition, the `continuation` lifetime of `tab/state.vim`: the value
  recorded holds while the buffer is unchanged since and the cursor is where
  the action left it (`edit#Do` records the cursor with every state). Anything else in between,
  a move included, ends it.
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
  it and move on. Where a slot is, is a *position* (`stops#Step`): a column,
  the gap after or before a column (the side it was entered from), an empty
  bar, a new bar. From a slot, the move goes on from its position:
  towards the column it was opened from it lands back on it, away from it it
  goes to the next stop. A slot that is part of a bigger edit (`c`, `o`) has no
  position and goes on to the next stop. So from `3` in `3-5`, `l` `l` `l` gives slot, `5`, slot; each gap
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
  `w`/`b`/`e` (`stops#BarStop`, pure). `W` goes to the first time column of
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
  No anchor note: no-op, not even the lint: `a`/`i` lint first (4.2, below), but
  that lint is part of opening the slot (`edit#Do`'s `open`).
- **Digits (3.4)**: a digit on a dash replaces it; on a note it replaces the
  whole note (both digits of a `12`). To type a two-digit fret, a digit typed
  straight after another is appended to it instead (3.4.1): `EnterNote` records
  the `typing` state after each digit, and the next digit appends only
  while it holds, the cursor and `b:changedtick` unchanged (see
  "Continuations" above). Any move or edit ends the run, so coming back to a note replaces it. The block is then
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

- **Carrying notes (3.6-3.8)**: see "Carrying notes across strings" below.

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
  - *A slot opened by moving, `a`/`i` or a new bar is written back*: closing
    it gives the tab back exactly as it was before, including the lint of 4.2,
    so that wandering in the insert state leaves the tab as it was.
    `slots#Mark`, taken before anything changes, records the block (a
    snapshot) and the cursor column; closing writes the snapshot, joined to
    the slot's undo step (the slot is forgotten on any other change, so that
    step is the last one). The step is left behind, changing nothing, and the
    buffer stays modified. Removing it with `:undo` was tried: it needed the
    undo sequence numbers, a fallback for `:normal` and macros (where several
    keys share one step and `:undo` takes earlier changes with it), and broke
    `undojoin` after it (E790). A plain write is one rule that holds in all
    of them.
  - *A motion closing a slot keeps the lint (4.3.3)*: otherwise walking an
    unlinted tab with `l`/`h` would lint it at every slot and unlint it at
    every close, and the whole tab would jump at each step. `AddNote` and
    `AddBarSlot` record the linted lines in the mark (`slots#Linted`); the
    motions call `slots#Abandon(1)`, which writes the linted lines back
    instead of the snapshot, so that the slot's undo step holds the lint
    alone. `<Esc>` and the
    other closers still give back the tab from before the lint.
  - *A slot that is part of a bigger edit is linted*: `c` (6.6), `o`/`O` (8)
    and `:SongwriterNewTab` (9) open a slot in what they made; `<Esc>` there
    must keep the deletion or the new tab, so closing lints, leaving an empty
    bar as `|-----|`.
- **4.3.1**: a digit typed into a slot, or appended to a fret being typed, is
  joined to the previous undo step (`:undojoin`), so `a7` or `a12` is one undo
  step and `u` gives back the tab as it was before `a`. Straight after an
  undo nothing is joined (`edit.vim`'s `s:join`, the undo tree's current
  sequence not its last): the step to join was undone, or never made (a slot
  that changed nothing), and Vim refuses to join (E790).

**Tabs with no time columns are refused** (spec 4.5). A column is a moment
only once the pipes are aligned and no note starts inside a note of another
string (`model#Timed`). Before that, a column map, which is one map for every
string, cannot say where the music went: the lint's map follows the top
string's pipes, wrong for the others, and check mode could only check each
string's notes in order, so an edit's mistakes there went unseen. Rather than
lint and edit in one key, `edit#Do` refuses such a tab (`edit#Untimed`, a
message pointing to `||`) unless its caller says it takes one (`'untimed'`,
only `||`), and the operators refuse in their lint before `g@`
(`operator#Prelint`, which cancels the pending operator, so its target is
still typed and dropped). Every other edit then sees a tab with time
columns, and its column maps always mean time. A tab that has them but is
not otherwise linted (loose dashes, an unclosed last bar) still lints and
edits in one key: those lints only move whole time columns, which the map
says exactly. So that a refusal is never a surprise, `tab/unlinted.vim`
shows the string names of such tabs in `songwriterUnlinted` (white on red),
window matches recomputed on every change over the whole buffer (a few
short lines per tab, cheap) and replaced only when they move.

**The cursor follows the music** (`lint#FollowColumn`): on a note it stays on
the same digit of that note; elsewhere in a bar it keeps its distance from the
nearest note starting at or before it (any string), clamped before the next
note and inside the bar. Notes before/after the cursor stay before/after it, so
`a`/`i` find the same anchor after the lint as before. `||` lints without
moving the cursor.

`<Esc>` is a context key like the others (`mode#Enter('normal')`). Outside tablature mode `Dispatch`
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
  before `g@` lints the block first, so that the motion is computed on the
  linted tab: a motion on an unlinted tab could reach other notes than the
  user sees it reach once linted. That lint is an undo step of its own
  (spec 6.10): joining it to the operation's would take a changedtick check
  in every path an operator can end in, for a lint that is a no-op on a tab
  being worked on. Refusing operators on unlinted tabs was rejected: a tab
  pasted in or edited outside tablature mode would need `||` first. The
  `<Cmd>` consumes the count, so the count is
  given again after `g@` (`g@3w`). `v:register` is not reliable inside the
  operatorfunc, so the operator, register and "exact target" flag are kept in
  `s:pending`, a script variable since the operatorfunc takes no arguments.
- **One edit per operator.** Each operator on columns or notes (a range, a
  string motion, a note object, across strings) is a pure function of the
  block, `edit#Do`'s Fn, returning one result: its lines, linted (it lints
  them itself, since the cursor goes where the lint leaves things: the next
  note column, 6.11), the register (`register`), the cursor and, for `c`,
  the slot to open (`open`). `Do` sets the register and the cursor; nothing
  in `operator.vim` moves the cursor between steps. A yank is the same
  function with no lines in its result. Line-wise targets are not edits of a
  tab (`dap` deletes buffer lines), except `cap`: each tab is cleared in an
  edit of its own, then a last edit opens the slot (`open` alone) on the
  cursor's tab. An edit stays one block: letting it cover several would
  complicate every edit for `cap` across tabs, which is rare.
- **Spacing is rhythm.** The gap after a note belongs to it: `ac`, a snapped
  motion range and `x` on a lone note remove it with the note, so the
  previous note keeps its length and what follows moves earlier. Rests exist
  only where the user put them with `_`; erasing never creates one, except that
  `x` on a shared column leaves the other strings' timing intact. Other
  strings' music wins over the gap: `x` on a lone note removes only as much
  of its gap as leaves every other string's notes and separators untouched and
  apart (`columns.vim` `s:removable`), since a dash lost between `10` and `12`
  would turn them into `1012`, which no lint can undo; with no room at all the
  note becomes dashes, as on a shared column.
- **Across strings (6.2.4).** `j`/`k` after an operator move across strings,
  so `dj` acts where they go: the time column under the cursor, on the
  strings covered (`operator#Across`, an operator-pending map like the text
  objects). Its notes are erased as `x` erases each (`columns#EraseSet`, which
  `x`, the string motions and the note objects share), so the column goes with
  its gap only when no note is left on it. The register is one column, with
  the strings not erased as dashes (as `in`), rather than `x`'s one column per
  note: the notes were played together and should paste together.
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
  every string, so what follows moves with it; on each string it goes before
  the separators of the column's note, which stay with it (`5h7` -> `5-h7`). Lint keeps two dashes after a
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
  lint: the result's `open`, the side, which `Do` opens on the linted lines.
- **`.`** Operators repeat natively. `g@` records every operator, including a
  yank, so after `ya|` a `.` repeats the yank (native `y` is not repeatable);
  accepted rather than reimplementing redo. `x`, `p`, `P`, `>>`, `<<` are `<Cmd>`
  actions, invisible to redo: they record themselves in `b:songwriter_repeat`
  (`repeat#Record`: a Funcref, its arguments and which one a count
  replaces, so nothing is quoted by hand) with the changedtick they left,
  and the `.` map runs them again while the buffer is unchanged since. The string moves (spec 7)
  record themselves the same way.
- **No counts in front of a command.** Digits enter notes in tablature mode
  (spec 3.4), so `3x` types a 3. Counts work after an operator (`d2ac`, `d3w`)
  and in visual mode, where digits are not mapped. `x` takes no count, not
  even through `.`: erasing several notes is `d3l`, one erasure and one lint.
  The other entry points still take a count.
- **Visual mode.** Text objects show the real (full-height) extent as a
  blockwise selection, and extend when repeated while the selection is still
  theirs; a plain `v` selection is widened at operator time instead, so `v`
  does not move the cursor off its string. `V` is a column selection (the
  common case in a tab), not line-wise: whole tabs are already `dap`/`yap`,
  and the native line-wise selection is one more `V` away (`VV`). `j`/`k`
  are clamped to the tab rather than blocked on a full-height selection, so a
  partial `<C-v>` still grows and shrinks natively.

### Rewriting a note in place (`<C-A>`/`<C-X>`, typing, spec [Tablature][[Editing]] 3.4, 11)

A note's text changes width (`9` -> `10`, `12` -> `5`) while it stays on its
time column. Splicing the new text into its line alone shifts everything after
it on that string by the difference, so the string drifts out of the time
columns it shared with the others (a different rhythm), and lint cannot tell:
it aligns pipes and splits overlaps, but has no memory of which notes were
together. So every edit that writes a note goes through one primitive,
`columns#WriteNote`, whichever key changes its width (`]`/`[`, `<C-A>`, a
digit, a carry keeping the pitch, `<leader>h`/`<leader>l` and the move state's `h`/`l`, a chord's frets):
one rule, so the same change of fret gives the same tab whatever key made it.
`SetNote` rewrites a note in place, `PutNote` writes one on dashes, and a
carry renders its notes with it, as rewriting the note it replaces, or the
one it was lifted from. `test/songwriter_invariants_frets.vader` checks over
the corpus that the notes of each time column still start together
afterwards.

- **Narrower: dashes after it and its separators.** The note keeps its start,
  its separators after it close up with it (`10~` -> `9~-`), and every other
  note keeps its column, those of its chain included: the `h` of `10h7`
  belongs to the 7, so a dash inside the chain (`9-h7`) detaches nothing.
- **Wider: the gap first, then room for everyone.** The dashes after the note
  are used while one stays before its string's next chain (that dash is what
  keeps `10` and `7` two notes) and the note covers no other string's time
  column. What is still missing is inserted on every string between the note
  and the next time column, so all that follows moves together. No dash goes
  before a rewritten note, and its separators right after it are not pushed
  off.
- **On dashes, apart from the chains around it.** A note written where there
  was none (a carry to another string, a chord's fret, a digit or `x` typed
  on a dash) is its own chain: when a note ends right before its column, a
  dash is inserted there on every string, rather than merging the two
  (`123`), which lint cannot undo; one starting right after it is kept apart
  as a wider note's next chain is (`3-5`, `7` on the dash: `3-7-5`). Its
  separators before it may follow a note (`5` and `h7` give `5h7`, each
  note keeping its own separators), not another separator (`5~h7` would give
  the `~` to the 7).
- **Visual `<C-A>` changes every fret selected**, so a riff is moved up the
  neck in one go, rather than Vim's first number per line, which means
  nothing in a tab. The notes change right to left: each one's room or
  closing-up only affects what lies to its right, which is already done.
- **`<C-A>` finds its note as Vim does** (under the cursor or next on the
  line), because that is what the key has always done in the buffer, and the
  cursor stays on the note's start, the column tablature mode works on.

### Carrying notes across strings (spec [Tablature][[Editing]] 3.6-3.8, 7)

`tab/carry.vim`. Moving a note to another string is the edit made most often
while transcribing, so it has right-hand keys (`<leader>k`/`<leader>j`, with a
`<Space>` leader) next to `s`/`S`, and one engine for all of them.

- **One engine: lift, step, render.** A carry lifts notes out of the tab; the
  rest, the *base*, is kept in the carry state (tied to `b:changedtick`, so any
  other edit ends the run). A step moves every carried note the same number of
  strings, or changes their texts (`S` keeps the pitch, `<leader>h`/`<leader>l`
  and the move state's `h`/`l` change the fret), and the tab is rendered again from the base with
  the notes written there. Rendering from the base rather than editing the last
  result is what puts back a note the carried one replaced, with no
  bookkeeping of what was overwritten; when the notes are back where they
  started with their texts, the render is the origin itself, so coming back
  leaves no trace. Back on their strings with other frets, the render is
  checked (check mode) as an edit of the origin, the notes erased there and
  written again, as a fret changed in place: against the base, the 1 of
  `4h1h9` written back would look like a note joining the 4 and the 9.
  Steps after the first are joined to its undo step: a run is
  "the buffer unchanged since the last step and the cursor where it left it".
- **Strings only, never time.** Carries change strings and frets, never time
  columns, so the base keeps every column of the tab: lifting blanks the notes,
  and no column can disappear under a carried note. Moving in time is done
  with delete and put (`dinp` moves a note one column later, `yinp` copies it
  into a new column), which keeps carries simple and `[`/`]` free to change
  frets everywhere.
- **The note, not the chain.** `s`/`S` and `<leader>k`/`<leader>j` carry one
  note, as do column carries (`sK`/`sJ` take the notes starting on the column,
  even the second note of `5h7`), with the separators that belong to it
  (`7~`, `/5`, the `h` of `5h7` with the 7). A note is replaced only when one starts on the
  carried note's time column; anything else in the way (a separator, a wider
  fret covering the column) is no room and refuses the carry.
- **Copies are carries.** `<leader><leader>k`/`j` are a carry whose base is the
  whole tab, note included (`carry#Copy`), started one string away. Rendering
  the copy over that base never touches the original, and carrying the copy
  back onto it renders the tab as it was. One more `<leader>` means "copy
  instead of carry", inside the move state as outside it.
- **The move state (`m`).** Building a chord is copy, set the fret, copy again:
  many steps in a row, so they get keys without a leader. `m` enters the state
  and `m` leaves it (also `<Esc>`); it is a state of tablature mode
  (`tab/mode.vim`, its keys in `s:moving`), and it holds while the cursor is
  on a note, so it needs no bookkeeping of edits: `[`/`]`, typing a fret or
  `w` keep it, and a `CursorMoved`/`TextChanged` autocmd (`mode#Check`)
  clears its message once the cursor is off the notes. A message alone is
  easy to miss, so the time column band takes another color there
  (`songwriterMoveColumn`, `Search` by default: a background colour in nearly
  every color scheme), the same window match with another group
  (`tab/highlight.vim`); `mode#Enter` refreshes it, since entering or leaving
  the state moves nothing. Coloring only the note under the cursor does not
  work: the block cursor covers it. The cursor's own colour is left alone:
  terminals do not reliably let a plugin change it. There, `h`/`l` change the fret as a step of the run (a
  replaced note still comes back), unlike `[`/`]`, which are their own edit.
  Off a note, `m` is Vim's mark command. There is no exit on a lone
  `<leader>`: it would make Vim wait 'timeoutlen' after every leader key.
- **Visual carries** step the notes the selection touches (the spans of
  visual `<C-A>`, `selection.vim`) and select the same part of the tab again,
  its ends moved one string and followed through the render and the lint, so
  pressing again goes on in the run.
- **Keys.** `s` keeps the fret, `S` keeps the pitch; then `k`/`j` the note,
  `K`/`J` its time column. `J`/`K` alone are left to the user outside the move
  state. Native `s` edits one string only, which tablature mode already rules
  out (spec 6). `S` is therefore not `cac` (spec 6.8): a lone `S` would wait
  for 'timeoutlen' to rule out `Sk`, and `cc` already does it. No count:
  digits enter notes (spec 6.12), and carrying one string at a time, in runs,
  is what is needed.
- **Pitch from the string names.** The interval between two neighbouring
  strings is the difference of their pitch classes, modulo 12
  (`tuning#Interval`).
  This assumes strings listed from the highest to the lowest and less than an
  octave apart, which covers standard and drop tunings, basses and 7-strings.
  String names are one letter, so an evenly lowered tuning (E flat standard
  written `eBGDAE`) has the same intervals and works. Two strings with the same
  letter (`E` above `e`) give no interval and the carry is refused, rather
  than guessing an octave.
- **Room, not overlap.** A carried note is written as any note that changes
  width (`columns#WriteNote`, see "Rewriting a note in place"): a wider one
  takes the gap or gets dashes inserted on every string, a narrower one closes
  up with its separators, and on another string it keeps apart from a note
  ending right before it. A note it lands on is rewritten in place, keeping
  its separators (`5h12` -> `5h7`), unless the carried note has separators
  before it, which take their place. Rendering from the base keeps all of it undoable: the
  room exists only in the render.

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
  A power chord is three strings and computes well from the intervals between
  them, as `S` does (`tuning#Interval`, spec 7.3), so drop D gets its
  one-finger shape for free.
- **The chord replaces the column**, as a digit replaces a note: the notes
  starting on it go, and a two-digit fret gets room as a moved note does
  (`columns#PutNote`, spec 11.2). Unplayed strings stay dashes: muting marks are
  the user's call (`x`).
- **A quality alone changes the chord there** (10.7). The root is the note on
  the lowest string of the column: no chord recognition, so it works on any
  column, a single note included, and is right for every root-position
  voicing this module writes. Keeping the root's fret when a voicing has it
  keeps the chord where it was on the neck. A name is a quality when it is not
  a chord but `C` + it is, which separates `b` (B) from `m7` without a list.
- **`+` reads the column, not a remembered state** (10.8). Power, major,
  minor is the order a riff grows in, and checking which of them the column
  holds (exactly, rooted on the cursor's note) lets `+` go on from a chord
  typed with `=` or entered long before, with no state to keep in sync with
  edits. Unlike 10.7 the root is the cursor's note and must stay so: the chord
  must be rooted on that string at that fret, or `+` is refused, so the next
  `+` still finds its root under the cursor. Minor is the end: a third quality
  would have to be chosen arbitrarily, and `=` covers the rest.
- **The name and the notes are two views of one chord.** Whatever writes a
  chord by name (`=Am`, `=m7`) writes its label too, so they never disagree;
  `+` builds riffs note by note, where labels would be clutter, so it only
  keeps an existing label true. The label is a `label` operation of the
  draft: `edit#Derive` writes it after the annotations followed the edit, so
  it lands on the chord's column wherever the lint put it, and in the same
  undo step. That operation is the one way a chord name is written
  (`=`, `+`, `=<CR>`, `:SongwriterTabChord`): `annotations#Apply` replaces
  the column's chord label (a label starting on the column that is a chord),
  else places the name as spec 6 says.
- **A chord name makes room in the tab, not on a new line.** A name too wide
  for its gap (`Am7` over `0-3` with a `C` above the 3) is the general case
  of a label that would be pushed (see Annotations): the tab widens, so a
  progression stays on one line. A new line is only for a name with a word in
  the way that no widening moves (one over the column or starting over its
  notes).
- **A label is spelled as `=?` would name it.** `M7`, `min` or `sus`
  are convenient to type, but the names `chord#Identify` gives are `maj7`,
  `m`, `sus4`, so `voicings#Spelled` writes each quality as `s:qualities`
  canonicalises it (`maj` dropped) in the label and the message. The table
  that decides which voicing a spelling means also decides how it is written,
  so the two cannot drift. It is applied where the voicing is placed, not
  where the name is read, so `=M7`, `=EM7` and a `CM7` label all come out the
  same; `:SongwriterTabChord` spells its chord the same way.
- **`=<CR>` is "the other view".** With no name typed, `=` takes the chord from
  where the cursor is: on a string, the name from the notes (`chordname.vim`,
  `==` cycling the names `=?` lists, kept in state `naming`); on a
  label, the voicing from the name. One key both ways, and `==` always cycles
  what was just written.
- **From a label: lowest on the neck, unlinted.** There is no cursor string to
  root on, so the voicing is the lowest root fret (open shapes first), and
  `==` goes on in the 10.4 order from its string. It is the usual `=` edit
  (`s:place`) told to root on that string at the label's column, the cursor
  staying on the label (`edit#Do` follows it there), so the whole of
  `edit#Do` (slot, undo, state) is reused. It does not lint:
  a progression typed over empty bars would lose the columns of the labels
  still to fill as the bars closed up. `.` on the annotation line repeats it
  (`repeat#Record`), so a progression is `=<CR>` then `w.` per chord.
- **Typing on.** In the insert state a chord counts as a typed note
  (`typing.chord`): a digit after it opens the next slot even when it would
  extend the root's fret (`1` then `2` is not `12`), and separators are not
  typed after it.

### Naming a column's chord (`=?<CR>`, spec [Tablature][[Editing]] 13)

- **Computed from pitches, not looked up in the shapes.** The column's notes
  become MIDI pitches through the string names (`tuning#Of`, as for
  playing), so any tuning and any fingering is named, not only the CAGED
  voicings `=` writes. Matching the shapes first would add nothing: every
  shape is a root-position chord whose notes are exactly its quality's, so it
  is already the first name. Naming offline also keeps the plugin free of any
  network dependency.
- **Exact pitch-class sets, every root tried.** A chord fits when the
  column's pitch classes, seen from one of them, are exactly a quality's
  intervals; the fifth alone may be missing, and only from qualities where it
  says nothing (not `5`, `6`, `sus`, `dim`, `aug`), so `C E A` is `Am/C`, not
  also a fifthless `C6`. Every fitting chord is listed, since the same notes
  are often two chords (`C6`, `Am7/C`) and only the player knows which is
  meant. The one on the bass comes first; the rest go up from the bass.
- **Rare qualities as a fallback.** `addb9`, `maddb9` and `13` name voicings
  nothing common fits (`x6897x`), but checked alongside the others they
  would add a second, unlikely reading to ordinary chords (`C C# E` would be
  `Caddb9` too). So they are a second table, tried only when the first finds
  nothing. A quality lists the intervals it may drop (`opt`): the fifth for
  most, the fifth and ninth for `13`.
- **Read-only**, like playing: no lint, no undo step. The pure part is
  `chord#Identify` (pitches to names), independent of tabs, and
  `chordname#Message` (lines to message).
- **On `=`, beside the other chord keys.** `=Am` writes a chord, `=<CR>`
  writes the column's name, `=?` asks for it: one prefix for everything about
  the column's chord, with no leader key to learn. `?` is never a chord or a
  quality, so `voicings#Enter` takes it before anything else. It follows `=`
  into tablature mode only (outside it `=` is Vim's); `<Plug>(songwriter-chord-name)`
  is kept, unmapped, for those who want it there.

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

### Time column highlight ([[Rendering]] 4)

Column-wise operations act on the notes starting on the cursor's column, on
every string, which the cursor alone does not show. `tab/highlight.vim` keeps
window matches (`matchaddpos`, group `songwriterTimeColumn`, linked by default
to `CursorColumn`) on that column, on every string of the tab and its
annotation lines, notes and dashes alike, as wide as its widest note: a full-height band shows the column
as one thing, and which strings are silent on it, where highlighting only its
notes would leave scattered cells. The note under the cursor decides the
column, so a cursor on the `2` of `12` still shows that note's column. On a
gap where no note starts, nothing is highlighted.
Buffer-local autocommands update it on every cursor move and text change,
and clear it when the window loses focus or shows another buffer (a window
match would otherwise stay on that buffer). Reading the block on each move is
cheap (a few short lines); the match is replaced only when the column
changes.

### Playing notes (`<leader>p`, spec [Tablature][[Editing]] 12)

- **An operator, not a set of keys.** Playing reuses the d/y/c machinery
  (`g@`, `s:pending`, the text objects, string motions, `j`/`k`, visual
  selections), so every target that can be yanked can be heard, and what is
  played is what `y` would reach. `play` is one more op in `ApplyRange`,
  `s:across` and `ApplyLines`, which branch before any edit; `Start` skips
  the pre-lint, so playing never changes the file (an invariant checks it).
  The doubled form is `<leader>pp` (the `p` operator-pending key), and
  `<leader>P` is `<leader>pin`, since one note is the most common case.
- **No dependencies but a player.** Vim has no portable audio (`+sound` is
  Linux-only and rarely built), so the plugin writes WAV files and starts a
  player command as a job: `afplay` ships with macOS, `paplay`/`aplay` with
  most Linux desktops. Windows is not supported. With no player the feature
  is inert; nothing else depends on it.
- **Karplus-Strong synthesis in Vim script.** A delay line of noise through
  a damping lowpass sounds like a plucked string and is a few lines of code.
  A first-order allpass, tuned for the note's frequency, covers the fraction
  of a sample in the period (rounding alone makes high frets tens of cents
  sharp), and the damping is set per pitch so notes die away in a guitar-like
  time (`s:t60`) instead of high notes vanishing at once. The noise is seeded
  by the pitch, so a pitch always gives the same file.
- **Cached per pitch.** A guitar spans about 50 pitches; each is generated
  once (1.2 s at 22.05 kHz) and kept in the cache directory, named with a
  synthesis version (`pluck1-…`) so a change to the synthesis makes new
  files. On Vim 9 the sample loop is compiled Vim9 script (`sound9.vim`),
  about 25 times faster than legacy script (a whole tab's first play: 0.2 s
  rather than 3 s); Vim 8.2 and Neovim use the legacy loop. A test checks
  both give the same bytes.
- **Timing with timers, mixing by the OS.** Each note is its own player job,
  started by a timer at its step (a beat at `g:songwriter_play_bpm`) plus
  a strum delay per string (80 ms by default, so each note of a chord is
  heard distinctly), so no mixing code is needed. The strum does not push
  the next column back: steps stay evenly spaced, and at fast tempos a wide
  chord's last notes may overlap the next column (a six-string strum takes
  400 ms of a 600 ms beat at 100 bpm). A note stops the
  previous job on its string (a string sounds one note at a time), and a new
  play stops everything first. Spacing is not read as rhythm: it is only a
  loose indication (spec 6), so every column gets the same length.
- **Pitches from the string names** (`tuning#Of`), as the `S` moves read
  them (7.3), with
  the lowest string in [B1, A#2]: right for six- and seven-string guitars
  and drop tunings; a bass sounds an octave up, which is acceptable for
  checking notes by ear.
- **Testing.** Tests set `g:songwriter_player = []` (sound off) and read
  what would have played with `songwriter#sound#Last()`; the synthesis and
  the schedule are pure functions.

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
`unsigned` for that call, since a dash before a fret is not a minus sign. In
tablature mode a tab line goes to `tab/frets.vim` instead (see "Rewriting a
note in place"): Vim's increment splices one line and would shift that
string's later notes off their time columns.
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

- Vader, `make test`; the pre-commit hook enforces a green suite. Each test
  file runs in its own Vim, in parallel (`JOBS`, one per CPU by default), so
  a slow file holds the whole run: keep files under a second or so, and
  split one that grows past that.
- Buffer transformations use `Given songwriter` / `Execute` or `Do` / `Expect`,
  so the before/after tab is visible; cursor positions and pure functions use
  `Assert*`.
- Vader reuses one buffer across the cases of a file, so buffer state (the
  tablature-mode flag) is reset in a `Before:` block wherever keys are typed.
- **Spec references** (`test/songwriter_spec_refs.vader`): every `spec
  [Section][[Sub]] n.n` in a comment under `autoload/`, `plugin/`,
  `ftplugin/` and `syntax/` must exist in specification.song.txt. A bare
  number counts only after a qualified reference in its comment block or the
  file's header comment; the rule is written at the top of the test.
- Key mappings are exercised end-to-end with `normal` where the result is
  observable; `Dispatch` and `b:undo_ftplugin` have their own tests. The
  actions of the key tables are strings, so a test checks that every function
  they call exists (`keys#Actions`): a misspelt name fails the suite rather
  than the key.
- **Check mode** (`g:songwriter_check`, see "Checking the rules"): every
  test runs with it, so every case checks the rules of the music on every
  edit it makes, not only the tab it expects.
- **Invariants** (`test/songwriter_invariants_*.vader`) are checked over a corpus
  of tabs and every relevant cursor position rather than one example: lint is
  idempotent and keeps each string's notes, the normal state never edits, an
  abandoned slot gives the tab back in one undo step, a carried-back note leaves no trace, each edit is one
  undo step and leaves the tab linted, a rewritten note leaves every note on
  its time column, a pure edit's map puts every note it did not rewrite
  where it now is, and a label above a time column stays above the notes it
  was above. They catch the interactions between
  features that hand-written cases miss. The main corpus is linted, so an
  edit's own lint shows no difference; unlinted tabs go only where the
  invariant must hold for them too (lint, 4.3, the refusal of 4.5). Keys are typed with
  `feedkeys(…, 'xt')` under `silent!` (one undo step per key sequence, and
  no hit-enter prompt reading stdin). An edit throwing in check mode is
  recorded as a failure of its case (`InvType`). A case that breaks an invariant
  because of a bug in the spec's [[Bugs]] is listed as a known exception,
  which must keep failing: fixing the bug means removing it from the list.
  Positions are limited to note starts and the dash after each note, and
  the corpus kept small. The corpus and helpers are in
  `test/invariants/setup.vader`, which each invariant file includes; the
  edit invariant is one body (`test/invariants/edits.vader`) included by
  files that each check a share of the keys, so that they run in parallel.
- **Fuzzing** (`test/songwriter_invariants_fuzz*.vader`, one body in
  `test/invariants/fuzz.vader`) walks the corpus (unlinted tabs and a tab
  with annotation lines included) with seeded random keys drawn from the
  tables of `keys.vim` (`keys#Tables`), those of where the cursor is (the
  state of tablature mode, the separators straight after a typed note, the
  annotation lines), an operator completed by a key of the operator-pending
  table, a selection by keys of the visual table, `=` by a chord name. A key
  added to a table is fuzzed with no new test, and bugs needing two features
  together are found by the suite. After every key, only what holds after
  any key: no error (check mode's or Vim's: keys are typed under `silent`,
  not `silent!`, which would carry on past an error and show only its
  aftermath), every line a tab line, an annotation line or blank, the tab
  around the cursor with time columns; after the walk, undo gives the tab
  back. Each walk starts afresh (registers, buffer states, undo history), so
  a failure is reported with its seed, tab, start and keys, and shrunk to the
  fewest keys that fail the same way. A failure of a bug in the spec's
  [[Bugs]] is recognised by its failing key and message, and logged rather
  than failed. `make test` runs one fixed seed; `make fuzz` runs more
  (`FUZZ_SEEDS`, `FUZZ_LENGTH`, `FUZZ_SEED` to replay one).
