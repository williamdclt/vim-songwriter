" autoload/songwriter/tab/newtab.vim - new tabs: `o`/`O` (spec
" [Tablature][[Editing]] 8) and :SongwriterNewTab (9).

" The string names of a new tab when none are given (standard guitar tuning).
let s:default_names = 'eBGDAE'

" Spec [Tablature][[Editing]] 8: add an empty tab under (below 1, `o`) or
" over (below 0, `O`) the block around the cursor, with the same string names
" and a blank line between the two, and land on the slot in its middle, on the
" cursor's string, in the insert state. The slot is part of the new tab, so
" closed without a note it is linted to an empty bar (4.3). An open slot is
" closed first.
function! songwriter#tab#newtab#NewTab(below) abort
  call songwriter#tab#slots#Abandon()
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return
  endif
  let l:tab = songwriter#tab#slots#EmptyTab(l:block)
  let l:row = songwriter#tab#model#CursorLin(l:block)
  if a:below
    let l:last = l:block.end
    call append(l:last, [''] + l:tab.lines)
    let l:first = l:last + 2
  else
    call append(l:block.start - 1, l:tab.lines + [''])
    let l:first = l:block.start
  endif
  call cursor(l:first + l:row, l:tab.col)
  call songwriter#tab#slots#Open()
endfunction

" Spec [Tablature][[Editing]] 9 (`:SongwriterNewTab`): add an empty tab with
" string `names` (one letter each, highest first; default eBGDAE). In a tab it
" goes under that tab; on a blank line it takes that line's place; elsewhere it
" goes under the cursor line. A blank line keeps it apart from a neighbouring
" tab. Tablature mode is turned on and the cursor lands on the slot of the top
" string, remembered as `o`'s is (8). Invalid names are refused with a message.
function! songwriter#tab#newtab#NewTabNamed(names) abort
  let l:names = empty(a:names) ? s:default_names : a:names
  if !songwriter#grammar#IsStringNames(l:names)
    call songwriter#tab#edit#Error('songwriter: string names are single letters, highest first (eBGDAE): ' . l:names)
    return
  endif
  call songwriter#tab#slots#Abandon()
  let l:tab = songwriter#tab#slots#EmptyTabNamed(split(l:names, '\zs'))
  let l:block = songwriter#tab#model#Read()
  if !empty(l:block)
    let l:after = l:block.end
  elseif getline('.') =~# '^\s*$'
    let l:after = line('.') - 1
    call deletebufline('%', line('.'))
  else
    let l:after = line('.')
  endif
  let l:lines = copy(l:tab.lines)
  let l:first = l:after + 1
  if l:after >= 1 && songwriter#grammar#IsTabLine(getline(l:after))
    call insert(l:lines, '')
    let l:first += 1
  endif
  if l:after < line('$') && songwriter#grammar#IsTabLine(getline(l:after + 1))
    call add(l:lines, '')
  endif
  if line('$') == 1 && getline(1) ==# '' && l:after == 0
    call setline(1, l:lines)
  else
    call append(l:after, l:lines)
  endif
  let b:songwriter_tabmode = 1
  call cursor(l:first, l:tab.col)
  call songwriter#tab#slots#Open()
endfunction
