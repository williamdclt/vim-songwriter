" ftdetect/songwriter.vim - Detect songwriter files
" Use BufReadPost + force set to override Vim's built-in *.txt -> text detection
autocmd BufReadPost,BufNewFile *.song.txt set filetype=songwriter
autocmd BufReadPost,BufNewFile *.tab.txt set filetype=songwriter
