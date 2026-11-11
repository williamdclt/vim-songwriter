" autoload/songwriter/tab/edit.vim - the buffer side of a tablature edit.
"
" A tablature-mode edit is a pure function (tab/columns.vim, tab/strings.vim,
" tab/slots.vim...) returning a result; this module does the rest. A result is
" a dict with any of
"   'lines': the block's new lines,
"   'col':   the cursor column,
"   'lin':   the cursor's 0-indexed line in the block (with 'col'; default:
"            stays),
"   'msg':   a message to echo,
"   'error': a refusal to show; nothing else is applied,
"   'state': {name: value} to record in tab/state.vim once written, each value
"            completed with the cursor's 'line' and 'col' (Do only).
" {} means nothing to do.
"
" Do() is the whole edit: what it does with an open slot, the undo step it
" joins, the lints before and after (spec [Tablature][[Editing]] 4), the
" insert state, the state for the next key, and `.`. The rest are its parts,
" for the entry points that are not one edit at the cursor.

" Show a refusal.
function! songwriter#tab#edit#Error(msg) abort
  echohl ErrorMsg
  echo a:msg
  echohl None
endfunction

" Pure. `lines` linted, with column `col` of line `lin` (0-indexed) followed
" through the lint so that it stays on the same note, or in the same gap
" between notes (lint#FollowColumn): {'lines', 'col'}. A `lin` outside the
" block keeps its column.
function! songwriter#tab#edit#Linted(lines, lin, col) abort
  let l:result = songwriter#tab#lint#Lint(a:lines)
  let l:col = a:lin >= 0 && a:lin < len(a:lines)
        \ ? songwriter#tab#lint#FollowColumn(a:lines, l:result, a:lin, a:col) : a:col
  return {'lines': l:result.lines, 'col': l:col}
endfunction

" Lint `block`, write it back and keep the cursor on the same note (or in the
" same gap between notes) when it is inside the block. Returns the re-read
" block, or {} when `block` is empty.
function! songwriter#tab#edit#LintAndFollow(block) abort
  if empty(a:block)
    return {}
  endif
  let l:lin = songwriter#tab#model#CursorLin(a:block)
  let l:linted = songwriter#tab#edit#Linted(a:block.lines, l:lin, col('.'))
  call songwriter#tab#model#Write(a:block, l:linted.lines)
  if l:lin >= 0 && l:lin < len(a:block.lines)
    call cursor(line('.'), l:linted.col)
  endif
  return songwriter#tab#model#Read(a:block.start)
endfunction

" Write a result's lines and move the cursor, without linting.
function! songwriter#tab#edit#Apply(block, result) abort
  if has_key(a:result, 'lines')
    call songwriter#tab#model#Write(a:block, a:result.lines)
  endif
  if has_key(a:result, 'col')
    call cursor(has_key(a:result, 'lin') ? a:block.start + a:result.lin : line('.'), a:result.col)
  endif
endfunction

" Apply a result to `block`, linted with the cursor kept on the music, in one
" write, and echo its message. Returns the linted block, or {} when the result
" was a refusal or nothing to do.
function! songwriter#tab#edit#Commit(block, result) abort
  if has_key(a:result, 'error')
    call songwriter#tab#edit#Error(a:result.error)
    return {}
  endif
  if empty(a:result)
    return {}
  endif
  let l:lin = songwriter#tab#model#CursorLin(a:block)
  let l:col = col('.')
  if has_key(a:result, 'col')
    let l:lin = get(a:result, 'lin', l:lin)
    let l:col = a:result.col
  endif
  let l:lines = get(a:result, 'lines', a:block.lines)
  if l:lin >= 0 && l:lin < len(l:lines)
    " As the cursor would be once there: on the line, at most on its end.
    let l:col = max([1, min([l:col, len(l:lines[l:lin])])])
  endif
  let l:linted = songwriter#tab#edit#Linted(l:lines, l:lin, l:col)
  call songwriter#tab#model#Write(a:block, l:linted.lines)
  call cursor(l:lin >= 0 && l:lin < len(l:lines) ? a:block.start + l:lin : line('.'), l:linted.col)
  if !empty(get(a:result, 'msg', ''))
    echo a:result.msg
  endif
  return songwriter#tab#model#Read(a:block.start)
endfunction

" A whole edit at the cursor: Fn(ctx) gives its result (see the top), ctx
" being model#Cursor() plus 'insert' (whether the insert state is on).
" `opts` (all optional):
"   'slot':    the open slot (spec 4.3): 'close' closes it first, 'motion'
"              closes it keeping the lint (4.3.3), 'fill' means the edit fills
"              it (joined to its undo step, then forgotten); default: left as
"              it is.
"   'join':    join the previous undo step.
"   'prelint': lint the block first (default 1).
"   'lint':    lint the result (default 1); without, it is only applied.
"   'open':    the edit opens a slot on side 1 (`a`), -1 (`i`) or 0 (empty
"              bar): closing it gives back the block as it was before the
"              edit, prelint included (slots#Mark, slots#Open).
"   'insert':  keep the insert state when it is on (default: an edit ends it).
"   'repeat':  a call for `.` (repeat#Record), with 'count'.
" Returns the written block, {} when nothing was done (off a tab line, a
" refusal, nothing to do).
function! songwriter#tab#edit#Do(Fn, ...) abort
  let l:opts = a:0 ? a:1 : {}
  let l:insert = songwriter#tab#insert#Active()
  let l:slot = get(l:opts, 'slot', '')
  let l:join = get(l:opts, 'join', 0)
  if l:slot ==# 'close'
    call songwriter#tab#slots#Abandon()
  elseif l:slot ==# 'motion'
    call songwriter#tab#slots#Abandon(1)
  elseif l:slot ==# 'fill'
    let l:join = l:join || !empty(songwriter#tab#state#Get('slot'))
  endif
  let l:block = songwriter#tab#model#Read()
  if empty(l:block)
    return {}
  endif
  if has_key(l:opts, 'open')
    let l:mark = songwriter#tab#slots#Mark(l:opts.open)
  endif
  if l:join
    silent! undojoin
  endif
  if get(l:opts, 'prelint', 1)
    let l:block = songwriter#tab#edit#LintAndFollow(l:block)
  endif
  if has_key(l:opts, 'open')
    call songwriter#tab#slots#Linted(l:mark, l:block)
  endif
  let l:ctx = extend(songwriter#tab#model#Cursor(l:block), {'insert': l:insert})
  let l:result = a:Fn(l:ctx)
  if get(l:opts, 'lint', 1)
    let l:written = songwriter#tab#edit#Commit(l:block, l:result)
  elseif has_key(l:result, 'error')
    call songwriter#tab#edit#Error(l:result.error)
    let l:written = {}
  elseif !empty(l:result)
    call songwriter#tab#edit#Apply(l:block, l:result)
    let l:written = songwriter#tab#model#Read(l:block.start)
  else
    let l:written = {}
  endif
  if !empty(l:written)
    if l:slot ==# 'fill'
      call songwriter#tab#slots#Forget()
    endif
    for [l:name, l:value] in items(get(l:result, 'state', {}))
      call songwriter#tab#state#Set(l:name, extend(copy(l:value),
            \ {'line': line('.'), 'col': col('.')}, 'keep'))
    endfor
    if has_key(l:opts, 'open')
      call songwriter#tab#slots#Open(l:mark)
    endif
    if has_key(l:opts, 'repeat')
      call songwriter#tab#repeat#Record(l:opts.repeat, get(l:opts, 'count', 1))
    endif
  endif
  if l:insert && get(l:opts, 'insert', 0) && !has_key(l:opts, 'open')
    call songwriter#tab#insert#Keep()
  endif
  return l:written
endfunction
