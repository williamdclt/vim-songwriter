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
the per-feature tests, and check mode (design.md "Checking the rules"), which
checks the rules of the music on every edit of every test: run `make test`
after every step.

## 4. Fuzz the key tables

**Now.** The invariant tests press a fixed list of keys at fixed positions.
Interactions between keys (a carry after a paste in the insert state) are
only tested when someone thinks of them.

**Change.** An invariant file that walks the corpus with a seeded random
sequence of keys drawn from the tables of `keys.vim` (every mode of
tablature mode, the annotation lines), with check mode on, and reports
the seed and the keys of a failing sequence. The seed is fixed in `make
test` so the suite stays deterministic; a `make fuzz` target runs more
seeds.

**Buys.** A key added to a table is fuzzed with no new test, and bugs that
need two features together are found by the suite rather than by use.

## 6. Operators as one edit each

**Now.** `operator.vim` goes around `edit#Do`'s result: it sets registers
itself (`s:set_register`), moves the cursor with `cursor()` between steps,
and `c` is two edits (`s:commit`, then `slots#OpenHere`), joined only
because they run in the same command. The first lint is a separate `<Cmd>`
before `g@`, whose undo step the operation joins (`s:join`, the tick in
`s:pending`, `edit#JoinUndo`), and which consumes the count, so it is typed
again after `g@` (`g@3w`). Results take 13 optional keys and `Do` 9
options, none checked, and the cursor column is a byte column on a string
but a display column on an annotation line (told apart by the sign of
`lin`).

**Change.** Each operator is one pure function returning lines, map,
register and the side of the slot to open (a result key, so `c` is one
edit); the cursor and the register are set by `Do` only. The first lint
moves inside the operator function, the marks of `g@` following it through
the lint's column map, so the separate `<Cmd>`, `s:join` and the count
re-typed after `g@` go. In check mode, `Do` throws on a result key or
option it does not know. Cursor columns are display columns everywhere (on
a string, the same as bytes, tab lines being ASCII).

**Behaviour, to check with the user.** With the lint inside the operator,
a motion is computed on the tab before the lint and its range followed
through it, rather than computed on the linted tab: `dw` on an unlinted tab
may reach differently. A `c` that opens no slot in a lint would no longer
leave an undo step of its own.

**Buys.** Operators read like every other edit; one undo step per operator
by construction instead of by joining; one unit for the cursor.

## 8. Later: chords over lyrics on the annotation layer

**Now.** The annotation layer takes a host (design.md "Annotations"), with
one host, the tab. `[Chord annotations]` (chords above lyrics) has editing
features to come, not specified yet, and `:SongwriterChordAbove` places a
chord by hand.

**Change.** Once those features are specified: a lyric host (anchored to the
lyric line's characters, words from column 1, room made by spaces in the
lyric or not at all), the edits of a lyric line giving column maps as the
tab's do, and the layer moved out of `tab/` (`autoload/songwriter/
annotations.vim`), since it is no longer about tabs.

**Buys.** One annotation engine for both formats instead of a second one.
