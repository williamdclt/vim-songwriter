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
