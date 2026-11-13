" autoload/songwriter/tab/paste.vim - pasting blockwise registers into a tab
" (spec [Tablature][[Editing]] 6.5, 6.9.4, 6.14), pure: rows matched to the
" strings, then inserted or overlaid. Block lines are 0-indexed (`lin`).

" Spec 6.5.3: register rows for a block with `names`, matched from the bottom
" string. `regnames` is [] when unknown. {'rows', 'msg'} or {'error'}.
function! songwriter#tab#paste#MatchRows(names, rows, regnames) abort
  let l:ns = len(a:names)
  let l:nr = len(a:rows)
  let l:width = max(map(copy(a:rows), 'len(v:val)'))
  let l:rows = map(copy(a:rows), 'songwriter#tab#model#Pad(v:val, l:width)')
  if l:ns == l:nr
    return {'rows': l:rows, 'msg': ''}
  endif
  let l:filler = substitute(l:rows[0], songwriter#grammar#NotPipe(), '-', 'g')
  let l:out = []
  for l:i in range(l:ns)
    let l:j = l:i - (l:ns - l:nr)
    if l:j < 0
      call add(l:out, l:filler)
      continue
    endif
    if !empty(a:regnames) && a:regnames[l:j] !=# a:names[l:i]
      return {'error': printf('songwriter: string names differ (register vs tab): %s vs %s',
            \ a:regnames[l:j], a:names[l:i])}
    endif
    call add(l:out, l:rows[l:j])
  endfor
  let l:msgs = []
  if empty(a:regnames)
    call add(l:msgs, 'strings matched by position')
  endif
  let l:dropped = 0
  for l:j in range(max([l:nr - l:ns, 0]))
    let l:dropped += len(songwriter#tab#model#RowNotes(l:rows[l:j]))
  endfor
  if l:dropped > 0
    call add(l:msgs, l:dropped . ' notes dropped')
  endif
  return {'rows': l:out, 'msg': empty(l:msgs) ? '' : 'songwriter: ' . join(l:msgs, ', ')}
endfunction

" Spec 6.5: paste blockwise register `rows` (source string names `regnames`,
" [] when unknown) into the block, from column `col` of line `lin`; `before`
" for `P`; `count` copies. A register holding a pipe is a bar register (6.5.2),
" pasted at a bar line; otherwise a column register (6.5.1), pasted after /
" before the cursor's column and its gap. `above` (optional): the register's
" annotation rows ([[Annotations]] 5.2), put above each copy. Returns {'lines',
" 'col' (first pasted note, any string), 'msg', 'map', 'put' (the annotation
" words, see annotations#Follow)} or {'error'}.
function! songwriter#tab#paste#Paste(lines, lin, col, rows, regnames, before, count, ...) abort
  let l:names = songwriter#tab#model#Names(a:lines)
  let l:m = songwriter#tab#paste#MatchRows(l:names, a:rows, a:regnames)
  if has_key(l:m, 'error')
    return l:m
  endif
  let l:rows = l:m.rows
  let l:line = a:lines[a:lin]
  let l:col = max([a:col, songwriter#tab#model#BodyOffset()])
  let l:shift = 0
  if !empty(filter(copy(l:rows), "stridx(v:val, '|') >= 0"))
    " The annotations of a leading pipe's column go to the pipe it is pasted
    " after.
    let l:shift = l:rows[0] =~# songwriter#grammar#LeadingPipe() ? -1 : 0
    call map(l:rows, "substitute(v:val, songwriter#grammar#LeadingPipe(), '', '')")
    call map(l:rows, "v:val =~# songwriter#grammar#FinalPipe() ? v:val : v:val . '|'")
    let l:pipes = songwriter#tab#model#Pipes(l:line)
    if index(l:pipes, l:col) >= 0
      let l:offset = l:col
    else
      let l:bar = songwriter#tab#model#BarAt(l:line, l:col)
      let l:offset = a:before ? l:bar.start : (l:bar.end > 0 ? l:bar.end : len(l:line))
    endif
  else
    let l:tab = songwriter#tab#model#Parse(0, a:lines)
    let l:bc = songwriter#tab#model#BarColumns(l:tab, a:lin, l:col)
    let l:c = songwriter#tab#model#ColumnFor(l:bc.cols, l:col)
    if l:c == 0
      let l:offset = l:bc.bar.start + 2
    else
      let l:offset = a:before ? l:c - 1 : songwriter#tab#model#GapEnd(l:tab, a:lin, l:bc, l:c)
    endif
  endif
  let l:res = s:insert_rows(a:lines, l:offset, l:rows, a:count, a:0 ? a:1 : [])
  call map(l:res.put, {_, p -> extend(p, {'col': p.col + l:shift})})
  let l:res.msg = l:m.msg
  return l:res
endfunction

" Spec 6.9.4: paste register `rows` right after byte `offset` (0 = line
" start), rows matched as in Paste, annotation rows `above` (optional) above
" them. {'lines', 'col', 'msg', 'map', 'put'} or {'error'}.
function! songwriter#tab#paste#PasteAt(lines, offset, rows, regnames, ...) abort
  let l:m = songwriter#tab#paste#MatchRows(songwriter#tab#model#Names(a:lines), a:rows, a:regnames)
  if has_key(l:m, 'error')
    return l:m
  endif
  let l:res = s:insert_rows(a:lines, a:offset, l:m.rows, 1, a:0 ? a:1 : [])
  let l:res.msg = l:m.msg
  return l:res
endfunction

" Insert `count` copies of `rows` after byte `offset` on every line, the
" annotation rows `above` above each copy. Returns {'lines', 'col': the first
" inserted note on any string, 'map', 'put'}.
function! s:insert_rows(lines, offset, rows, count, above) abort
  let l:width = len(a:rows[0])
  let l:put = []
  for l:k in range(max([a:count, 1]))
    call extend(l:put, songwriter#tab#annotations#FromRows(a:above, a:offset + 1 + l:k * l:width))
  endfor
  let l:rows = map(copy(a:rows), 'repeat(v:val, max([a:count, 1]))')
  let l:out = []
  for l:i in range(len(a:lines))
    let l:l = songwriter#tab#model#Pad(a:lines[l:i], a:offset)
    call add(l:out, strpart(l:l, 0, a:offset) . l:rows[l:i] . strpart(l:l, a:offset))
  endfor
  let l:first = 0
  for l:r in l:rows
    let l:p = match(l:r, songwriter#grammar#Note())
    if l:p >= 0 && (l:first == 0 || l:p + 1 < l:first)
      let l:first = l:p + 1
    endif
  endfor
  return {'lines': l:out, 'col': a:offset + max([l:first, 1]),
        \ 'map': songwriter#tab#colmap#Insert(a:offset, len(l:rows[0])), 'put': l:put}
endfunction

" Spec 6.14: write the notes of column register `rows` onto the time column at
" `col` of line `lin`, without adding time: the register's first note column
" lands on that column. Rows are matched as in Paste. Returns {'lines', 'col',
" 'msg', 'map'} (no time column moves), or {'error'} for a bar register, no
" column there, or a note that would replace anything but dashes.
function! songwriter#tab#paste#Overlay(lines, lin, col, rows, regnames) abort
  if !empty(filter(copy(a:rows), "stridx(v:val, '|') >= 0"))
    return {'error': 'songwriter: gp pastes a column, not a bar'}
  endif
  let l:m = songwriter#tab#paste#MatchRows(songwriter#tab#model#Names(a:lines), a:rows, a:regnames)
  if has_key(l:m, 'error')
    return l:m
  endif
  let l:c = 0
  if !songwriter#tab#columns#OnPipeOrName(a:lines[a:lin], a:col)
    let l:c = songwriter#tab#model#ColumnFor(songwriter#tab#model#BarColumns(
          \ songwriter#tab#model#Parse(0, a:lines), a:lin, a:col).cols, a:col)
  endif
  if l:c == 0
    return {'error': 'songwriter: gp needs a note column under the cursor'}
  endif
  let l:atoms = map(copy(l:m.rows), 'songwriter#tab#model#RowChains(v:val)')
  let l:starts = []
  for l:r in l:m.rows
    call extend(l:starts, map(songwriter#tab#model#RowNotes(l:r), 'v:val.col'))
  endfor
  if empty(l:starts)
    return {'lines': copy(a:lines), 'col': l:c, 'msg': l:m.msg, 'map': []}
  endif
  let l:qmin = min(l:starts)
  let l:out = copy(a:lines)
  for l:i in range(len(l:out))
    for l:a in l:atoms[l:i]
      let l:s = l:c + l:a.col - l:qmin
      let l:line = songwriter#tab#model#Pad(l:out[l:i], l:s + l:a.len)
      if strpart(l:line, l:s - 1, l:a.len) !~# songwriter#grammar#OnlyDashes()
        return {'error': printf('songwriter: gp would replace a note on string %s', songwriter#tab#model#Name(a:lines[l:i]))}
      endif
      let l:out[l:i] = songwriter#tab#model#Splice(l:line, l:s, l:a.len, l:a.text)
    endfor
  endfor
  return {'lines': l:out, 'col': l:c, 'msg': l:m.msg, 'map': []}
endfunction
