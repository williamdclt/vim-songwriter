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
the per-feature tests: run `make test` after every step. Entries 1 and 4 make
that net much wider, which is why they come first.

The one weakness behind most of these: a tab is edited as raw text, and the
rules of the music (the notes of a time column start together; two chains of
a string never join into one; a string keeps its notes in order) are guarded
by each primitive on its own. `columns#WriteNote` (`s:splits`, `s:in_chain`)
and `columns#EraseNote` (`s:removable`) guard them; `columns#DeleteRange`,
the row insertion of `paste.vim` and `paste#Overlay` do not, and lint pushes
single notes. Every bug in the spec's [[Bugs]] is one of these gaps. The
entries below first make a broken rule fail loudly anywhere (1, 4), then make
it impossible by construction (5).

## 1. Check the rules of the music inside `edit#Do`

**Now.** The invariant tests check the rules over a corpus of tabs and
cursor positions. The ~1000 per-feature cases check only the tab they
expect, so an edit that joins two chains on a string no case looks at goes
unnoticed (`gp` next to a two-digit fret, [[Bugs]] 4, was found by hand).

**Change.** Behind a flag set by the test setup (`g:songwriter_check`),
`edit#Do` checks every draft it writes against the block it started from,
through the draft's column map: every note it did not rewrite is still a
note with the same text where the map puts it; notes that started together
still do; no chain holds two notes that were in different chains; once
linted, the pipes are aligned. A broken rule throws, naming the edit. The
edits that rewrite notes (a typed digit, `]`, a carry, a chord) say which,
so the check knows what may change. The [[Bugs]] cases stay known
exceptions, as in the invariant tests. The lint's fixed point (200 passes)
and `s:make_room` (100) also throw in check mode when they hit their cap,
rather than stopping silently.

**Buys.** Every existing test case checks the rules, for free, and so does
every case written for a new feature.

## 2. Tuning and options in one place each

**Now.** String names become pitches in three places: `carry.vim`
(`s:interval`, for `S`), `play#OpenPitches` (also used by `chordname.vim`,
so naming a chord depends on the module that plays sound) and
`voicings.vim` (pitch classes per string, the standard-tuning check, power
chords). `g:songwriter_max_fret` and its default of 24 are read in
`typing.vim`, `frets.vim` and `carry.vim`; the other options
(`songwriter_play_bpm`, `songwriter_strum_ms`, `songwriter_player`,
`songwriter_sound_cache`) each have their default where they are read.

**Change.** A pure `tuning.vim`: the tuning of string names, `{'pitches'
(open string pitches, spec 12.3), 'standard'}` or `{'error'}` (a name that
is not a note), and the interval between two strings (7.3, refusing the
same letter twice). Carries, playing, naming and voicings use it. A
`config.vim` with one table of options and their defaults, read through
one function.

**Buys.** One rule for what a string name means, so a new tuning feature
(capo, alternate tunings for `=`) is one change; one place to find every
option.

## 4. Fuzz the key tables

**Now.** The invariant tests press a fixed list of keys at fixed positions.
Interactions between keys (a carry after a paste in the insert state) are
only tested when someone thinks of them.

**Change.** An invariant file that walks the corpus with a seeded random
sequence of keys drawn from the tables of `keys.vim` (every mode of
tablature mode, the annotation lines), with the check of 1 on, and reports
the seed and the keys of a failing sequence. The seed is fixed in `make
test` so the suite stays deterministic; a `make fuzz` target runs more
seeds.

**Buys.** A key added to a table is fuzzed with no new test, and bugs that
need two features together are found by the suite rather than by use.

## 5. A time-grid model: the rules of the music by construction

**Now.** See the top of this file: each primitive keeps chains apart and
time columns together on its own, and those that do not are the known bugs.
Pure functions also re-scan raw lines (`model#Notes`, `NoteAt`, `ChainAt`
are called on raw lines in 14 modules) and re-parse whole blocks inside
helpers (`WriteNote` to find the next time column, `EraseSet` once per
note), against AGENTS.md.

**Change.** A tab is parsed into bars, each a list of time columns (the
notes starting there, one per string, and the gap after the column on each
string, separators included, at their distance from what precedes them),
and rendered back. Rendering is the only code that writes a tab's text: it
puts each column at its position, widening the gap before it on every
string wherever a string would join two chains, so no edit can join or
split them. The column map comes from the render. Edits work on the grid
(insert, delete, rewrite a column or a note) and pure functions take and
return parsed tabs.

In steps, each with the suite green:

1. Lint as parse, then render. The fixed point pushes a time column, not a
   note, which fixes [[Bugs]] 3 (a behaviour change, already decided by the
   spec). Lint's idempotence and note-keeping invariants are its oracle.
2. Column deletion (`columns#DeleteRange`, `x` on a lone column) on the
   grid: fixes [[Bugs]] 1.
3. Pasting and overlaying (`paste.vim`) on the grid: fixes [[Bugs]] 2 and 4.
4. `WriteNote`, the slots and the carry's render on the grid; the guards
   (`s:splits`, `s:in_chain`, `s:removable`) go.

**Open questions.** Where a separator goes when the gap it is in shrinks,
and whether `_`, `:SongwriterAddBar` and `:SongwriterAddDashes` outside
tablature mode (which keep an unlinted tab as it is) stay text edits. If
step 1 shows the grid cannot keep unlinted tabs as they are where the spec
needs it, the fallback is one guarded insertion primitive and one guarded
removal primitive that every edit goes through, fixing the same bugs
without the model.

**Buys.** A new edit cannot break the rules of the music, rather than
having to know which guards to call; the known bugs go with the code that
had them.

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
re-typed after `g@` go. In check mode (1), `Do` throws on a result key or
option it does not know. Cursor columns are display columns everywhere (on
a string, the same as bytes, tab lines being ASCII).

**Behaviour, to check with the user.** With the lint inside the operator,
a motion is computed on the tab before the lint and its range followed
through it, rather than computed on the linted tab: `dw` on an unlinted tab
may reach differently. A `c` that opens no slot in a lint would no longer
leave an undo step of its own.

**Buys.** Operators read like every other edit; one undo step per operator
by construction instead of by joining; one unit for the cursor.

## 7. Spec references checked

**Now.** Comments reference the spec by number (AGENTS.md), and renumbering
it means finding them by hand; many say only `spec 4.3`, which exists in
more than one section.

**Change.** A test reads every `spec [Section][[Subsection]] n.n` reference
in `autoload/` and checks it exists in specification.song.txt; a bare
number is accepted only after a qualified reference in the same comment
block.

**Buys.** Renumbering the spec cannot leave stale references behind.

## 8. Later: the same layer for chords over lyrics

**Now.** `[Chord annotations]` (chords above lyrics) has editing features to
come, and `:SongwriterChordAbove` places a chord by hand.

**Change.** Annotations are anchored words with one layout and one set of
operations (`annotations#Apply`, `Render`, `Room`), whose only tie to tabs is
where the anchors come from and how room is made. Anchor them to character
positions of a lyric line instead (room made by spaces in the lyric, or not
at all) to give chords over lyrics the same following and room-making. With
the grid of 5, a tab's anchors are its time columns; a lyric line's would be
its characters.

**Buys.** One annotation engine for both formats instead of a second one.
