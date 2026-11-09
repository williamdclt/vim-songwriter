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

" Pure. Where column `col` of block line `lin` (0-indexed) lands once `lines`
" are linted into `result` (the return of Lint), so the cursor stays put
" relative to the music:
"   - on a note of that line: the same digit of that note;
"   - on a pipe: the same pipe;
"   - elsewhere in a bar: the same distance from the nearest note starting at or
"     before `col` (on any string), kept before the next note start and inside
"     the bar. Notes starting before / after `col` stay before / after it, so
"     the `a`/`i` anchors are unchanged.
"   - on the string name: unchanged; past the final pipe: the line end.
function! songwriter#tab#lint#FollowColumn(lines, result, lin, col) abort
  let l:old_pipes = songwriter#tab#model#Pipes(a:lines[a:lin])
  let l:new_pipes = songwriter#tab#model#Pipes(a:result.lines[a:lin])
  if empty(l:old_pipes) || a:col < l:old_pipes[0]
    return a:col
  endif
  if a:col > l:old_pipes[-1]
    return len(a:result.lines[a:lin])
  endif
  let l:k = index(l:old_pipes, a:col)
  if l:k >= 0
    return l:new_pipes[l:k]
  endif
  let l:bar = len(filter(copy(l:old_pipes), 'v:val < a:col')) - 1

  " This bar's notes on every string: [from, to, len].
  let l:notes = []
  for l:m in a:result.moves
    let l:p = songwriter#tab#model#Pipes(a:lines[l:m.line])
    if l:bar + 1 < len(l:p) && l:m.from > l:p[l:bar] && l:m.from < l:p[l:bar + 1]
      let l:len = len(matchstr(a:lines[l:m.line], '^' . songwriter#grammar#Note(), l:m.from - 1))
      if l:m.line == a:lin && a:col >= l:m.from && a:col < l:m.from + l:len
        return l:m.to + a:col - l:m.from
      endif
      call add(l:notes, [l:m.from, l:m.to, l:len])
    endif
  endfor

  let l:lo = l:new_pipes[l:bar] + 1
  let l:hi = l:new_pipes[l:bar + 1] - 1
  let l:prev = filter(copy(l:notes), 'v:val[0] <= a:col')
  let l:next = filter(copy(l:notes), 'v:val[0] > a:col')
  if !empty(l:next)
    let l:hi = min([l:hi, min(map(copy(l:next), 'v:val[1]')) - 1])
  endif
  if !empty(l:prev)
    let l:from = max(map(copy(l:prev), 'v:val[0]'))
    let l:to = max(map(filter(copy(l:prev), 'v:val[0] == l:from'), 'v:val[1]'))
    let l:lo = max([l:lo, l:to])
    let l:c = l:to + a:col - l:from
  elseif !empty(l:next)
    let l:first = sort(copy(l:next), {a, b -> a[0] - b[0]})[0]
    let l:c = l:first[1] - (l:first[0] - a:col)
  else
    let l:c = l:lo + a:col - l:old_pipes[l:bar] - 1
  endif
  return max([l:lo, min([l:c, l:hi])])
endfunction
