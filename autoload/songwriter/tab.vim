" autoload/songwriter/tab.vim - the tablature commands that work outside
" tablature mode too: `_`, `||`, :SongwriterAddBar, :SongwriterAddDashes and
" :SongwriterTabChord and `<leader>a` (spec [Tablature][[Editing]] 1, 2,
" [[Annotations]] 6, 8).
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

" Spec [Tablature][[Annotations]] 6: write `chord` above the block, aligned
" to the cursor column (past the string name and first pipe, so that it is an
" annotation): on the annotation line right above the strings when it fits,
" else on a new one.
function! songwriter#tab#TabChord(chord) abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:col = max([col('.'), songwriter#tab#model#BodyOffset() + 1])
  call songwriter#tab#model#Write(l:block, extend(songwriter#tab#model#Snapshot(l:block),
        \ {'above': songwriter#tab#annotations#Add(l:block.above, l:col, a:chord)}))
endfunction

" Spec [Tablature][[Annotations]] 8: the keys that start typing an annotation
" above the cursor's column (past the string name and first pipe), in Vim's
" insert mode, on the annotation line right above the strings: opened with
" `O` when there is none, typed over in Replace mode inside it (the words
" after the column stay where they are), appended to past its end with spaces
" up to the column. Typed rather than set, so that the line and what is typed
" on it are one undo step. Leave() tidies the line afterwards. Off a tab line,
" no keys.
function! songwriter#tab#Annotate() abort
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return ''
  endif
  let l:col = max([col('.'), songwriter#tab#model#BodyOffset() + 1])
  if empty(l:block.above)
    let l:lnum = l:block.start
    let l:keys = printf("\<Cmd>call cursor(%d, 1)\<CR>O", l:lnum) . repeat(' ', l:col - 1)
  else
    let l:lnum = l:block.start - 1
    let l:line = getline(l:lnum)
    let l:at = songwriter#tab#annotations#Bytes(l:line, l:col, 1)
    let l:keys = empty(l:at)
          \ ? printf("\<Cmd>call cursor(%d, 1)\<CR>A", l:lnum)
          \   . repeat(' ', l:col - 1 - strdisplaywidth(l:line))
          \ : printf("\<Cmd>call cursor(%d, %d)\<CR>R", l:lnum, l:at[0])
  endif
  let b:songwriter_annotating = {'top': l:block.top}
  return l:keys
endfunction

" Spec [Tablature][[Annotations]] 8, on leaving insert mode after Annotate():
" the annotation line loses the spaces at its end, and goes when it is left
" empty, in the same undo step as what was typed.
function! songwriter#tab#AnnotateLeave() abort
  if !exists('b:songwriter_annotating')
    return
  endif
  unlet b:songwriter_annotating
  let l:lnum = line('.')
  let l:line = getline(l:lnum)
  let l:trimmed = substitute(l:line, songwriter#grammar#TrailingSpace(), '', '')
  if l:trimmed ==# l:line
    return
  endif
  silent! undojoin
  if l:trimmed ==# ''
    call deletebufline('%', l:lnum)
  else
    call setline(l:lnum, l:trimmed)
  endif
endfunction
