" autoload/songwriter/tab/annotations.vim - annotation lines (spec
" [Tablature][[Annotations]]): their words, and how they follow the music
" through an edit, given its column map (tab/colmap.vim). Pure.
"
" Columns here are display columns, which on a tab line are its byte columns;
" bytes are only reached from them where a line is read or written (Bytes).
" A word is {'col', 'width' (display cells), 'text', 'span' (it has an
" extender), 'parts': [{'col', 'width', 'text', 'fill' (an extender)}]}.
" A block's annotation lines are parsed once (Parse) into rows, top first:
" {'text' (the line), 'words'}, each word with 'anchored': whether it starts
" on a time column, which it then stands for (spec 3).
"
" One layout (s:layout) turns words placed at the columns they want into a
" line, left to right, one space at least between them: every line written
" goes through it.

" Spec 3: the annotation lines `above` as rows of words, top first, a word
" anchored when its first column is one of `cols` (the tab's time columns).
function! songwriter#tab#annotations#Parse(above, cols) abort
  return map(copy(a:above), {_, l -> {'text': l, 'words': map(songwriter#tab#annotations#Words(l),
        \ {_, w -> extend(w, {'anchored': index(a:cols, w.col) >= 0})})}})
endfunction

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
" to the tab under them, with the operations `ops` (optional) done (see
" Apply): Apply then Render, for annotations whose anchors do not matter.
function! songwriter#tab#annotations#Follow(above, map, ...) abort
  return songwriter#tab#annotations#Render(songwriter#tab#annotations#Apply(
        \ songwriter#tab#annotations#Parse(a:above, []), a:map, a:0 ? a:1 : [], []))
endfunction

" Spec 4: the annotation rows `rows` (Parse) once the edit of column map `map`
" is made to the tab under them, its lines being `lines`, and the operations
" `ops` done: the words placed where they want to go, before the layout, as
" rows, top first: {'text' (the line before), 'moved', 'words': placed words
" (s:place) with 'anchored'}. A label goes where its column goes, and with
" it; a span covers the columns it still covers, its labels at its ends, and
" goes with the last of them. The operations, their columns in `lines`, are
"   {'op': 'clear'}: every word goes (`cap`),
"   {'op': 'put', 'row' (0 for the line right above the strings, 1 for the
"   one above it...), 'col', 'text'}: a word an edit brings along, anchored
"   when it starts on a time column; a row past the top makes a new line,
"   {'op': 'label', 'col', 'text', 'add'}: a chord label written (s:label).
function! songwriter#tab#annotations#Apply(rows, map, ops, lines) abort
  let l:cols = songwriter#tab#model#NoteColumns(songwriter#tab#model#Parse(0, a:lines))
  let l:put = filter(copy(a:ops), 'v:val.op ==# "put"')
  let l:label = filter(copy(a:ops), 'v:val.op ==# "label"')
  let l:rows = empty(filter(copy(a:ops), 'v:val.op ==# "clear"')) ? a:rows
        \ : map(copy(a:rows), {_, r -> {'text': r.text, 'words': [], 'cleared': !empty(r.words)}})
  let l:n = max([len(l:rows)] + map(copy(l:put), 'v:val.row + 1'))
  let l:rows = repeat([{'text': '', 'words': []}], l:n - len(l:rows)) + l:rows
  let l:out = []
  for l:i in range(l:n)
    let l:row = l:n - 1 - l:i
    let l:words = []
    let l:moved = get(l:rows[l:i], 'cleared', 0)
    for l:w in l:rows[l:i].words
      let l:p = s:place(l:w, a:map)
      if empty(l:p)
        let l:moved = 1
      else
        let l:moved = l:moved || l:p.moved
        call add(l:words, extend(l:p, {'anchored': l:w.anchored}))
      endif
    endfor
    for l:p in filter(copy(l:put), 'v:val.row == l:row')
      call add(l:words, s:word(l:p.text, l:p.col, index(l:cols, l:p.col) >= 0))
      let l:moved = 1
    endfor
    call add(l:out, {'text': l:rows[l:i].text, 'moved': l:moved, 'words': l:words})
  endfor
  return empty(l:label) ? l:out : s:label(l:out, l:label[-1], a:lines)
endfunction

" A placed word (s:place) of `text` at column `col`.
function! s:word(text, col, anchored) abort
  return {'moved': 1, 'anchored': a:anchored, 'pieces': [{'text': a:text,
        \ 'width': strdisplaywidth(a:text), 'from': a:col}]}
endfunction

" True when placed word `word` is a label that is a chord.
function! s:is_chord(word) abort
  return len(a:word.pieces) == 1 && !has_key(a:word.pieces[0], 'fill')
        \ && !empty(songwriter#grammar#ParseChord(a:word.pieces[0].text))
endfunction

" Spec [Tablature][[Editing]] 10.9, [[Annotations]] 6: placed rows `rows`
" (Apply) with `label.text` as the chord label of column `label.col`, which
" it stands for: in place of the column's chord label (the first label,
" looking up from the line right above the strings, that starts on that
" column and is a chord), else, when `label.add` is set, on the line right
" above the strings, unless a word there is in the way however the tab is
" widened (one over the column, or starting over its notes): then on a new
" line under the others.
function! s:label(rows, label, lines) abort
  let l:new = s:word(a:label.text, a:label.col, 1)
  for l:i in range(len(a:rows) - 1, 0, -1)
    for l:k in range(len(a:rows[l:i].words))
      let l:w = a:rows[l:i].words[l:k]
      if s:is_chord(l:w) && s:start(l:w) == a:label.col
        let a:rows[l:i].words[l:k] = l:new
        let a:rows[l:i].moved = 1
        return a:rows
      endif
    endfor
  endfor
  if !a:label.add
    return a:rows
  endif
  let l:end = songwriter#tab#model#ColumnEnd(songwriter#tab#model#Parse(0, a:lines), a:label.col)
  if !empty(a:rows) && empty(filter(copy(s:layout(a:rows[-1].words).words),
        \ {_, w -> w.at <= a:label.col && w.end >= a:label.col || w.at > a:label.col && w.at <= l:end}))
    call add(a:rows[-1].words, l:new)
    let a:rows[-1].moved = 1
    return a:rows
  endif
  return a:rows + [{'text': '', 'moved': 1, 'words': [l:new]}]
endfunction

" The annotation lines of placed rows `rows` (Apply), laid out: a row whose
" words did not move is kept as it is, one left with no word is dropped.
function! songwriter#tab#annotations#Render(rows) abort
  let l:out = []
  for l:r in a:rows
    if !l:r.moved
      call add(l:out, l:r.text)
    elseif !empty(l:r.words)
      call add(l:out, s:layout(l:r.words).text)
    endif
  endfor
  return l:out
endfunction

" Spec 4.4: where the tab under placed rows `rows` (Apply), its lines being
" `lines`, must widen so that an anchored word the layout would push right
" stays on its column: {'offset', 'n'}, `n` dashes to insert after byte
" `offset` (right before the word's column, outside any note), the leftmost
" such place; {} for none. A word whose room would widen or move the word
" before it (a span over that place) stays pushed.
function! songwriter#tab#annotations#Room(rows, lines) abort
  let l:tab = songwriter#tab#model#Parse(0, a:lines)
  let l:best = {}
  for l:r in filter(copy(a:rows), 'v:val.moved')
    let l:laid = s:layout(l:r.words).words
    for l:k in range(1, max([len(l:laid) - 1, 0]))
      let l:w = l:laid[l:k]
      let l:want = s:start(l:w)
      if !l:w.anchored || l:w.at <= l:want
        continue
      endif
      let l:offset = s:outside_notes(l:tab, l:want - 1)
      if l:offset < songwriter#tab#model#BodyOffset() || s:last(l:laid[l:k - 1]) > l:offset
        continue
      endif
      if empty(l:best) || l:offset < l:best.offset
        let l:best = {'offset': l:offset, 'n': l:w.at - l:want}
      endif
    endfor
  endfor
  return l:best
endfunction

" The byte offset `offset` of `tab`'s lines, or before it, where no note runs
" across: inserting there splits none.
function! s:outside_notes(tab, offset) abort
  let l:offset = a:offset
  let l:again = 1
  while l:again
    let l:again = 0
    for l:s in a:tab.strings
      for l:n in l:s.notes
        if l:n.col <= l:offset && songwriter#tab#model#NoteEnd(l:n) > l:offset
          let [l:offset, l:again] = [l:n.col - 1, 1]
        endif
      endfor
    endfor
  endwhile
  return l:offset
endfunction

" The last column placed word `word` stands for: its start for a label, its
" end for a span.
function! s:last(word) abort
  let l:last = s:start(a:word)
  for l:p in a:word.pieces
    let l:last = max([l:last, has_key(l:p, 'fill') ? l:p.to : l:p.from])
  endfor
  return l:last
endfunction

" Spec 4.2, 4.5: the words of `above` that the edit of column map `map`
" deletes, as `put` operations (Apply), with their columns before the edit.
function! songwriter#tab#annotations#Cut(above, map) abort
  let l:cut = []
  for l:i in range(len(a:above))
    for l:w in songwriter#tab#annotations#Words(a:above[l:i])
      if empty(s:place(l:w, a:map))
        call add(l:cut, {'op': 'put', 'row': len(a:above) - 1 - l:i, 'col': l:w.col, 'text': l:w.text})
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

" The layout: the annotation line of placed words (s:place), left to right by
" where they want to start, one space at least between them, none before
" column 3. {'text', 'words': each placed word with 'at' and 'end', the
" columns it got, in the order laid out}.
function! s:layout(words) abort
  let l:words = sort(copy(a:words), {a, b -> s:start(a) - s:start(b)})
  let l:line = ''
  let l:next = songwriter#tab#model#BodyOffset() + 1
  let l:out = []
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
    call add(l:out, extend(copy(l:w), {'at': l:at, 'end': l:pos - 1}))
    let l:next = l:pos + 1
  endfor
  return {'text': l:line, 'words': l:out}
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

" Spec 5.2: the words of register rows `rows` (Rows), as `put` operations
" (Apply), at columns from `col`.
function! songwriter#tab#annotations#FromRows(rows, col) abort
  let l:put = []
  for l:i in range(len(a:rows))
    for l:w in songwriter#tab#annotations#Words(a:rows[l:i])
      call add(l:put, {'op': 'put', 'row': len(a:rows) - 1 - l:i, 'col': a:col + l:w.col - 1, 'text': l:w.text})
    endfor
  endfor
  return l:put
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

" The word of row `row` (Parse) under display column `col`, or {}.
function! songwriter#tab#annotations#At(row, col) abort
  for l:w in a:row.words
    if l:w.col <= a:col && a:col < l:w.col + l:w.width
      return l:w
    endif
  endfor
  return {}
endfunction

" Spec 8: the `count`-th word of `rows` (Parse) covering column `col`, looking
" up from the line right above the strings: {'i' (its row), 'word'}, or {}.
function! songwriter#tab#annotations#Over(rows, col, count) abort
  let l:n = a:count
  for l:i in range(len(a:rows) - 1, 0, -1)
    for l:w in a:rows[l:i].words
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

