" autoload/songwriter/sound.vim - plucked-string sounds and playing them
" (spec [Tablature][[Editing]] 12.2, 12.4, 12.5). Each pitch is synthesised
" once (Karplus-Strong) into a WAV file in the cache, and played by an
" external player command, one job per note, started by timers. See design.md
" "Playing notes".

let s:rate = 22050
let s:seconds = 1.2
" Part of the file names, so that changing the synthesis makes new files.
let s:synth = 'pluck1'
" Peak level, out of 32767: notes played together must not clip.
let s:level = 9000.0
let s:pi = 3.14159265358979
" Vim 9 synthesises with compiled Vim9 script (sound9.vim), some 25 times
" faster; Vim 8.2 and Neovim with the same loop in legacy script.
let s:vim9 = v:version >= 900 && !has('nvim')

let s:timers = []
" The job sounding on each string (lin -> job): a note stops its string's
" previous one.
let s:jobs = {}
let s:last = []

" The frequency in Hz of MIDI pitch `midi` (A4 = 69 = 440 Hz).
function! songwriter#sound#Frequency(midi) abort
  return 440.0 * pow(2.0, (a:midi - 69) / 12.0)
endfunction

" A plucked string at pitch `midi`, as the bytes of a 16-bit mono WAV file.
" Karplus-Strong: a delay line of one period filled with noise (seeded by the
" pitch, so a pitch always sounds the same) that goes round through a
" two-tap lowpass (the string's damping) and a first-order allpass (the
" fraction of a sample left of the period, so that high notes stay in tune).
" The damping is set so that the note dies away in s:t60(), high notes
" sooner, as on a guitar.
function! songwriter#sound#Wav(midi) abort
  let l:f = songwriter#sound#Frequency(a:midi)
  let l:w = 2 * s:pi * l:f / s:rate
  let l:period = s:rate / l:f
  let [l:tap, l:loss] = s:damping(l:w, pow(0.001, 1.0 / (s:t60(l:f) * l:f)))
  " The lowpass reads one sample ahead, which shortens the loop.
  let l:advance = atan2(l:tap * sin(l:w), 1 - l:tap + l:tap * cos(l:w)) / l:w
  let l:p = float2nr(floor(l:period + l:advance - 0.5))
  let l:c = s:allpass(l:period + l:advance - l:p, l:w)
  let [l:a, l:b] = [l:loss * (1 - l:tap), l:loss * l:tap]
  let l:seed = srand(a:midi)
  let l:buf = map(range(l:p), {-> (rand(l:seed) % 2001) / 1000.0 - 1.0})
  " No DC: the damping would keep it forever.
  let l:mean = eval(join(l:buf, '+')) / l:p
  call map(l:buf, {_, v -> v - l:mean})
  let l:ks = {'buf': l:buf, 'a': l:a, 'b': l:b, 'c': l:c,
        \ 'n': float2nr(s:rate * s:seconds), 'fade': s:rate / 20, 'level': s:level}
  let l:data = s:vim9 ? songwriter#sound9#Pluck(l:ks) : songwriter#sound#Pluck(l:ks)
  return s:header(len(l:data)) + l:data
endfunction

" The samples of a plucked string, as 16-bit little-endian bytes: `ks.n`
" turns of the delay line `ks.buf` (changed in place) through the lowpass
" (`ks.a`, `ks.b`) and the allpass (`ks.c`), at `ks.level`, faded out over
" the last `ks.fade` samples. songwriter#sound9#Pluck is the same, compiled.
function! songwriter#sound#Pluck(ks) abort
  let [l:buf, l:a, l:b, l:c, l:n, l:fade, l:level] =
        \ [a:ks.buf, a:ks.a, a:ks.b, a:ks.c, a:ks.n, a:ks.fade, a:ks.level]
  let l:p = len(l:buf)
  let l:data = []
  let [l:i, l:j, l:x1, l:y1] = [0, 0, 0.0, 0.0]
  while l:i < l:n
    let l:s = l:buf[l:j]
    let l:next = l:j + 1 < l:p ? l:j + 1 : 0
    let l:x = l:a * l:s + l:b * l:buf[l:next]
    let l:y = l:c * l:x + l:x1 - l:c * l:y1
    let [l:x1, l:y1] = [l:x, l:y]
    let l:buf[l:j] = l:y
    let l:j = l:next
    let l:gain = l:i < l:n - l:fade ? l:level : l:level * (l:n - l:i) / l:fade
    let l:v = float2nr(l:s * l:gain)
    let l:v = l:v < 0 ? l:v + 65536 : l:v
    call extend(l:data, [and(l:v, 255), l:v / 256])
    let l:i += 1
  endwhile
  return list2blob(l:data)
endfunction

" How long a note at `f` Hz takes to die away (-60 dB), in seconds.
function! s:t60(f) abort
  return 2.5 * pow(82.4 / a:f, 0.35)
endfunction

" The damping that loses `g` of the amplitude per period at angular frequency
" `w`: [tap, loss], the lowpass (1 - tap) x[n] + tap x[n+1], times `loss`.
" An even lowpass (tap 0.5) where it loses less than that, with the rest lost
" by `loss`; else a lighter one (a smaller tap), found by bisection.
function! s:damping(w, g) abort
  let l:even = cos(a:w / 2)
  if l:even >= a:g
    return [0.5, a:g / l:even]
  endif
  let [l:lo, l:hi] = [0.0, 0.5]
  for l:i in range(40)
    let l:tap = (l:lo + l:hi) / 2
    if sqrt(1 - 2 * l:tap * (1 - l:tap) * (1 - cos(a:w))) > a:g
      let l:lo = l:tap
    else
      let l:hi = l:tap
    endif
  endfor
  return [(l:lo + l:hi) / 2, 1.0]
endfunction

" The coefficient of the first-order allpass (c + z^-1) / (1 + c z^-1) whose
" phase delay at angular frequency `w` (radians per sample) is `d` samples
" (0.5 <= d < 1.5), by bisection: the delay falls as c grows.
function! s:allpass(d, w) abort
  let [l:lo, l:hi] = [-0.99, 0.99]
  for l:i in range(40)
    let l:c = (l:lo + l:hi) / 2
    let l:phase = atan2(-sin(a:w), l:c + cos(a:w)) - atan2(-l:c * sin(a:w), 1 + l:c * cos(a:w))
    if -l:phase / a:w > a:d
      let l:lo = l:c
    else
      let l:hi = l:c
    endif
  endfor
  return (l:lo + l:hi) / 2
endfunction

" The 44-byte header of a 16-bit mono PCM WAV file of `size` data bytes.
function! s:header(size) abort
  return 0z52494646 + s:le(36 + a:size, 4) + 0z57415645
        \ + 0z666D7420 + s:le(16, 4) + s:le(1, 2) + s:le(1, 2)
        \ + s:le(s:rate, 4) + s:le(s:rate * 2, 4) + s:le(2, 2) + s:le(16, 2)
        \ + 0z64617461 + s:le(a:size, 4)
endfunction

" `n` as `bytes` little-endian bytes.
function! s:le(n, bytes) abort
  let l:b = 0z
  let l:n = a:n
  for l:i in range(a:bytes)
    call add(l:b, and(l:n, 255))
    let l:n = l:n / 256
  endfor
  return l:b
endfunction

" Spec 12.5: the cache directory of the sounds.
function! s:cache() abort
  if exists('g:songwriter_sound_cache')
    return g:songwriter_sound_cache
  endif
  let l:base = empty($XDG_CACHE_HOME) ? expand('~/.cache') : $XDG_CACHE_HOME
  return l:base . '/vim-songwriter'
endfunction

" Spec 12.5: the path of the WAV file of pitch `midi`, written to the cache
" the first time.
function! songwriter#sound#File(midi) abort
  let l:path = printf('%s/%s-%d.wav', s:cache(), s:synth, a:midi)
  if !filereadable(l:path)
    call mkdir(fnamemodify(l:path, ':h'), 'p')
    call writefile(songwriter#sound#Wav(a:midi), l:path)
  endif
  return l:path
endfunction

" Spec 12.5: the player command (a list, the file is appended):
" g:songwriter_player, else the first of afplay, paplay, aplay found, else [].
function! songwriter#sound#Player() abort
  if exists('g:songwriter_player')
    return g:songwriter_player
  endif
  for l:cmd in ['afplay', 'paplay', 'aplay']
    if executable(l:cmd)
      return [l:cmd]
    endif
  endfor
  return []
endfunction

" Spec 12.2: when each note of `steps` starts, as [lin, ms, midi]: a half beat
" at g:songwriter_play_bpm per step, the notes of a step strummed in order,
" g:songwriter_strum_ms apart.
function! songwriter#sound#Schedule(steps) abort
  let l:step_ms = 30000 / get(g:, 'songwriter_play_bpm', 120)
  let l:strum_ms = get(g:, 'songwriter_strum_ms', 40)
  let l:res = []
  for l:i in range(len(a:steps))
    for l:k in range(len(a:steps[l:i]))
      let l:note = a:steps[l:i][l:k]
      call add(l:res, [l:note.lin, l:i * l:step_ms + l:k * l:strum_ms, l:note.midi])
    endfor
  endfor
  return l:res
endfunction

" Spec 12.2, 12.4, 12.5: play `steps` (see songwriter#tab#play#Steps), after
" stopping what is playing. With no player: a message, unless sound is off
" (g:songwriter_player is []).
function! songwriter#sound#Play(steps) abort
  call songwriter#sound#Stop()
  let s:last = a:steps
  let l:player = songwriter#sound#Player()
  if empty(l:player)
    if !exists('g:songwriter_player')
      echohl WarningMsg
      echo 'songwriter: no audio player found (afplay, paplay, aplay); set g:songwriter_player'
      echohl None
    endif
    return
  endif
  try
    let l:notes = map(songwriter#sound#Schedule(a:steps),
          \ {_, n -> [n[0], n[1], songwriter#sound#File(n[2])]})
  catch /^Vim\%((\a\+)\)\=:E/
    echohl ErrorMsg
    echo 'songwriter: cannot write the sounds to ' . s:cache() . ': ' . v:exception
    echohl None
    return
  endtry
  for [l:lin, l:ms, l:path] in l:notes
    call add(s:timers, timer_start(l:ms, function('s:start', [l:player, l:lin, l:path])))
  endfor
endfunction

function! s:start(player, lin, path, timer) abort
  if has_key(s:jobs, a:lin)
    call s:job_stop(s:jobs[a:lin])
  endif
  let s:jobs[a:lin] = s:job_start(a:player + [a:path])
endfunction

" Spec 12.4: stop what is playing and what is yet to start.
function! songwriter#sound#Stop() abort
  for l:timer in s:timers
    call timer_stop(l:timer)
  endfor
  for l:job in values(s:jobs)
    call s:job_stop(l:job)
  endfor
  let s:timers = []
  let s:jobs = {}
endfunction

" The steps last asked to play.
function! songwriter#sound#Last() abort
  return s:last
endfunction

function! s:job_start(cmd) abort
  if has('nvim')
    return jobstart(a:cmd)
  endif
  return job_start(a:cmd, {'in_io': 'null', 'out_io': 'null', 'err_io': 'null'})
endfunction

function! s:job_stop(job) abort
  if has('nvim')
    silent! call jobstop(a:job)
  else
    call job_stop(a:job)
  endif
endfunction
