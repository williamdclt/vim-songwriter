" autoload/songwriter/tab/play.vim - playing the notes of a tab (spec
" [Tablature][[Editing]] 12): which notes a target reaches, as steps of
" pitches (pure), handed to songwriter#sound#Play. The operator side (targets,
" `<leader>p`) is tab/operator.vim, the sound sound.vim.

" Spec 12.2: the fretted notes of `lines` starting in columns [s, e] on the
" strings `lins` (0-indexed), as steps, one per time column left to right:
" each a list of {'lin', 'midi'} from the lowest string up, `open` being the
" open strings' pitches (songwriter#tuning#Of). Muted notes are left out, and a column with nothing
" else gives no step.
function! songwriter#tab#play#Steps(lines, open, lins, s, e) abort
  let l:by_col = {}
  for l:lin in a:lins
    for l:n in songwriter#tab#model#Notes(a:lines[l:lin])
      if l:n.col >= a:s && l:n.col <= a:e && songwriter#grammar#IsFretChar(l:n.text[0])
        let l:by_col[l:n.col] = add(get(l:by_col, l:n.col, []),
              \ {'lin': l:lin, 'midi': a:open[l:lin] + str2nr(l:n.text)})
      endif
    endfor
  endfor
  return map(sort(map(keys(l:by_col), 'str2nr(v:val)'), 'n'),
        \ {_, c -> sort(l:by_col[c], {a, b -> b.lin - a.lin})})
endfunction

" Spec 12: play `parts`, one after the other: each [lines, lins, s, e], the
" notes of a tab's `lines` starting in columns [s, e] on the strings `lins`.
" A string name that is not a note refuses it all, with a message.
function! songwriter#tab#play#Play(parts) abort
  let l:steps = []
  for [l:lines, l:lins, l:s, l:e] in a:parts
    let l:tuning = songwriter#tuning#Of(songwriter#tab#model#Names(l:lines))
    if has_key(l:tuning, 'error')
      return songwriter#tab#edit#Error(l:tuning.error)
    endif
    call extend(l:steps, songwriter#tab#play#Steps(l:lines, l:tuning.pitches, l:lins, l:s, l:e))
  endfor
  call songwriter#sound#Play(l:steps)
endfunction
