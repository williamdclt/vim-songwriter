" autoload/songwriter/tab/lint.vim - the tablature linter (spec
" [Tablature][[Editing]] 1), as a pure function over a block's lines.
" See design.md "Linter" for the model and its invariants.

" Lint `lines` (one tab block). Returns {
"   'lines': the linted lines,
"   'moves': [{'line': 0-indexed line in the block, 'from': old column,
"              'to': new column}] for every note, so callers can keep the
"              cursor on the same note after linting.
" }
function! songwriter#tab#lint#Lint(lines) abort
  let l:nl = len(a:lines)
  let l:regions = s:bar_regions(a:lines)
  let l:nbars = max(map(copy(l:regions), 'len(v:val)'))

  let l:lineparts = map(range(l:nl), '[]')
  let l:moves = []
  for l:j in range(l:nbars)
    " This bar's notes ([lin, c0, text], c0 = 0-indexed offset in the bar
    " region) and its leftmost offset.
    let l:atoms = []
    for l:lin in range(l:nl)
      if l:j < len(l:regions[l:lin])
        for l:n in songwriter#tab#model#Notes(l:regions[l:lin][l:j])
          call add(l:atoms, [l:lin, l:n.col - 1, l:n.text])
        endfor
      endif
    endfor

    if empty(l:atoms)
      " Empty bar -> exactly two dashes on every string.
      for l:lin in range(l:nl)
        call add(l:lineparts[l:lin], '--')
      endfor
      continue
    endif

    let l:mincol = min(map(copy(l:atoms), 'v:val[1]'))
    let l:work = s:relax_bar(l:atoms, l:mincol)
    let l:rendered = s:render_bar(l:work, l:nl)
    for l:lin in range(l:nl)
      call add(l:lineparts[l:lin], l:rendered[l:lin])
    endfor
    for l:a in l:work
      call add(l:moves, {'line': l:a.lin, 'bar': l:j, 'c0': l:a.c0, 'start': l:a.start})
    endfor
  endfor

  let l:out = []
  for l:k in range(l:nl)
    call add(l:out, strpart(a:lines[l:k], 0, 1) . '|' . join(l:lineparts[l:k], '|') . '|')
  endfor
  return {'lines': l:out, 'moves': s:to_columns(l:moves, a:lines, l:lineparts)}
endfunction

" Split each line on pipes into its bar regions, dropping the string-name
" prefix and anything after the final pipe.
function! s:bar_regions(lines) abort
  let l:regions = []
  for l:ln in a:lines
    let l:parts = split(l:ln, '[|]', 1)
    call remove(l:parts, 0)
    call remove(l:parts, len(l:parts) - 1)
    call add(l:regions, l:parts)
  endfor
  return l:regions
endfunction

" Fixed-point placement of a bar's notes: each gets an output offset `start`
" (2 dashes after the bar's left pipe for the leftmost note) such that
"   - a string's notes keep their original relative gaps, and
"   - a note starting inside a different string's number is pushed right to
"     leave one dash after it (spec 1.3); aligned starts are never split.
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
      let l:need = l:a.start
      if has_key(l:last, l:a.lin)
        let l:prev = l:last[l:a.lin]
        let l:need = max([l:need, l:prev.start + l:a.c0 - l:prev.c0])
      endif
      for l:b in l:work
        if l:b.lin !=# l:a.lin
              \ && l:b.start < l:a.start
              \ && l:a.start <= l:b.start + l:b.len - 1
          let l:need = max([l:need, l:b.start + l:b.len + 1])
        endif
      endfor
      if l:need > l:a.start
        let l:a.start = l:need
        let l:changed = 1
      endif
      let l:last[l:a.lin] = {'c0': l:a.c0, 'start': l:a.start}
    endfor
    if !l:changed
      break
    endif
  endwhile
  return l:work
endfunction

" One region string per line for a placed bar, all the same width (the
" rightmost note's end + 2 trailing dashes) so the pipes line up.
function! s:render_bar(work, nl) abort
  let l:maxend = 2
  for l:a in a:work
    let l:maxend = max([l:maxend, l:a.start + l:a.len - 1])
  endfor
  let l:width = l:maxend + 3

  let l:cells = map(range(a:nl), "repeat(['-'], l:width)")
  for l:a in a:work
    for l:k in range(l:a.len)
      let l:cells[l:a.lin][l:a.start + l:k] = l:a.num[l:k]
    endfor
  endfor
  return map(l:cells, "join(v:val, '')")
endfunction

" Turn per-bar offsets into 1-indexed line columns, before and after.
function! s:to_columns(moves, lines, lineparts) abort
  let l:res = []
  for l:m in a:moves
    let l:old_pipe = songwriter#tab#model#Pipes(a:lines[l:m.line])[l:m.bar]
    let l:new_region = 2
    for l:k in range(l:m.bar)
      let l:new_region += len(a:lineparts[l:m.line][l:k]) + 1
    endfor
    call add(l:res, {
          \ 'line': l:m.line,
          \ 'from': l:old_pipe + l:m.c0 + 1,
          \ 'to': l:new_region + l:m.start + 1})
  endfor
  return l:res
endfunction
