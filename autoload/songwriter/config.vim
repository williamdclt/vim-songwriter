" autoload/songwriter/config.vim - the plugin's options (README "Customization"):
" each g:songwriter_<name>, with its default. A default of v:null is computed
" where the option is used (the player found, the cache directory).

let s:defaults = {
      \ 'max_fret': 24,
      \ 'play_bpm': 100,
      \ 'strum_ms': 80,
      \ 'player': v:null,
      \ 'sound_cache': v:null,
      \ }

" The value of option `name`: g:songwriter_{name}, else its default. Throws
" for a name that is not an option.
function! songwriter#config#Get(name) abort
  if !has_key(s:defaults, a:name)
    throw 'songwriter: no option ' . a:name
  endif
  return get(g:, 'songwriter_' . a:name, s:defaults[a:name])
endfunction
