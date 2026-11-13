# Tab annotations (spec [Tablature][[Annotations]])

Branch `annotations`. Decisions taken with the user: an annotation line has
two leading spaces; a label over a deleted column is deleted; edits report
their column maps (no diffing).

1. Refactor 1 (refactors.md): column maps.
2. Refactor 2 (refactors.md): drafts, one write path.
3. Annotations are part of the block (spec 1, 2): grammar pattern, `Read`
   gives `top` and `above`, a block is identified by `top` (slot, carry),
   `Write` handles a changing number of annotation lines, line-wise targets,
   `O`, `P`, `:SongwriterNewTab`.
4. Annotations follow edits (spec 3, 4): `tab/annotations.vim` (words, labels,
   spans, `Follow(above, map)`), wired into `edit#Write`; carry and slots keep
   annotations in their saved states; carried labels (4.5). End-to-end
   invariant: labels over every time column of the corpus.
5. Registers carry annotations (spec 5).
6. `:SongwriterTabChord` (6) and the highlight (7).
7. README, design.md; delete this file.
