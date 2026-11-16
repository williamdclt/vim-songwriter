" autoload/songwriter/tuning.vim - what a tab's string names mean (pure):
" the open strings' pitches (spec [Tablature][[Editing]] 12.3), whether they
" are standard tuning (10.2), and the interval between two strings (7.3).

" The lowest string's pitch is taken in [B1, A#2] (MIDI 35-46), 12.3.
let s:lowest = 35

let s:standard = ['e', 'b', 'g', 'd', 'a', 'e']

" Spec 12.3, 10.2: the tuning of strings named `names` (highest first):
" {'pitches': the MIDI pitches of the open strings, each the nearest pitch
" above the string below it (less than an octave, as 7.3; the same name is an
" octave up), the lowest in [B1, A#2]; 'standard': 1 when the names are
" eBGDAE, in either case}, or {'error'} for a name that is not a note.
function! songwriter#tuning#Of(names) abort
  let l:pitches = []
  for l:name in reverse(copy(a:names))
    let l:pc = songwriter#pitch#Class(l:name)
    if l:pc < 0
      return {'error': printf('string name %s is not a note', l:name)}
    endif
    if empty(l:pitches)
      call add(l:pitches, s:lowest + (l:pc - s:lowest % 12 + 12) % 12)
    else
      let l:up = (l:pc - l:pitches[-1] % 12 + 12) % 12
      call add(l:pitches, l:pitches[-1] + (l:up == 0 ? 12 : l:up))
    endif
  endfor
  return {'pitches': reverse(l:pitches),
        \ 'standard': map(copy(a:names), 'tolower(v:val)') ==# s:standard}
endfunction

" Spec 7.3: {'frets': the number of frets a note moving from string `from` to
" string `to` of strings named `names` (highest first) changes by to keep its
" pitch}, or {'error'} when a name is not a note or both have the same pitch
" class. Neighbouring strings are taken to be less than an octave apart: the
" interval is read from the two pitch classes.
function! songwriter#tuning#Interval(names, from, to) abort
  for l:lin in [a:from, a:to]
    if songwriter#pitch#Class(a:names[l:lin]) < 0
      return {'error': printf('string name %s is not a note', a:names[l:lin])}
    endif
  endfor
  let [l:hi, l:lo] = a:to < a:from ? [a:to, a:from] : [a:from, a:to]
  let l:interval = (songwriter#pitch#Class(a:names[l:hi])
        \ - songwriter#pitch#Class(a:names[l:lo]) + 12) % 12
  if l:interval == 0
    return {'error': printf('cannot tell the interval between strings %s and %s',
          \ a:names[l:hi], a:names[l:lo])}
  endif
  return {'frets': a:to < a:from ? -l:interval : l:interval}
endfunction
