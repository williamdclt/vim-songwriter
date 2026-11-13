" autoload/songwriter/tab/play.vim - playing the notes of a tab (spec
" [Tablature][[Editing]] 12): which notes a target reaches, as steps of
" pitches (pure), handed to songwriter#sound#Play. The operator side (targets,
" `<leader>p`) is tab/operator.vim, the sound sound.vim.

" The lowest string's pitch is taken in [B1, A#2] (MIDI 35-46), 12.3.
let s:lowest = 35

" Spec 12.3: the MIDI pitches of open strings named `names` (highest first),
" each the nearest pitch above the string below it (less than an octave, as
" 7.3; the same name is an octave up), the lowest in [B1, A#2]:
" {'midi': [...]}, or {'error': message} for a name that is not a note.
function! songwriter#tab#play#OpenPitches(names) abort
  let l:midi = []
  for l:name in reverse(copy(a:names))
    let l:pc = songwriter#pitch#Class(l:name)
    if l:pc < 0
      return {'error': printf('songwriter: string name %s is not a note', l:name)}
    endif
    if empty(l:midi)
      call add(l:midi, s:lowest + (l:pc - s:lowest % 12 + 12) % 12)
    else
      let l:up = (l:pc - l:midi[-1] % 12 + 12) % 12
      call add(l:midi, l:midi[-1] + (l:up == 0 ? 12 : l:up))
    endif
  endfor
  return {'midi': reverse(l:midi)}
endfunction

" Spec 12.2: the fretted notes of `lines` starting in columns [s, e] on the
" strings `lins` (0-indexed), as steps, one per time column left to right:
" each a list of {'lin', 'midi'} from the lowest string up, `open` being the
" open strings' pitches. Muted notes are left out, and a column with nothing
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
    let l:open = songwriter#tab#play#OpenPitches(songwriter#tab#model#Names(l:lines))
    if has_key(l:open, 'error')
      return songwriter#tab#edit#Error(l:open.error)
    endif
    call extend(l:steps, songwriter#tab#play#Steps(l:lines, l:open.midi, l:lins, l:s, l:e))
  endfor
  call songwriter#sound#Play(l:steps)
endfunction
