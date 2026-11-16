" autoload/songwriter/tab.vim - the tablature commands that work outside
" tablature mode too: `_`, `||`, :SongwriterAddBar, :SongwriterAddDashes and
" :SongwriterTabChord (spec [Tablature][[Editing]] 1, 2, [[Annotations]] 6).
" Tablature mode's editing lives in tab/*.vim (see design.md "Modules").

" Append `--` to every string of the block.
function! songwriter#tab#AddDashes() abort
  call s:edit({ctx -> {'lines': map(copy(ctx.block.lines), "v:val . '--'"),
        \ 'map': songwriter#tab#colmap#Insert(max(map(copy(ctx.block.lines), 'len(v:val)')), 2)}})
endfunction

" Fn's edit of the block at the cursor (edit#Do), as it is: no lint, the
" cursor where it is.
function! s:edit(Fn) abort
  call songwriter#tab#edit#Do(a:Fn, {'prelint': 0, 'lint': 0})
endfunction

" Spec [Tablature][[Editing]] 2: insert a dash after the cursor column on
" every string of the block.
function! songwriter#tab#AddDash() abort
  call s:insert_after_cursor('-')
endfunction

" Insert a bar pipe after the cursor column on every string of the block.
function! songwriter#tab#AddBar() abort
  call s:insert_after_cursor('|')
endfunction

function! s:insert_after_cursor(char) abort
  call s:edit({ctx -> songwriter#tab#model#InsertColumns(ctx.block.lines, ctx.col, 1, a:char)})
endfunction

" Spec [Tablature][[Editing]] 1: lint the block around the cursor (the lint's
" lines and map as the edit's result).
function! songwriter#tab#Lint() abort
  call s:edit({ctx -> filter(songwriter#tab#lint#Lint(ctx.block.lines),
        \ {k -> k ==# 'lines' || k ==# 'map'})})
endfunction

" Spec [Tablature][[Annotations]] 6: write `chord` above the block, aligned
" to the cursor column (past the string name and first pipe, so that it is an
" annotation): in place of the column's chord label, else on the annotation
" line right above the strings, the tab widened when its neighbours are too
" close (edit.vim), else on a new one. A chord is
" spelled as `=` writes it ([[Editing]] 10.9: `CM7` -> `Cmaj7`).
function! songwriter#tab#TabChord(chord) abort
  call s:edit({ctx -> {'lines': ctx.block.lines, 'map': [],
        \ 'annotations': [{'op': 'label', 'col': max([ctx.col, songwriter#tab#model#BodyOffset() + 1]),
        \   'text': songwriter#tab#voicings#Spelled(a:chord), 'add': 1}]}})
endfunction
