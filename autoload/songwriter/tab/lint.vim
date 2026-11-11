" autoload/songwriter/tab/lint.vim - the tablature linter (spec
" [Tablature][[Editing]] 1), as a pure function over a block's lines.
" See design.md "Linter" for the model and its invariants.

" Lint `lines` (one tab block). Returns {
"   'lines': the linted lines,
"   'moves': [{'line': 0-indexed line in the block, 'bar': 0-indexed bar,
"              'len': width, 'from': old column, 'to': new column}] for every
"              note, so callers can keep the cursor on the same note after
"              linting.
" }
function! songwriter#tab#lint#Lint(lines) abort
  let l:lines = s:close_bars(a:lines)
  let l:nl = len(l:lines)
  let l:regions = s:bar_regions(l:lines)
  " A tab keeps at least one bar (spec 1.4): with none (`e|`), one empty bar.
  let l:nbars = max([1, max(map(copy(l:regions), 'len(v:val)'))])

  let l:lineparts = map(range(l:nl), '[]')
  let l:moves = []
  let l:empty = []
  for l:j in range(l:nbars)
    " This bar's notes and separators, left to right on each line ({lin, c0,
    " text, note}, c0 = 0-indexed offset in the bar region), kept verbatim. And
    " its leftmost offset.
    let l:atoms = []
    for l:lin in range(l:nl)
      if l:j < len(l:regions[l:lin])
        call extend(l:atoms, s:region_atoms(l:lin, l:regions[l:lin][l:j]))
      endif
    endfor

    call add(l:empty, empty(l:atoms))
    if empty(l:atoms)
      " Empty bar -> exactly five dashes on every string (spec 1.2), so a
      " note typed on the middle one needs no reflow.
      for l:lin in range(l:nl)
        call add(l:lineparts[l:lin], '-----')
      endfor
      continue
    endif

    let l:mincol = min(map(copy(l:atoms), 'v:val.c0'))
    let l:work = s:relax_bar(l:atoms, l:mincol)
    let l:rendered = s:render_bar(l:work, l:nl)
    for l:lin in range(l:nl)
      call add(l:lineparts[l:lin], l:rendered[l:lin])
    endfor
    for l:a in filter(copy(l:work), 'v:val.note')
      call add(l:moves, {'line': l:a.lin, 'bar': l:j, 'len': l:a.len, 'c0': l:a.c0, 'start': l:a.start})
    endfor
  endfor

  " Spec 1.4: empty bars at the end of the tab are dropped (all of them, so
  " lint is idempotent), but a tab keeps at least one bar. They hold no notes,
  " so no moves to update.
  let l:keep = len(l:empty)
  while l:keep > 1 && l:empty[l:keep - 1]
    let l:keep -= 1
  endwhile
  if l:keep < len(l:empty)
    call map(l:lineparts, 'v:val[: l:keep - 1]')
  endif

  let l:out = []
  for l:k in range(l:nl)
    call add(l:out, songwriter#tab#model#Name(l:lines[l:k]) . '|' . join(l:lineparts[l:k], '|') . '|')
  endfor
  return {'lines': l:out, 'moves': s:to_columns(l:moves, l:lines, l:lineparts)}
endfunction

" The notes and separators of bar region `row` of line `lin`, left to right.
function! s:region_atoms(lin, row) abort
  let l:atoms = []
  for l:n in songwriter#tab#model#RowNotes(a:row)
    call add(l:atoms, {'lin': a:lin, 'c0': l:n.col - 1, 'text': l:n.text, 'note': 1})
  endfor
  for l:n in songwriter#tab#model#RowSeparators(a:row)
    call add(l:atoms, {'lin': a:lin, 'c0': l:n.col - 1, 'text': l:n.text, 'note': 0})
  endfor
  return sort(l:atoms, {a, b -> a.c0 - b.c0})
endfunction

" Close every line's last bar: a line with anything but whitespace after its
" final pipe (`e|--3--5--`) gets a pipe after its last non-blank character, so
" that content is linted as a bar rather than dropped. Only appends, so every
" earlier column is unchanged (moves and FollowColumn stay valid for the
" caller's lines).
function! s:close_bars(lines) abort
  return map(copy(a:lines), {_, l ->
        \ songwriter#grammar#IsClosedTabLine(l) ? l : substitute(l, songwriter#grammar#TrailingSpace(), '|', '')})
endfunction

" Split each line on pipes into its bar regions, dropping the string-name
" prefix and anything after the final pipe.
function! s:bar_regions(lines) abort
  let l:regions = []
  for l:ln in a:lines
    let l:parts = split(l:ln, songwriter#grammar#Pipe(), 1)
    call remove(l:parts, 0)
    call remove(l:parts, len(l:parts) - 1)
    call add(l:regions, l:parts)
  endfor
  return l:regions
endfunction

" Fixed-point placement of a bar's notes and separators: each gets an output
" offset `start` (2 dashes after the bar's left pipe for the leftmost one) such
" that
"   - a string's notes and separators keep their original relative gaps, and
"   - a note starting inside a different string's number is pushed right to
"     leave one dash after it (spec 1.3); aligned starts are never split.
"     Separators take no part in this: they occupy no time.
function! s:relax_bar(atoms, mincol) abort
  let l:work = []
  for l:a in a:atoms
    call add(l:work, {
          \ 'lin': l:a.lin,
          \ 'c0': l:a.c0,
          \ 'num': l:a.text,
          \ 'note': l:a.note,
          \ 'len': len(l:a.text),
          \ 'start': l:a.c0 - a:mincol + 2})
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
        if l:a.note && l:b.note && l:b.lin !=# l:a.lin
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
          \ 'bar': l:m.bar,
          \ 'len': l:m.len,
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
  let l:lines = s:close_bars(a:lines)
  let l:old_pipes = songwriter#tab#model#Pipes(l:lines[a:lin])
  let l:new_pipes = songwriter#tab#model#Pipes(a:result.lines[a:lin])
  if empty(l:old_pipes) || a:col < l:old_pipes[0]
    return a:col
  endif
  if a:col > l:old_pipes[-1]
    return len(a:result.lines[a:lin])
  endif
  let l:k = index(l:old_pipes, a:col)
  if l:k >= 0
    return l:new_pipes[min([l:k, len(l:new_pipes) - 1])]
  endif
  let l:bar = len(filter(copy(l:old_pipes), 'v:val < a:col')) - 1
  if l:bar + 1 >= len(l:new_pipes)
    " In a trailing empty bar that lint dropped (1.4): the tab's last pipe.
    return l:new_pipes[-1]
  endif

  " This bar's notes on every string.
  let l:notes = filter(copy(a:result.moves), 'v:val.bar == l:bar')
  for l:m in l:notes
    if l:m.line == a:lin && a:col >= l:m.from && a:col < l:m.from + l:m.len
      return l:m.to + a:col - l:m.from
    endif
  endfor

  let l:lo = l:new_pipes[l:bar] + 1
  let l:hi = l:new_pipes[l:bar + 1] - 1
  let l:prev = filter(copy(l:notes), 'v:val.from <= a:col')
  let l:next = filter(copy(l:notes), 'v:val.from > a:col')
  if !empty(l:next)
    let l:hi = min([l:hi, min(map(copy(l:next), 'v:val.to')) - 1])
  endif
  if !empty(l:prev)
    let l:from = max(map(copy(l:prev), 'v:val.from'))
    let l:to = max(map(filter(copy(l:prev), 'v:val.from == l:from'), 'v:val.to'))
    let l:lo = max([l:lo, l:to])
    let l:c = l:to + a:col - l:from
  elseif !empty(l:next)
    let l:first = sort(copy(l:next), {a, b -> a.from - b.from})[0]
    let l:c = l:first.to - (l:first.from - a:col)
  else
    let l:c = l:lo + a:col - l:old_pipes[l:bar] - 1
  endif
  return max([l:lo, min([l:c, l:hi])])
endfunction
