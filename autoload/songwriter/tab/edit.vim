" autoload/songwriter/tab/edit.vim - the buffer side of a tablature edit.
"
" A tablature-mode edit is a pure function (tab/columns.vim, tab/strings.vim,
" tab/slots.vim) returning a result; this module does the rest: lint, write,
" move the cursor, report. A result is a dict with any of
"   'lines': the block's new lines,
"   'col':   the cursor column,
"   'lin':   the cursor's 0-indexed line in the block (default: stays),
"   'msg':   a message to echo,
"   'error': a refusal to show; nothing else is applied.
" {} means nothing to do.

" Show a refusal.
function! songwriter#tab#edit#Error(msg) abort
  echohl ErrorMsg
  echo a:msg
  echohl None
endfunction

" Lint `block`, write it back and keep the cursor on the same note (or in the
" same gap between notes) when it is inside the block. Returns the re-read
" block, or {} when `block` is empty.
function! songwriter#tab#edit#LintAndFollow(block) abort
  if empty(a:block)
    return {}
  endif
  let l:result = songwriter#tab#lint#Lint(a:block.lines)
  call songwriter#tab#model#Write(a:block, l:result.lines)
  let l:lin = line('.') - a:block.start
  if l:lin >= 0 && l:lin < len(a:block.lines)
    call cursor(line('.'),
          \ songwriter#tab#lint#FollowColumn(a:block.lines, l:result, l:lin, col('.')))
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

" Apply a result to `block`, lint keeping the cursor on the music, and echo its
" message. Returns the linted block, or {} when the result was a refusal or
" nothing to do.
function! songwriter#tab#edit#Commit(block, result) abort
  if has_key(a:result, 'error')
    call songwriter#tab#edit#Error(a:result.error)
    return {}
  endif
  if empty(a:result)
    return {}
  endif
  call songwriter#tab#edit#Apply(a:block, a:result)
  let l:linted = songwriter#tab#edit#LintAndFollow(songwriter#tab#model#Read(a:block.start))
  if !empty(get(a:result, 'msg', ''))
    echo a:result.msg
  endif
  return l:linted
endfunction

" A whole edit at the cursor: lint the block, call Fn({'block', 'lin', 'col'})
" for a result, and commit it. Returns the linted block, {} when nothing was
" done (off a tab line, refusal, nothing to do).
function! songwriter#tab#edit#Run(Fn) abort
  let l:block = songwriter#tab#edit#LintAndFollow(songwriter#tab#model#Read())
  if empty(l:block)
    return {}
  endif
  return songwriter#tab#edit#Commit(l:block,
        \ a:Fn({'block': l:block, 'lin': line('.') - l:block.start, 'col': col('.')}))
endfunction
