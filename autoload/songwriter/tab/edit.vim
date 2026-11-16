" autoload/songwriter/tab/edit.vim - the buffer side of a tablature edit.
"
" A tablature-mode edit is a pure function (tab/columns.vim, tab/carry.vim,
" tab/slots.vim...) returning a result; this module does the rest. A result is
" a dict with any of
"   'lines': the block's new lines,
"   'map':   where each column of the lines the edit was given went
"            (tab/colmap.vim), required with 'lines',
"   'base':  with 'lines' and 'map', a snapshot (model#Snapshot) the edit
"            started from instead of the block it was given (a carry renders
"            from the tab it saved),
"   'put':   with 'lines', annotation words the edit brings along, at columns
"            of its lines (annotations#Follow),
"   'label': with 'lines', {'col' (of its lines), 'text', 'add'}: the chord
"            label of that column to write (annotations#Label),
"   'above': with 'lines', the annotation lines, in place of those that
"            would follow the edit (`cap` clears them, 6.3.1),
"   'col':   the cursor column,
"   'lin':   the cursor's 0-indexed line in the block (with 'col'; default:
"            stays),
"   'sel':   with 'lines', the selection to make again once written (Do's
"            'selection' given), as selection#Get gives it but its 'anchor'
"            and 'cursor' being [lin, col] of the lines the edit was given (or
"            of its 'base'); its columns follow the edit and the lint,
"   'slot':  1 when the cursor is left on a slot the edit opened as part of
"            a bigger edit (`c`, 6.6), which closing lints (slots#Open),
"   'msg':   a message to echo,
"   'error': a refusal to show; nothing else is applied,
"   'state': {name: value} to record in tab/state.vim once written, each value
"            completed with the cursor's 'line' and 'col' (Do only),
"   'register': {'name', 'rows', 'type', 'names', 'above' (optional)} to set
"            once written (register#Set; Do only),
"   'side':  0 for an edit that opens a slot in an empty bar whatever
"            opts.open says (slots#InBar; Do only).
" {} means nothing to do.
"
" Do() is the one way an edit reaches the buffer, in stages: prepare (the
" open slot, the first lint), the pure edit, write (the lint, the column map,
" the undo step), then the follow-ups (the selection, the state for the next
" key, the register, a slot opened, `.`, the insert state), each a small
" function. Its target is the cursor, or a visual selection it selects again.
" `undojoin` is only here (s:write, JoinUndo).
"
" What an edit writes is a draft: {'lines', 'map', 'base' (optional), 'put'
" (optional), 'label' (optional), 'above' (optional)}, the block's new lines
" and where each column of `base` went in them; `base` is the snapshot the
" edit started from, by default the block being written; `put` are annotation
" words the edit brings along (annotations#Follow); `label` a chord label it
" writes (annotations#Label); `above` annotation lines replacing them all.
" s:write is the one way a draft reaches the buffer.

" Pure. The snapshot of `lines`, made from the snapshot `base` by an edit
" whose column map is `map`: the annotations follow the music
" (annotations#Follow), with the words `put` (optional, [] for none) added,
" then the chord label `label` (optional) written.
function! songwriter#tab#edit#Derive(base, lines, map, ...) abort
  let l:above = songwriter#tab#annotations#Follow(a:base.above, a:map, a:0 ? a:1 : [])
  if a:0 > 1 && !empty(a:2)
    let l:above = songwriter#tab#annotations#Label(l:above, a:2.col, a:2.text, a:2.add)
  endif
  return {'top': a:base.top, 'lines': copy(a:lines), 'above': l:above}
endfunction

" Pure. The snapshot `draft` makes of `block`.
function! s:snapshot(block, draft) abort
  if !has_key(a:draft, 'map')
    throw 'songwriter: a draft needs a map (tab/colmap.vim)'
  endif
  let l:snapshot = songwriter#tab#edit#Derive(get(a:draft, 'base', songwriter#tab#model#Snapshot(a:block)),
        \ a:draft.lines, a:draft.map, get(a:draft, 'put', []), get(a:draft, 'label', {}))
  if has_key(a:draft, 'above')
    let l:snapshot.above = copy(a:draft.above)
  endif
  return l:snapshot
endfunction

" Show a refusal, `msg` as a pure function gives it ({'error'}), prefixed
" with the plugin's name.
function! songwriter#tab#edit#Error(msg) abort
  echohl ErrorMsg
  echo 'songwriter: ' . a:msg
  echohl None
endfunction

" Pure. `lines` linted, with column `col` of line `lin` (0-indexed) followed
" through the lint so that it stays on the same note, or in the same gap
" between notes (lint#FollowColumn): {'lines', 'col', 'map'}. A `lin` outside
" the block keeps its column.
function! songwriter#tab#edit#Linted(lines, lin, col) abort
  let l:result = songwriter#tab#lint#Lint(a:lines)
  let l:col = a:lin >= 0 && a:lin < len(a:lines)
        \ ? songwriter#tab#lint#FollowColumn(a:lines, l:result, a:lin, a:col) : a:col
  return {'lines': l:result.lines, 'col': l:col, 'map': l:result.map}
endfunction

" Write `draft` over `block` and put the cursor on line `lin` of the block
" at column `col`; a cursor off the block's strings stays on its line. `join`:
" the write, if anything changes, is joined to the previous undo step.
function! s:write(block, draft, lin, col, join) abort
  let l:snapshot = s:snapshot(a:block, a:draft)
  let l:block = a:block
  if l:snapshot !=# songwriter#tab#model#Snapshot(a:block)
    if a:join
      silent! undojoin
    endif
    let l:block = songwriter#tab#model#Write(a:block, l:snapshot)
  endif
  call cursor(a:lin >= 0 && a:lin < len(a:draft.lines) ? l:block.start + a:lin : line('.'), a:col)
  return l:block
endfunction

" Join the next change to the previous undo step, for a change that is not an
" edit of a tab's strings (whole tabs deleted by a line-wise operator, an
" annotation line retyped once Vim's insert mode is left) made in a later
" command than the change it belongs with.
function! songwriter#tab#edit#JoinUndo() abort
  silent! undojoin
endfunction

" Pure. Where `result` takes `lines`, the cursor being on line `lin` (0-indexed)
" at column `col`: {'lines', 'lin', 'col', 'map'}, linted with the cursor
" following the music when `lint` is set. The map is from `lines`, or from the
" result's base, also given ('base'), when it has one.
function! s:resolve(lines, lin, col, result, lint) abort
  let l:lin = a:lin
  let l:col = a:col
  if has_key(a:result, 'col')
    let l:lin = get(a:result, 'lin', l:lin)
    let l:col = a:result.col
  endif
  let l:lines = get(a:result, 'lines', a:lines)
  if has_key(a:result, 'lines') && !has_key(a:result, 'map')
    throw 'songwriter: an edit result with lines needs a map (tab/colmap.vim)'
  endif
  let l:map = get(a:result, 'map', [])
  if l:lin >= 0 && l:lin < len(l:lines)
    " As the cursor would be once there: on the line, at most on its end.
    let l:col = max([1, min([l:col, len(l:lines[l:lin])])])
  endif
  if a:lint
    let l:linted = songwriter#tab#edit#Linted(l:lines, l:lin, l:col)
    let [l:lines, l:col] = [l:linted.lines, l:linted.col]
    let l:map = songwriter#tab#colmap#Then(l:map, l:linted.map)
  endif
  let l:r = {'lines': l:lines, 'lin': l:lin, 'col': l:col, 'map': l:map}
  for l:key in ['base', 'above']
    if has_key(a:result, l:key)
      let l:r[l:key] = a:result[l:key]
    endif
  endfor
  " The words' columns follow the lint, as the rest of the tab.
  let l:lint = a:lint ? l:linted.map : []
  if has_key(a:result, 'put')
    let l:r.put = map(copy(a:result.put), {_, p -> extend(copy(p),
          \ {'col': songwriter#tab#colmap#At(l:lint, p.col)})})
  endif
  if has_key(a:result, 'label')
    let l:r.label = extend(copy(a:result.label),
          \ {'col': songwriter#tab#colmap#At(l:lint, a:result.label.col)})
  endif
  return l:r
endfunction

" A whole edit, written once: the block is linted (in memory), Fn(ctx) gives a
" result for it (see the top), and the result is linted again and written.
" ctx is {'block' (the linted block, as Read gives it), 'lin', 'col', 'line'
" (as model#Cursor; 'line' is '' when the cursor is off the block's strings),
" 'insert' (whether the insert state is on), 'sel' (the selection, when one
" is given)}. A refusal or an empty result still writes the first lint,
" except for an edit that opens a slot: the lint is part of opening it (spec
" 4.2), so with no slot nothing changes.
" `opts` (all optional):
"   'lnum':    a line of the block to edit (default: the cursor's), when the
"              cursor may be elsewhere.
"   'selection': the target is this visual selection (selection#Get, read
"              before leaving visual mode), selected again once written (the
"              result's 'sel', else as it was).
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
  let l:edit = s:prepare(a:0 ? a:1 : {})
  if empty(l:edit)
    return {}
  endif
  let l:result = a:Fn(l:edit.ctx)
  let l:edit.done = !empty(l:result) && !has_key(l:result, 'error')
  call s:write_result(l:edit, l:result)
  call s:select(l:edit, l:result)
  call s:report(l:edit, l:result)
  if l:edit.done
    call s:fill_slot(l:edit, l:result)
    call s:record_state(l:edit, l:result)
    call s:set_register(l:edit, l:result)
    call s:open_slot(l:edit, l:result)
    call s:record_repeat(l:edit, l:result)
  endif
  call s:keep_insert(l:edit)
  return l:edit.done ? songwriter#tab#model#ReadTop(l:edit.block.top) : {}
endfunction

" Stage 1: what Do works on, {'opts', 'block' (as read), 'pre' (the first
" lint, resolved), 'ctx' (for Fn), 'join', 'insert', 'mark' (with 'open')},
" once the open slot is dealt with; {} off a tab.
function! s:prepare(opts) abort
  let l:edit = {'opts': a:opts, 'insert': songwriter#tab#mode#Current() ==# 'insert',
        \ 'join': get(a:opts, 'join', 0)}
  let l:slot = get(a:opts, 'slot', '')
  if l:slot ==# 'close'
    call songwriter#tab#slots#Abandon()
  elseif l:slot ==# 'motion'
    call songwriter#tab#slots#Abandon(1)
  elseif l:slot ==# 'fill'
    let l:edit.join = l:edit.join || !empty(songwriter#tab#state#Get('slot'))
  endif
  let l:block = has_key(a:opts, 'lnum') ? songwriter#tab#model#Around(a:opts.lnum)
        \ : songwriter#tab#model#Read()
  if empty(l:block)
    return {}
  endif
  let l:edit.block = l:block
  if has_key(a:opts, 'open')
    let l:edit.mark = songwriter#tab#slots#Mark(a:opts.open)
  endif
  let l:pre = s:resolve(l:block.lines, songwriter#tab#model#CursorLin(l:block), col('.'), {},
        \ get(a:opts, 'prelint', 1))
  if has_key(a:opts, 'open')
    call songwriter#tab#slots#Linted(l:edit.mark, l:pre)
  endif
  let l:edit.pre = l:pre
  let l:edit.ctx = {'block': songwriter#tab#model#FromSnapshot(s:snapshot(l:block, l:pre)),
        \ 'lin': l:pre.lin, 'col': l:pre.col, 'insert': l:edit.insert,
        \ 'line': l:pre.lin >= 0 && l:pre.lin < len(l:pre.lines) ? l:pre.lines[l:pre.lin] : ''}
  if has_key(a:opts, 'selection')
    let l:edit.ctx.sel = a:opts.selection
  endif
  return l:edit
endfunction

" Stage 3: write the result, linted, or only the first lint when it is a
" refusal or nothing (none of it for an edit that opens a slot). Records what
" was written in `edit` ('post', the draft; 'written', the block).
function! s:write_result(edit, result) abort
  let l:post = a:edit.pre
  if a:edit.done
    let l:post = s:resolve(l:post.lines, l:post.lin, l:post.col, a:result, get(a:edit.opts, 'lint', 1))
    if !has_key(l:post, 'base')
      let l:post.map = songwriter#tab#colmap#Then(a:edit.pre.map, l:post.map)
    endif
  endif
  let a:edit.post = l:post
  let a:edit.written = a:edit.block
  if a:edit.done || !has_key(a:edit.opts, 'open')
    let a:edit.written = s:write(a:edit.block, l:post, l:post.lin, l:post.col, a:edit.join)
  endif
endfunction

" Follow-up: select the selection target again, its columns following the
" edit when the result says where it went ('sel').
function! s:select(edit, result) abort
  if !has_key(a:edit.opts, 'selection')
    return
  endif
  if !a:edit.done || !has_key(a:result, 'sel')
    return songwriter#selection#Select(a:edit.opts.selection)
  endif
  let l:sel = copy(a:result.sel)
  for l:end in ['anchor', 'cursor']
    let [l:lin, l:col] = a:result.sel[l:end]
    let l:sel[l:end] = [0, a:edit.written.start + l:lin,
          \ max([1, songwriter#tab#colmap#At(a:edit.post.map, l:col)]), 0]
  endfor
  let l:sel.cursor += [l:sel.cursor[2]]
  call songwriter#selection#Select(l:sel)
endfunction

" Follow-up: echo the refusal, or the message.
function! s:report(edit, result) abort
  if has_key(a:result, 'error')
    call songwriter#tab#edit#Error(a:result.error)
  elseif a:edit.done && !empty(get(a:result, 'msg', ''))
    echo a:result.msg
  endif
endfunction

" Follow-up: a slot the edit filled is forgotten.
function! s:fill_slot(edit, result) abort
  if get(a:edit.opts, 'slot', '') ==# 'fill'
    call songwriter#tab#slots#Forget()
  endif
endfunction

" Follow-up: record the result's state for the next key, with the cursor
" where the edit left it (state#Continuing).
function! s:record_state(edit, result) abort
  for [l:name, l:value] in items(get(a:result, 'state', {}))
    call songwriter#tab#state#Set(l:name, extend(copy(l:value), {'line': line('.'), 'col': col('.')}))
  endfor
endfunction

" Follow-up: set the result's register.
function! s:set_register(edit, result) abort
  if has_key(a:result, 'register')
    let l:r = a:result.register
    call songwriter#tab#register#Set(l:r.name, l:r.rows, l:r.type, l:r.names, get(l:r, 'above', 0))
  endif
endfunction

" Follow-up: remember the slot the edit opened: with a mark (opts.open), in
" the empty bar it landed in when that is not the side it was opened on
" (slots#InBar); without one, a slot of a bigger edit (the result's 'slot').
function! s:open_slot(edit, result) abort
  if has_key(a:edit.opts, 'open')
    if has_key(a:result, 'side') && a:result.side != a:edit.mark.side
      call songwriter#tab#slots#InBar(a:edit.mark, col('.'))
    endif
    call songwriter#tab#slots#Open(a:edit.mark)
  elseif get(a:result, 'slot', 0)
    call songwriter#tab#slots#Open()
  endif
endfunction

" Follow-up: record the edit for `.`.
function! s:record_repeat(edit, result) abort
  if has_key(a:edit.opts, 'repeat')
    call songwriter#tab#repeat#Record(a:edit.opts.repeat, get(a:edit.opts, 'count', 1))
  endif
endfunction

" Follow-up: keep the insert state the edit was made in, when asked.
function! s:keep_insert(edit) abort
  if a:edit.insert && get(a:edit.opts, 'insert', 0) && !has_key(a:edit.opts, 'open')
    call songwriter#tab#mode#Keep()
  endif
endfunction
