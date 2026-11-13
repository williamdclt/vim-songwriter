" autoload/songwriter/tab.vim - the tablature commands that work outside
" tablature mode too: `_`, `||`, :SongwriterAddBar, :SongwriterAddDashes and
" :SongwriterTabChord (spec [Tablature][[Editing]] 1, 2).
" Tablature mode's editing lives in tab/*.vim (see design.md "Modules").

" Append `--` to every string of the block.
function! songwriter#tab#AddDashes() abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call songwriter#tab#edit#Write(l:block, {'lines': map(copy(l:block.lines), "v:val . '--'"),
        \ 'map': songwriter#tab#colmap#Insert(max(map(copy(l:block.lines), 'len(v:val)')), 2)})
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
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call songwriter#tab#edit#Write(l:block,
        \ songwriter#tab#model#InsertColumns(l:block.lines, col('.'), 1, a:char))
endfunction

" Spec [Tablature][[Editing]] 1: lint the block around the cursor.
function! songwriter#tab#Lint() abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call songwriter#tab#edit#Write(l:block, songwriter#tab#lint#Lint(l:block.lines))
endfunction

" Insert `chord` on a new line above the block, aligned to the cursor column.
function! songwriter#tab#TabChord(chord) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  call append(l:block.start - 1, repeat(' ', col('.') - 1) . a:chord)
endfunction
