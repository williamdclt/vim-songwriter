# Agent instructions

## Context
- Read README.md, specification.song.txt and design.md for context.

## Workflow
- Always work in a dedicated git worktree (under `.worktrees/`), on its own branch. Once the work is done, merge it back into the main branch and remove the worktree, unless the user explicitly asked to confirm before merging; in that case, stop and wait for their go-ahead.
- Use TDD: write expected behaviour in the form of a Vader test first (failing), then implement it until the tests are passing. If implementation proves to be difficult or impossible, check in with the user to decide on compromises.
- Refactors must not change behaviour: the existing tests are the oracle. If a refactor would fix or change a behaviour, stop and check with the user first. Known bugs are listed in specification.song.txt under [[Bugs]]; do not fix them as a side effect.
- Commit every time you make a successful change (tests green, enforced by the pre-commit hook).
- A PLAN.md is a scratchpad for one task in progress. Delete it once the task is done; it must never describe finished work.

## Architecture (see design.md for the why)
- `autoload/songwriter/grammar.vim` is the single source of truth for the format's patterns (tab line, note, chord root...). Never write one of these regexes inline elsewhere.
- `autoload/songwriter/tab/model.vim` parses a tab block once into a structured model and offers queries (note columns, bar bounds...) and the one column-insertion primitive. New tab features compose these; do not re-scan raw strings.
- Keep logic pure (lines + cursor in, lines + cursor out). Only thin entry points read/write the buffer (`getline`/`setline`/`cursor`).
- Context-dependent keys (tab line, tablature mode) are declared in the per-mode tables in `autoload/songwriter/keys.vim` and dispatched by `songwriter#keys#Dispatch()`; plain keys map to `<Plug>(songwriter-…)` via the table in `ftplugin/songwriter.vim`. Every buffer map must be undone in `b:undo_ftplugin`. Use `<Cmd>…<CR>`, never `:call …<CR>`; an action that must return keys (an operator's `g@`) is written `=expr` in the tables. Don't hand-write near-identical map lines.
- Public functions live in autoload (`songwriter#module#Name`). No global `Songwriter*()` functions; tests call the autoload functions directly. User-facing entry points are `:Songwriter*` commands and `<Plug>(songwriter-…)` maps.

## Code style (Vim script)
- Every function has `abort`.
- Use dicts with named keys for structured values (`block.lines`, not `block[2]`).
- Explicit scopes (`l:`, `a:`, `s:`), `==#` / `=~#` for comparisons.

## Comments and docs
- Comments describe the code as it is now. Never narrate history ("now", "previously", "the old behaviour"); that belongs in commit messages.
- Reference the spec with its exact number as it currently stands in specification.song.txt (e.g. "spec [Tablature][[Editing]] 3.3.2"). When the spec is renumbered, update references.
- When a function's behaviour changes, rewrite its doc comment; never stack a second comment on top of a stale one.
- design.md records lasting design decisions and their rationale, organised by topic. Edit the relevant section in place rather than appending; remove what no longer applies.

## Testing
- `make test` runs the full suite (fast; prefer it to running single files).
- Prefer `Given songwriter` / `Do` / `Expect songwriter` blocks for buffer transformations, so the before/after tab is visible in the test. Use `Execute` + `Assert*` for cursor positions and pure functions.
- Shared setup goes in a `Before:` block, not repeated in every case.
