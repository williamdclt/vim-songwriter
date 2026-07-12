" songwriter.vim - Vim plugin for guitar tablatures, chords, lyrics, notes
" Maintainer:
" License: MIT

if exists('g:loaded_songwriter')
  finish
endif
let g:loaded_songwriter = 1

function! SongwriterAddDashes()
  " A tab line: starts with a letter immediately followed by |
  let l:tab_pat = '^\a[|]'

  " Check if current line is a tab line
  if !(getline('.') =~# tab_pat)
    return
  endif

  " Find start of contiguous tab block (scan up)
  let l:start = line('.')
  while l:start > 1 && (getline(l:start - 1) =~# tab_pat)
    let l:start -= 1
  endwhile

  " Find end of contiguous tab block (scan down)
  let l:end = line('.')
  while l:end < line('$') && (getline(l:end + 1) =~# tab_pat)
    let l:end += 1
  endwhile

  " Append -- to each tab line in the block
  for l:ln in range(l:start, l:end)
    let l:line = getline(l:ln)
    call setline(l:ln, l:line . '--')
  endfor
endfunction

function! SongwriterAddBar()
  " A tab line: starts with a letter immediately followed by |
  let l:tab_pat = '^\a[|]'

  " Check if current line is a tab line
  if !(getline('.') =~# tab_pat)
    return
  endif

  " Find start of contiguous tab block (scan up)
  let l:start = line('.')
  while l:start > 1 && (getline(l:start - 1) =~# tab_pat)
    let l:start -= 1
  endwhile

  " Find end of contiguous tab block (scan down)
  let l:end = line('.')
  while l:end < line('$') && (getline(l:end + 1) =~# tab_pat)
    let l:end += 1
  endwhile

  " Get cursor column (1-indexed)
  let l:col = col('.')

  " Insert | at cursor column on each tab line in the block
  for l:ln in range(l:start, l:end)
    let l:line = getline(l:ln)
    " Ensure line is long enough; pad with dashes if needed
    while len(l:line) < l:col
      let l:line .= '-'
    endwhile
    " Insert | at cursor column (col is 1-indexed, string is 0-indexed)
    let l:newline = strpart(l:line, 0, l:col) . '|' . strpart(l:line, l:col)
    call setline(l:ln, l:newline)
  endfor
endfunction

function! SongwriterTabChord(chord)
  " A tab line: starts with a letter immediately followed by |
  let l:tab_pat = '^\a[|]'

  " Check if current line is a tab line
  if !(getline('.') =~# tab_pat)
    return
  endif

  " Find start of contiguous tab block (scan up)
  let l:start = line('.')
  while l:start > 1 && (getline(l:start - 1) =~# tab_pat)
    let l:start -= 1
  endwhile

  " Get cursor column (1-indexed)
  let l:col = col('.')

  " Build chord line: spaces to align chord start at cursor column, then chord name
  let l:spaces = repeat(' ', l:col - 1)
  let l:chord_line = l:spaces . a:chord

  " Insert chord line above the tab block
  call append(l:start - 1, l:chord_line)
endfunction
