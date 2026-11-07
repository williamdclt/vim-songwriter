" autoload/songwriter/util.vim - shared tablature helpers: the single
" tab-line pattern, the block scanner, the column-op helper, and the
" tab-line test. Shared by the tab and chord modules.

let s:TabLinePat = '^\a[|]'

" True when `line` is a tablature line (string name + bar pipe).
function! songwriter#util#IsTablatureLine(line) abort
  return a:line =~# s:TabLinePat
endfunction

function! songwriter#util#find_tab_block()
  if getline('.') !~# s:TabLinePat
    return [0, 0, []]
  endif
  let l:start = line('.')
  while l:start > 1 && (getline(l:start - 1) =~# s:TabLinePat)
    let l:start -= 1
  endwhile
  let l:end = line('.')
  while l:end < line('$') && (getline(l:end + 1) =~# s:TabLinePat)
    let l:end += 1
  endwhile
  let l:lines = []
  for l:ln in range(l:start, l:end)
    call add(l:lines, getline(l:ln))
  endfor
  return [l:start, l:end, l:lines]
endfunction
function! songwriter#util#insert_char_at_col(char)
  let l:block = songwriter#util#find_tab_block()
  if empty(l:block[2])
    return 0
  endif
  let l:col = col('.')
  for l:i in range(len(l:block[2]))
    let l:line = l:block[2][l:i]
    while len(l:line) < l:col
      let l:line .= '-'
    endwhile
    call setline(l:block[0] + l:i, strpart(l:line, 0, l:col) . a:char . strpart(l:line, l:col))
  endfor
  return 1
endfunction
