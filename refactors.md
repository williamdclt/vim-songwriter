# Refactors

Planned architecture changes, in the order they are meant to be done. Each
entry says what is wrong now, what to change, and what it buys. Unlike
design.md, this file describes work not done yet: when a refactor lands,
delete its entry here and record the resulting design in design.md. Refactors
must not change behaviour (AGENTS.md); where one would, it says so, and the
change is checked with the user first. Such changes are welcome when they make
the implementation simpler: complex code is often the sign of an illogical or
inconsistent behaviour, so an entry points out where behaviour could be made
more regular, as a question for the user.

The safety net for all of them is `test/songwriter_invariants_*.vader`, on top of
the per-feature tests: run `make test` after every step.

## 2. The states of tablature mode, in one place

**Now.** The state of tablature mode is spread out: `b:songwriter_tabmode`,
`b:songwriter_moving` (not tied to the buffer version, ended by its own
autocommand, carry#Check), the insert state (tied to changedtick), the typed
digit, the open slot, the carry run, and the `annotating`, `naming`,
`voicing` and `upward` states. keys#Dispatch tests them in a fixed order, and
keys#Mode() repeats that order. carry#StartMove leaves the insert state
itself, and the move state shows its message with insert#Show.

**Change.** Tell apart two kinds of state:
- **modes**, which the user sees and enters and leaves explicitly: normal,
  insert and move. One module (tab/mode.vim) owns the current mode, with an
  enter and leave hook per mode and the message each shows. keys.vim picks its
  table from the mode.
- **continuations**, valid only while nothing else has happened (`state#Continuing`): the carry
  run, the typed digit, the slot, cycling voicings, `.`.

**Behaviour.** Which key wins when several states apply must stay as it is,
unless the user agrees otherwise. Questions for the user: should the move
state end on any change it did not make, like the insert state, rather than
only when the cursor leaves the notes? Should the typed-digit keys be a state
of the insert mode rather than a separate layer?

**Buys.** A key's meaning follows from one value; a new mode is a table and
two hooks.

## 3. One way to write an edit, visual mode included

**Now.** edit#Do is the pipeline for an edit at the cursor, but there are
four other ways to write one (edit#Commit, edit#Apply, edit#Write,
edit#LintAndFollow), and several entry points lint, compose column maps,
`undojoin` and write by hand: carry#Visual (which repeats carry.vim's
`s:result`), frets#IncrementIn, the operator ranges, tab.vim, annotate.vim.
Undo steps are joined in three places. Do itself has grown to 11 result keys
and 8 options.

**Change.** Split Do into stages: prepare (slot, first lint), run the pure
edit, write (lint, column map, undo step), then the follow-ups (state,
register, opening a slot, `.`, the insert state), each follow-up a small
function rather than a branch of Do. The target is the cursor or a
selection: a visual edit hands over its selection (selection.vim), which the
pipeline maps through the edit's column map and selects again. Every entry
point goes through it; `undojoin` lives only there.

**Buys.** carry#Visual becomes a few lines, visual `<C-A>` stops being a
special case, and every edit lints, maps annotations and joins undo steps the
same way.

## 4. A note and the separators that belong to it, in the model

**Now.** Rule 3.1.3 (the separators of a chain with no note beyond them
belong to the note at that end) is implemented twice: carry.vim's `s:note`
and slots.vim's `s:loose_separators`. columns#EraseNote decides what to
remove around a note with a rule of its own (`s:removable`).

**Change.** `model#NoteSpan(line, note)`: {'col', 'pre', 'text', 'post'},
the note with the separators that belong to it. carry.vim and slots.vim use
it.

**Behaviour.** Question for the user: should erasing a note (`x`) also take
the separators that belong to it, as carrying does, so that the three agree?

## 5. One way to change a fret

**Now.** `]`/`[` and `<C-A>`/`<C-X>` change a fret with frets#Add, which makes
room for a wider fret by spec 11.2 (columns#SetNote). In the move state,
`h`/`l` change it as a carry step, which makes room by 7.5
(columns#PutNote). The two can differ when the wider fret runs into another
string's column.

**Behaviour.** Decided with the user: one rule for a note that gets wider,
wherever it gets wider (`]`/`[`, `<C-A>`/`<C-X>`, a carry keeping the pitch,
the move state's `h`/`l`). The proposal is 11.2's, the more precise of the
two: take a dash of the gap after the note while one stays before the next
note on its string and it covers no other string's time column, otherwise
insert dashes on every string right after it. 7.5 then refers to 11.2. To
settle with the user before implementing: whether a note that gets narrower
in a carry also closes up its chain as 11.2 says (a carried note is rendered
on the base, so today it just leaves dashes).

**Change.** One pure function makes room for a note's new text (where
columns#SetNote and columns#PutNote now disagree); frets#Add and
carry#Render both use it. The move state can keep changing the fret as a
carry step, so the run and its exact restore are unchanged.

**Buys.** One rule for making room, one function.

## 6. Split operator.vim

**Now.** operator.vim (550 lines) holds the operator machinery (`g@`,
motions, text objects, ranges) and actions that are not operators: `x`,
`p`/`P`, `>>`/`<<`, `gp`.

**Change.** Move the actions that are not operators to tab/actions.vim.
Mechanical.

## 7. One shape for refusals

**Now.** Pure functions return a refusal as {'error'}, except some that return
a list or an error dict (carry#Notes), which the caller tells apart by type.
The `'songwriter: '` prefix is added by hand in about a dozen places.

**Change.** Every pure function that can refuse returns a dict, with 'error'
on a refusal; edit#Error adds the prefix.

## 8. Check the key tables

**Now.** Every action in keys.vim is a string, so a misspelt function only
shows when its key is pressed.

**Change.** A Vader test that reads every action of every table and asserts
that its function exists (after sourcing its autoload file).

## 9. `.` records a function and its arguments

**Now.** An action records itself for `.` as a printf format string
(`'songwriter#tab#carry#Carry(%s, %d, %d, %d)'`), with the quoting done by
hand.

**Change.** Record a Funcref and its arguments (and which argument the count
replaces); repeat#Repeat calls it.
