" autoload/songwriter/tab/annotations.vim - annotation lines (spec
" [Tablature][[Annotations]]): their words, and how they follow the music
" through an edit, given its column map (tab/colmap.vim). Pure.
"
" Columns here are display columns, which on a tab line are its byte columns.
" A word is {'col', 'width' (display cells), 'text', 'span' (it has an
" extender), 'parts': [{'col', 'width', 'text', 'fill' (an extender)}]}.

" The words of an annotation line, left to right.
function! songwriter#tab#annotations#Words(line) abort
  let l:words = []
  let l:word = {}
  let l:vcol = 0
  for l:ch in split(a:line, '\zs')
    let l:width = strdisplaywidth(l:ch, l:vcol)
    if l:ch =~# '\s'
      if !empty(l:word)
        call add(l:words, s:parts(l:word))
        let l:word = {}
      endif
    else
      if empty(l:word)
        let l:word = {'col': l:vcol + 1, 'width': 0, 'text': ''}
      endif
      let l:word.text .= l:ch
      let l:word.width += l:width
    endif
    let l:vcol += l:width
  endfor
  if !empty(l:word)
    call add(l:words, s:parts(l:word))
  endif
  return l:words
endfunction

" `word` split into its parts: extenders and what is between them.
function! s:parts(word) abort
  let l:parts = []
  let l:at = 0
  while l:at < len(a:word.text)
    let l:m = matchstrpos(a:word.text, songwriter#grammar#Extender(), l:at)
    let l:end = l:m[1] < 0 ? len(a:word.text) : l:m[1]
    if l:end > l:at
      call add(l:parts, s:part(a:word, l:at, strpart(a:word.text, l:at, l:end - l:at), 0))
    endif
    if l:m[1] < 0
      break
    endif
    call add(l:parts, s:part(a:word, l:m[1], l:m[0], 1))
    let l:at = l:m[2]
  endwhile
  return extend(a:word, {'parts': l:parts, 'span': !empty(filter(copy(l:parts), 'v:val.fill'))})
endfunction

function! s:part(word, byte, text, fill) abort
  return {'col': a:word.col + strdisplaywidth(strpart(a:word.text, 0, a:byte)),
        \ 'width': strdisplaywidth(a:text), 'text': a:text, 'fill': a:fill}
endfunction

" Spec 4: annotation lines `above` once the edit of column map `map` is made
" to the tab under them. A label goes where its column goes, and with it; a
" span covers the columns it still covers, its labels at its ends, and goes
" with the last of them. Words are laid out left to right, one space at
" least between them, never in the first two columns; a line whose words did
" not move is kept as it is, and a line left with no word is dropped.
" `put` (optional) adds words: [{'row' (0 for the line right above the
" strings, 1 for the one above it...), 'col' (in the edited tab), 'text'}];
" a row past the top makes a new line there.
function! songwriter#tab#annotations#Follow(above, map, ...) abort
  let l:put = a:0 ? a:1 : []
  let l:rows = max([len(a:above)] + map(copy(l:put), 'v:val.row + 1'))
  let l:lines = repeat([''], l:rows - len(a:above)) + a:above
  let l:out = []
  for l:i in range(l:rows)
    let l:row = l:rows - 1 - l:i
    let l:words = map(songwriter#tab#annotations#Words(l:lines[l:i]), 's:place(v:val, a:map)')
    let l:moved = !empty(filter(copy(l:words), 'empty(v:val) || v:val.moved'))
    let l:words = filter(l:words, '!empty(v:val)')
    for l:p in filter(copy(l:put), 'v:val.row == l:row')
      call add(l:words, {'moved': 1, 'pieces': [{'text': l:p.text,
            \ 'width': strdisplaywidth(l:p.text), 'from': l:p.col}]})
      let l:moved = 1
    endfor
    if !l:moved
      call add(l:out, l:lines[l:i])
    elseif !empty(l:words)
      call add(l:out, s:render(l:words))
    endif
  endfor
  return l:out
endfunction

" Spec 4.2, 4.5: the words of `above` that the edit of column map `map`
" deletes, as `put` takes them (Follow), with their columns before the edit.
function! songwriter#tab#annotations#Cut(above, map) abort
  let l:cut = []
  for l:i in range(len(a:above))
    for l:w in songwriter#tab#annotations#Words(a:above[l:i])
      if empty(s:place(l:w, a:map))
        call add(l:cut, {'row': len(a:above) - 1 - l:i, 'col': l:w.col, 'text': l:w.text})
      endif
    endfor
  endfor
  return l:cut
endfunction

" Where `word` goes through `map`: {'moved', 'pieces': [{'text', 'width',
" 'from'} for a label part, {'fill', 'from' (a leading extender's start, else
" 0), 'to' (a trailing extender's end, else 0)} for an extender]}, or {} when
" it is deleted.
function! s:place(word, map) abort
  if !a:word.span
    let l:at = songwriter#tab#colmap#At(a:map, a:word.col)
    return l:at == 0 ? {} : {'moved': l:at != a:word.col,
          \ 'pieces': [{'text': a:word.text, 'width': a:word.width, 'from': l:at}]}
  endif
  let l:end = a:word.col + a:word.width - 1
  let l:first = s:survivor(a:map, range(a:word.col, l:end))
  if l:first == 0
    return {}
  endif
  let l:last = s:survivor(a:map, range(l:end, a:word.col, -1))
  let l:pieces = []
  let l:moved = 0
  let l:n = len(a:word.parts)
  for l:k in range(l:n)
    let l:p = a:word.parts[l:k]
    if l:p.fill
      let l:piece = {'fill': l:p.text[0], 'from': 0, 'to': 0}
      if l:k == 0
        let l:piece.from = songwriter#tab#colmap#At(a:map, l:first)
        let l:moved = l:moved || l:piece.from != l:p.col
      endif
      if l:k == l:n - 1
        let l:piece.to = songwriter#tab#colmap#At(a:map, l:last)
        let l:moved = l:moved || l:piece.to != l:p.col + l:p.width - 1
      endif
    else
      let l:at = songwriter#tab#colmap#At(a:map, l:p.col)
      if l:at == 0 && l:k == 0
        let l:at = songwriter#tab#colmap#At(a:map, l:first)
      elseif l:at == 0 && l:k == l:n - 1
        let l:at = songwriter#tab#colmap#At(a:map, l:last) - l:p.width + 1
      elseif l:at == 0
        continue
      endif
      let l:piece = {'text': l:p.text, 'width': l:p.width, 'from': l:at}
      let l:moved = l:moved || l:at != l:p.col
    endif
    call add(l:pieces, l:piece)
  endfor
  " An extender between two parts moves when they do not keep its width.
  let l:moved = l:moved || len(l:pieces) != l:n
  return {'moved': l:moved, 'pieces': l:pieces}
endfunction

" The column the first of `cols` that `map` keeps goes to, 0 for none: its
" own column, before the edit.
function! s:survivor(map, cols) abort
  for l:c in a:cols
    if songwriter#tab#colmap#At(a:map, l:c) > 0
      return l:c
    endif
  endfor
  return 0
endfunction

" An annotation line of placed words (s:place), left to right by where they
" want to start, one space at least between them, none before column 3.
function! s:render(words) abort
  let l:words = sort(copy(a:words), {a, b -> s:start(a) - s:start(b)})
  let l:line = ''
  let l:next = songwriter#tab#model#BodyOffset() + 1
  for l:w in l:words
    let l:text = ''
    let l:at = max([s:start(l:w), l:next])
    let l:pos = l:at
    let l:pieces = l:w.pieces
    for l:k in range(len(l:pieces))
      let l:p = l:pieces[l:k]
      if has_key(l:p, 'fill')
        let l:to = l:p.to > 0 ? l:p.to
              \ : l:k + 1 < len(l:pieces) ? l:pieces[l:k + 1].from - 1 : l:pos + 1
        let l:width = max([2, l:to - l:pos + 1])
        let l:text .= repeat(l:p.fill, l:width)
        let l:pos += l:width
      else
        let l:pos = max([l:p.from, l:pos])
        let l:text .= repeat(' ', l:pos - l:at - strdisplaywidth(l:text)) . l:p.text
        let l:pos += l:p.width
      endif
    endfor
    let l:line .= repeat(' ', l:at - 1 - strdisplaywidth(l:line)) . l:text
    let l:next = l:pos + 1
  endfor
  return l:line
endfunction

" Where a placed word wants to start.
function! s:start(word) abort
  let l:p = a:word.pieces[0]
  return has_key(l:p, 'fill') ? (l:p.from > 0 ? l:p.from : l:p.to - 1) : l:p.from
endfunction

" Spec 5.1: the register rows of the words `words` (as Cut gives them), at
" columns from `col`: one row per annotation row, the highest first, each word
" at its offset from `col`. [] for no word.
function! songwriter#tab#annotations#Rows(words, col) abort
  if empty(a:words)
    return []
  endif
  let l:n = max(map(copy(a:words), 'v:val.row')) + 1
  let l:rows = repeat([''], l:n)
  for l:w in sort(copy(a:words), {a, b -> a.col - b.col})
    let l:i = l:n - 1 - l:w.row
    let l:pad = max([l:w.col - a:col - strdisplaywidth(l:rows[l:i]), empty(l:rows[l:i]) ? 0 : 1])
    let l:rows[l:i] .= repeat(' ', l:pad) . l:w.text
  endfor
  return l:rows
endfunction

" Spec 5.2: the words of register rows `rows` (Rows), as Follow's `put` takes
" them, at columns from `col`.
function! songwriter#tab#annotations#FromRows(rows, col) abort
  let l:put = []
  for l:i in range(len(a:rows))
    for l:w in songwriter#tab#annotations#Words(a:rows[l:i])
      call add(l:put, {'row': len(a:rows) - 1 - l:i, 'col': a:col + l:w.col - 1, 'text': l:w.text})
    endfor
  endfor
  return l:put
endfunction

" Spec 6: annotation lines `above` with `text` written at column `col`: on the
" last line (right above the strings) when it fits there, with a blank or the
" line's end on each side, else on a new line under the others.
function! songwriter#tab#annotations#Add(above, col, text) abort
  let l:width = strdisplaywidth(a:text)
  let l:last = empty(a:above) ? '' : a:above[-1]
  let l:free = !empty(a:above) && empty(filter(songwriter#tab#annotations#Words(l:last),
        \ {_, w -> w.col <= a:col + l:width && w.col + w.width - 1 >= a:col - 1}))
  if !l:free
    return a:above + [repeat(' ', a:col - 1) . a:text]
  endif
  let l:at = s:byte_at(l:last, a:col)
  let l:line = l:at < 0 ? l:last . repeat(' ', a:col - 1 - strdisplaywidth(l:last)) . a:text
        \ : strpart(l:last, 0, l:at) . a:text . strpart(l:last, l:at + l:width)
  return a:above[: -2] + [l:line]
endfunction

" The byte index where display column `col` of `line` starts, -1 past its end.
function! s:byte_at(line, col) abort
  let l:vcol = 0
  let l:byte = 0
  for l:ch in split(a:line, '\zs')
    if l:vcol + 1 >= a:col
      return l:byte
    endif
    let l:vcol += strdisplaywidth(l:ch, l:vcol)
    let l:byte += len(l:ch)
  endfor
  return -1
endfunction

" The bytes of display columns [col, col + width - 1] of `line`: [first byte
" column (1-indexed), byte length], or [] when the line ends before `col`.
function! songwriter#tab#annotations#Bytes(line, col, width) abort
  let l:start = s:byte_at(a:line, a:col)
  if l:start < 0
    return []
  endif
  let l:end = s:byte_at(a:line, a:col + a:width)
  return [l:start + 1, (l:end < 0 ? len(a:line) : l:end) - l:start]
endfunction

" Spec 8: the `count`-th word of `above` covering column `col`, looking up from
" the line right above the strings: {'i' (its line in `above`), 'word'}, or {}.
function! songwriter#tab#annotations#Over(above, col, count) abort
  let l:n = a:count
  for l:i in range(len(a:above) - 1, 0, -1)
    for l:w in songwriter#tab#annotations#Words(a:above[l:i])
      if l:w.col <= a:col && a:col < l:w.col + l:w.width
        let l:n -= 1
        if l:n == 0
          return {'i': l:i, 'word': l:w}
        endif
      endif
    endfor
  endfor
  return {}
endfunction

" Spec 8.1, 8.2: an annotation line with the `width` display columns from
" column `col` replaced by `typed`, `prefix` and `rest` being the text before
" and after them: the next word stays where it was, unless `typed` runs into
" it, then it goes one space after it. No spaces at the end.
function! songwriter#tab#annotations#Retype(prefix, rest, col, width, typed) abort
  let l:words = substitute(a:rest, '^\s*', '', '')
  let l:line = a:prefix . a:typed
  if l:words !=# ''
    let l:next = a:col + a:width + strdisplaywidth(a:rest) - strdisplaywidth(l:words)
    let l:end = a:col + strdisplaywidth(a:typed)
    let l:at = a:typed ==# '' ? l:next : max([l:next, l:end + 1])
    let l:line .= repeat(' ', l:at - l:end) . l:words
  endif
  return substitute(l:line, '\s*$', '', '')
endfunction

" Spec [Tablature][[Editing]] 10.9: the chord label of column `col` in
" annotation lines `above`: the first label, looking up from the line right
" above the strings, that starts on that column and is a chord. {'i' (its
" line in `above`), 'word'}, or {}.
function! songwriter#tab#annotations#ChordLabel(above, col) abort
  for l:i in range(len(a:above) - 1, 0, -1)
    for l:w in songwriter#tab#annotations#Words(a:above[l:i])
      if l:w.col == a:col && !l:w.span && !empty(songwriter#grammar#ParseChord(l:w.text))
        return {'i': l:i, 'word': l:w}
      endif
    endfor
  endfor
  return {}
endfunction

" Spec [Tablature][[Editing]] 10.9, [[Annotations]] 6: annotation lines
" `above` with `text` as the chord label of column `col`: in place of the
" column's chord label, the next word staying where it is unless `text` runs
" into it (Retype), else, when `add` is set, written as Add does. Unchanged
" when there is no chord label and `add` is not set.
function! songwriter#tab#annotations#Label(above, col, text, add) abort
  let l:label = songwriter#tab#annotations#ChordLabel(a:above, a:col)
  if empty(l:label)
    return a:add ? songwriter#tab#annotations#Add(a:above, a:col, a:text) : a:above
  endif
  let l:line = a:above[l:label.i]
  let [l:byte, l:len] = songwriter#tab#annotations#Bytes(l:line, l:label.word.col, l:label.word.width)
  let l:above = copy(a:above)
  let l:above[l:label.i] = songwriter#tab#annotations#Retype(strpart(l:line, 0, l:byte - 1),
        \ strpart(l:line, l:byte - 1 + l:len), l:label.word.col, l:label.word.width, a:text)
  return l:above
endfunction
