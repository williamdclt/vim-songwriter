" autoload/songwriter/tab/colmap.vim - column maps: where each column of a
" block's lines is after an edit. Pure.
"
" A map is a list of steps, applied in order, so the identity is [] and
" composing is concatenating (Then). A column maps to a column of the edited
" lines, or to 0 when the edit deleted it. Columns past the end of the lines
" follow the steps like any other, so text after a tab's last pipe keeps its
" distance from it. See design.md "Column maps".

" `n` columns inserted after byte offset `offset` (0 = line start).
function! songwriter#tab#colmap#Insert(offset, n) abort
  return a:n > 0 ? [{'insert': a:offset, 'n': a:n}] : []
endfunction

" Columns [s, e] removed.
function! songwriter#tab#colmap#Delete(s, e) abort
  return a:e >= a:s ? [{'delete': a:s, 'e': a:e}] : []
endfunction

" The `old` columns from column `s` replaced by `new` columns: each keeps its
" offset from `s`, clamped to the new width; with `old` 0, an insertion before
" `s`; with `new` 0, a deletion.
function! songwriter#tab#colmap#Resize(s, old, new) abort
  if a:new == 0
    return songwriter#tab#colmap#Delete(a:s, a:s + a:old - 1)
  endif
  return a:old == a:new ? [] : [{'resize': a:s, 'old': a:old, 'new': a:new}]
endfunction

" A re-flow (lint): column c goes to Fn(c), computed when looked up.
function! songwriter#tab#colmap#Func(Fn) abort
  return [{'fn': a:Fn}]
endfunction

" `a`, then `b`.
function! songwriter#tab#colmap#Then(a, b) abort
  return a:a + a:b
endfunction

" Where column `col` goes through `map`, or 0 when it is deleted.
function! songwriter#tab#colmap#At(map, col) abort
  let l:c = a:col
  for l:s in a:map
    if l:c == 0
      return 0
    endif
    if has_key(l:s, 'insert')
      let l:c += l:c > l:s.insert ? l:s.n : 0
    elseif has_key(l:s, 'delete')
      let l:c = l:c < l:s.delete ? l:c : l:c <= l:s.e ? 0 : l:c - (l:s.e - l:s.delete + 1)
    elseif has_key(l:s, 'resize')
      if l:c >= l:s.resize + l:s.old
        let l:c += l:s.new - l:s.old
      elseif l:c >= l:s.resize
        let l:c = l:s.resize + min([l:c - l:s.resize, l:s.new - 1])
      endif
    else
      let l:c = l:s.fn(l:c)
    endif
  endfor
  return l:c
endfunction
