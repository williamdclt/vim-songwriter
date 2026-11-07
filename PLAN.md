# Goal

Extract the reusable abstractions from the monolithic `plugin/songwriter.vim` so
new features (chord-annotation editing, insert-frets, etc.) are cheap to add,
without changing any existing behaviour.

# Assumptions

- These are **pure refactors**: the 50-assertion Vader suite is the behaviour
  oracle and must stay green after every step.
- Steps 1–4 stay in `plugin/songwriter.vim` and keep the public `Songwriter*`
  function names, so existing tests and mappings are untouched.
- Step 5 splits implementation into `autoload/songwriter/{util,tab,chord}.vim`
  and keeps thin global `Songwriter*()` wrappers in `plugin/songwriter.vim`, so
  the public API (and the tests that call it) is stable. Tests are not edited.
- The tab-line pattern `^\a[|]` is the design-documented one; step 1 unifies the
  3 differing definitions to it (`ftplugin` used the narrower `[eEaAdDgGbB]`).
  All test inputs (`e|…`, prose) match both, so motion tests are unaffected.
- Spec `[Editing] 3` ("press a number replaces the dash") is NOT implemented;
  step 2's `InsertCharAtCol` makes it a one-liner later. Out of scope here.

# Steps

- [x] 1. Introduce `s:TabLinePat` + `s:find_tab_block()` and rewrite
      `AddDashes/AddDash/AddBar/Lint/TabChord` to use it; unify `ftplugin`'s
      tab-line check to the same pattern — check: `make test` (50/50).
- [ ] 2. Add `s:insert_char_at_col(char)`; make `SongwriterAddDash`/
      `SongwriterAddBar` thin wrappers over it — check: `make test`.
- [ ] 3. Centralize chord handling: `s:Chromatic`/`s:FlatToSharp`/`s:RootPat`
      constants, `s:chord_parse()`, `s:chord_transpose()`, `s:chord_build()`,
      `s:splice_chord()`; rewrite the 5 chord functions over them — check:
      `make test`.
- [ ] 4. Decompose `s:lint_block` into `s:parse_tab_lines()`,
      `s:relax_bar()`, `s:render_bar()` (same algorithm, documented model) —
      check: `make test`.
- [ ] 5. Split into `autoload/songwriter/{util,tab,chord}.vim`; keep global
      wrappers + `:command`s in `plugin/songwriter.vim`; `ftplugin` calls the
      unified util — check: `make test`.

# Done when

- `make test` is 50/50 after each committable step.
- Each design decision is recorded in `design.md`.
- One commit per completed step.
