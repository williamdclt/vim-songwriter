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

## 8. Later: the same layer for chords over lyrics

**Now.** `[Chord annotations]` (chords above lyrics) has editing features to
come, and `:SongwriterChordAbove` places a chord by hand.

**Change.** Annotations are anchored words with one layout and one set of
operations (`annotations#Apply`, `Render`, `Room`), whose only tie to tabs is
where the anchors come from and how room is made. Anchor them to character
positions of a lyric line instead (room made by spaces in the lyric, or not
at all) to give chords over lyrics the same following and room-making. A tab's
anchors are its time columns; a lyric line's would be its characters.

**Buys.** One annotation engine for both formats instead of a second one.
