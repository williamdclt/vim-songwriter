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
