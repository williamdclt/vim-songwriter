# PLAN: carrying notes across strings (spec [Tablature][[Editing]] 3.6-3.8, 7)

Scratchpad for the carry redesign. Delete when done.

1. Spec: 3.6 (`<leader>k/j` carry), 3.7 (`<leader><leader>k/j` copy), 3.8
   (`m` move state), 7 (`s`/`S` are carries), [[Annotations]] 4.5. Arrows gone.
2. carry.vim: vertical carry of a set of notes (base = tab with the notes
   blanked, render = base + notes one or more strings away, texts changing for
   `S` and frets). Runs: one undo step while the cursor stays on the carry.
3. strings.vim: `s`/`S` call the carry; keep repitch and the column lookup.
4. Keys: tabmode `<leader>k/j`, `<leader><leader>k/j`, `m`; moving table
   `hjklJK`, `<leader>j/k`, `m`, `<Esc>`; visual `<leader>k/j`. Remove arrows,
   lone `<leader>`, the duplicate/end-move <Plug> maps.
5. Visual carry.
6. README, design.md, delete PLAN.md, merge.
