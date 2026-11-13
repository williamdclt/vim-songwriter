" autoload/songwriter/tab/annotate.vim - editing and reaching annotations from
" the strings (spec [Tablature][[Annotations]] 8, 9): the `ia`/`aa` text
" objects after an operator and in visual mode, and `gk`/`gj`. The buffer side;
" the pure parts are in tab/annotations.vim.

" The annotation word above the cursor's time column (the note's start on a
" note), the `count`-th one up, `around` adding its spaces (8): {'lnum',
" 'line', 'col', 'width' (display), 'text', 'byte', 'len' (its bytes)}, {'lnum',
" 'line', 'col', 'width': 0} for none, the line right above the strings
" (lnum 0 when there is none), or {} off a tab line.
function! s:target(around, count) abort
  let l:c = songwriter#tab#model#Cursor()
  if empty(l:c)
    return {}
  endif
  let l:note = songwriter#tab#model#NoteAt(l:c.line, l:c.col)
  let l:col = max([empty(l:note) ? l:c.col : l:note.col, songwriter#tab#model#BodyOffset() + 1])
  let l:block = l:c.block
  let l:over = songwriter#tab#annotations#Over(l:block.above, l:col, a:count)
  if empty(l:over)
    return {'lnum': empty(l:block.above) ? 0 : l:block.start - 1,
          \ 'line': empty(l:block.above) ? '' : l:block.above[-1], 'col': l:col, 'width': 0,
          \ 'start': l:block.start}
  endif
  let l:line = l:block.above[l:over.i]
  let l:w = l:over.word
  let [l:s, l:width] = [l:w.col, l:w.width]
  if a:around
    let l:words = songwriter#tab#annotations#Words(l:line)
    let l:k = index(map(copy(l:words), 'v:val.col'), l:w.col)
    if l:k + 1 < len(l:words)
      let l:width = l:words[l:k + 1].col - l:s
    elseif strdisplaywidth(l:line) == l:s + l:width - 1
      let l:prev = l:k > 0 ? l:words[l:k - 1].col + l:words[l:k - 1].width : songwriter#tab#model#BodyOffset() + 1
      let [l:s, l:width] = [l:prev, l:s + l:width - l:prev]
    else
      let l:width = strdisplaywidth(l:line) - l:s + 1
    endif
  endif
  let [l:byte, l:len] = songwriter#tab#annotations#Bytes(l:line, l:s, l:width)
  return {'lnum': l:block.top + l:over.i, 'line': l:line, 'col': l:s, 'width': l:width,
        \ 'text': strpart(l:line, l:byte - 1, l:len), 'byte': l:byte, 'len': l:len}
endfunction

" Spec 8: `ia` / `aa` after an operator (`around` 0 / 1): the keys that end the
" pending operator (operator.vim) and do it on the annotation word instead.
" `y` yanks it, `d` deletes it (Delete), `c` changes it with Vim's own `c`, or
" starts typing at the column when there is no word; Leave() then puts the
" next word back in place. Anything else does nothing.
function! songwriter#tab#annotate#Object(around) abort
  let l:op = songwriter#tab#operator#Pending()
  let l:t = s:target(a:around, v:count1)
  if empty(l:t) || l:t.width == 0 && l:op.op !=# 'c' || index(['d', 'y', 'c'], l:op.op) < 0
    return "\<Esc>"
  endif
  let l:reg = l:op.reg
  if l:op.op ==# 'y'
    call setreg(l:reg, l:t.text, 'v')
    return "\<Esc>"
  elseif l:op.op ==# 'd'
    return printf("\<Esc>\<Cmd>call songwriter#tab#annotate#Delete(%d, %d, %d, %s)\<CR>",
          \ l:t.lnum, l:t.col, l:t.width, string(l:reg))
  endif
  let l:keys = "\<Esc>"
  if l:t.width > 0
    let l:keys .= printf("\<Cmd>call cursor(%d, %d)\<CR>\"%sc%dl", l:t.lnum, l:t.byte, l:reg, strchars(l:t.text))
    let l:mark = {'prefix': strpart(l:t.line, 0, l:t.byte - 1), 'rest': strpart(l:t.line, l:t.byte - 1 + l:t.len)}
  elseif l:t.lnum == 0
    let l:pad = repeat(' ', l:t.col - 1)
    let l:keys .= printf("\<Cmd>call cursor(%d, 1)\<CR>O", l:t.start) . l:pad
    let [l:t.lnum, l:mark] = [l:t.start, {'prefix': l:pad, 'rest': ''}]
  else
    let l:at = songwriter#tab#annotations#Bytes(l:t.line, l:t.col, 1)
    if empty(l:at)
      let l:pad = repeat(' ', l:t.col - 1 - strdisplaywidth(l:t.line))
      let l:keys .= printf("\<Cmd>call cursor(%d, 1)\<CR>A", l:t.lnum) . l:pad
      let l:mark = {'prefix': l:t.line . l:pad, 'rest': ''}
    else
      let l:keys .= printf("\<Cmd>call cursor(%d, %d)\<CR>i", l:t.lnum, l:at[0])
      let l:mark = {'prefix': strpart(l:t.line, 0, l:at[0] - 1), 'rest': strpart(l:t.line, l:at[0] - 1)}
    endif
  endif
  let b:songwriter_annotating = extend(l:mark, {'lnum': l:t.lnum, 'col': l:t.col, 'width': l:t.width})
  return l:keys
endfunction

" Spec 8.3: `ia` / `aa` in visual mode select the annotation word.
function! songwriter#tab#annotate#Select(around) abort
  let l:t = s:target(a:around, v:count1)
  if empty(l:t) || l:t.width == 0
    return
  endif
  let l:last = songwriter#tab#annotations#Bytes(l:t.line, l:t.col + l:t.width - 1, 1)[0]
  execute "normal! \<Esc>"
  call cursor(l:t.lnum, l:t.byte)
  normal! v
  call cursor(l:t.lnum, l:last)
endfunction

" Spec 8.1: delete the `width` display columns from `col` of annotation line
" `lnum` into register `reg`, the next word staying where it is; a line left
" empty goes.
function! songwriter#tab#annotate#Delete(lnum, col, width, reg) abort
  let l:line = getline(a:lnum)
  let [l:byte, l:len] = songwriter#tab#annotations#Bytes(l:line, a:col, a:width)
  call setreg(a:reg, strpart(l:line, l:byte - 1, l:len), 'v')
  call s:set(a:lnum, songwriter#tab#annotations#Retype(strpart(l:line, 0, l:byte - 1),
        \ strpart(l:line, l:byte - 1 + l:len), a:col, a:width, ''))
endfunction

" Spec 8.2, on leaving insert mode after `cia`: the line with what was typed
" in place of the word, the next word back where it was or pushed right
" (annotations#Retype), in the same undo step; a line left empty goes.
function! songwriter#tab#annotate#Leave() abort
  if !exists('b:songwriter_annotating')
    return
  endif
  let l:m = b:songwriter_annotating
  unlet b:songwriter_annotating
  let l:line = getline(l:m.lnum)
  let l:typed = len(l:line) - len(l:m.prefix) - len(l:m.rest)
  if l:typed >= 0 && strpart(l:line, 0, len(l:m.prefix)) ==# l:m.prefix
        \ && strpart(l:line, len(l:line) - len(l:m.rest)) ==# l:m.rest
    let l:new = songwriter#tab#annotations#Retype(l:m.prefix, l:m.rest, l:m.col, l:m.width,
          \ strpart(l:line, len(l:m.prefix), l:typed))
  else
    let l:new = substitute(l:line, '\s*$', '', '')
  endif
  if l:new !=# l:line
    silent! undojoin
    call s:set(l:m.lnum, l:new)
  endif
endfunction

" Set line `lnum` to `line`, deleting it when it is empty.
function! s:set(lnum, line) abort
  if a:line ==# ''
    call deletebufline('%', a:lnum)
  else
    call setline(a:lnum, a:line)
  endif
endfunction

" Spec 9: `gk`. From a string, to the annotation line right above the
" strings; from an annotation line, to the one above it. The string and
" column the moves started from are kept (state.vim 'upward') while the buffer
" is unchanged, so the column is kept through short lines and `gj` comes back.
function! songwriter#tab#annotate#Up() abort
  if songwriter#grammar#IsTabLine(getline('.'))
    let l:block = songwriter#tab#model#Read()
    if empty(l:block.above)
      return
    endif
    call songwriter#tab#state#Set('upward', {'top': l:block.top, 'lnum': line('.'), 'col': virtcol('.')})
    call s:land(l:block.start - 1, virtcol('.'))
    return
  endif
  let l:block = songwriter#tab#model#Around(line('.'))
  if !empty(l:block) && line('.') > l:block.top
    call s:land(line('.') - 1, s:column(l:block))
  endif
endfunction

" Spec 9: `gj` on an annotation line: to the one below, or from the one right
" above the strings to the string the moves started from (the top string when
" unknown).
function! songwriter#tab#annotate#Down() abort
  let l:block = songwriter#tab#model#Around(line('.'))
  if empty(l:block)
    return
  endif
  if line('.') < l:block.start - 1
    call s:land(line('.') + 1, s:column(l:block))
    return
  endif
  let l:from = songwriter#tab#state#Get('upward')
  let [l:lnum, l:col] = !empty(l:from) && l:from.top == l:block.top
        \ ? [l:from.lnum, l:from.col] : [l:block.start, virtcol('.')]
  call cursor(l:lnum, 1)
  execute 'normal! ' . l:col . '|'
endfunction

" The display column the moves through `block`'s annotations keep.
function! s:column(block) abort
  let l:from = songwriter#tab#state#Get('upward')
  return !empty(l:from) && l:from.top == a:block.top ? l:from.col : virtcol('.')
endfunction

" Put the cursor on line `lnum` at display column `col`, or at its end when
" it is shorter.
function! s:land(lnum, col) abort
  let l:at = songwriter#tab#annotations#Bytes(getline(a:lnum), a:col, 1)
  call cursor(a:lnum, empty(l:at) ? max([1, len(getline(a:lnum))]) : l:at[0])
endfunction
