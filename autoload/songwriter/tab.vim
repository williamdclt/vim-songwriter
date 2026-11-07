" autoload/songwriter/tab.vim - tablature editing operations: inserting
" dashes/bars, the bar-alignment linter, and placing a chord above a bar.
" Private helpers stay s:-local; the public ops delegate to
" songwriter#util for the shared block scan and column op.

" === Linter support (private) ===

function! s:extract_atoms(region) abort
  let l:res = []
  let l:i = 0
  let l:n = len(a:region)
  while l:i < l:n
    if a:region[l:i] =~# '[0-9]'
      let l:j = l:i + 1
      while l:j < l:n && a:region[l:j] =~# '[0-9]'
        let l:j += 1
      endwhile
      call add(l:res, [l:i, strpart(a:region, l:i, l:j - l:i)])
      let l:i = l:j
    else
      let l:i += 1
    endif
  endwhile
  return l:res
endfunction
function! s:parse_tab_lines(lines) abort
  let l:regions = []
  let l:P = 0
  for l:ln in a:lines
    let l:parts = split(l:ln, '[|]', 1)
    call remove(l:parts, 0)             " drop the string-name prefix
    call remove(l:parts, len(l:parts) - 1) " drop anything after the final pipe
    call add(l:regions, l:parts)
    if len(l:parts) > l:P
      let l:P = len(l:parts)
    endif
  endfor
  return [l:regions, l:P, len(a:lines)]
endfunction
function! s:relax_bar(atoms, mincol) abort
  let l:work = []
  for l:a in a:atoms
    call add(l:work, {
             \ 'lin': l:a[0],
             \ 'c0': l:a[1],
             \ 'num': l:a[2],
             \ 'len': len(l:a[2]),
             \ 'start': l:a[1] - a:mincol + 2})
  endfor

  let l:iter = 0
  while l:iter < 200
    let l:iter += 1
    let l:changed = 0
    let l:last = {}
    for l:a in l:work
      let l:need = l:a['start']
      if has_key(l:last, l:a['lin'])
        let l:gap = l:a['c0'] - l:last[l:a['lin']]['c0']
        let l:cand = l:last[l:a['lin']]['start'] + l:gap
        if l:cand > l:need
          let l:need = l:cand
        endif
      endif
      for l:b in l:work
        if l:b['lin'] !=# l:a['lin']
              \ && l:b['start'] < l:a['start']
              \ && l:a['start'] <= l:b['start'] + l:b['len'] - 1
          let l:cand = l:b['start'] + l:b['len'] + 1
          if l:cand > l:need
            let l:need = l:cand
          endif
        endif
      endfor
      if l:need > l:a['start']
        let l:a['start'] = l:need
        let l:changed = 1
      endif
      let l:last[l:a['lin']] = {'c0': l:a['c0'], 'start': l:a['start']}
    endfor
    if !l:changed
      break
    endif
  endwhile
  return l:work
endfunction
function! s:render_bar(work, NL) abort
  let l:maxend = 2
  for l:a in a:work
    let l:e = l:a['start'] + l:a['len'] - 1
    if l:e > l:maxend
      let l:maxend = l:e
    endif
  endfor
  let l:W = l:maxend + 3

  let l:bylin = {}
  for l:a in a:work
    if !has_key(l:bylin, l:a['lin'])
      let l:bylin[l:a['lin']] = []
    endif
    call add(l:bylin[l:a['lin']], l:a)
  endfor

  let l:out = []
  for l:lin in range(0, a:NL - 1)
    if has_key(l:bylin, l:lin)
      let l:arr = repeat(['-'], l:W)
      for l:a in l:bylin[l:lin]
        for l:k in range(0, l:a['len'] - 1)
          let l:arr[l:a['start'] + l:k] = l:a['num'][l:k]
        endfor
      endfor
      call add(l:out, join(l:arr, ''))
    else
      call add(l:out, repeat('-', l:W))
    endif
  endfor
  return l:out
endfunction
function! s:lint_block(lines)
  let l:parsed = s:parse_tab_lines(a:lines)
  let l:regions = l:parsed[0]
  let l:P = l:parsed[1]
  let l:NL = l:parsed[2]

  let l:lineparts = []
  for l:i in range(0, l:NL - 1)
    call add(l:lineparts, [])
  endfor

  for l:j in range(0, l:P - 1)
     " Collect this bar's digit atoms ([lin, c0, num]), its minimum column, and
     " whether any string has a note in the bar.
    let l:atoms = []
    let l:mn = 0
    let l:mnset = 0
    let l:h = 0
    for l:lin in range(0, l:NL - 1)
      if l:j >= len(l:regions[l:lin])
        continue
      endif
      for l:at in s:extract_atoms(l:regions[l:lin][l:j])
        call add(l:atoms, [l:lin, l:at[0], l:at[1]])
        let l:h = 1
        if !l:mnset || l:at[0] < l:mn
          let l:mn = l:at[0]
          let l:mnset = 1
        endif
      endfor
    endfor

    if l:h == 0
       " Empty bar -> exactly two dashes on every string.
      for l:lin in range(0, l:NL - 1)
        call add(l:lineparts[l:lin], '--')
      endfor
      continue
    endif

    let l:work = s:relax_bar(l:atoms, l:mn)
    let l:out_j = s:render_bar(l:work, l:NL)
    for l:lin in range(0, l:NL - 1)
      call add(l:lineparts[l:lin], l:out_j[l:lin])
    endfor
  endfor

   " Assemble lines.
  let l:out = []
  for l:k in range(0, l:NL - 1)
    let l:letter = strpart(a:lines[l:k], 0, 1)
    call add(l:out, l:letter . '|' . join(l:lineparts[l:k], '|') . '|')
  endfor
  return l:out
endfunction

" === Public tab operations ===

function! songwriter#tab#AddDashes()
  let l:block = songwriter#util#find_tab_block()
  if empty(l:block[2])
    return
  endif
  for l:i in range(len(l:block[2]))
    call setline(l:block[0] + l:i, l:block[2][l:i] . '--')
  endfor
endfunction

function! songwriter#tab#AddDash()
  call songwriter#util#insert_char_at_col('-')
endfunction

function! songwriter#tab#AddBar()
  call songwriter#util#insert_char_at_col('|')
endfunction

function! songwriter#tab#Lint()
  let l:block = songwriter#util#find_tab_block()
  if empty(l:block[2])
    return
  endif
  let l:newlines = s:lint_block(l:block[2])
  for l:i in range(len(l:newlines))
    call setline(l:block[0] + l:i, l:newlines[l:i])
  endfor
endfunction

function! songwriter#tab#TabChord(chord)
  let l:block = songwriter#util#find_tab_block()
  if empty(l:block[2])
    return
  endif
  call append(l:block[0] - 1, repeat(' ', col('.') - 1) . a:chord)
endfunction
