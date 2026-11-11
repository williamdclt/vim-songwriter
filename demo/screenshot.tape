# Regenerate with: vhs demo/screenshot.tape (from the repository root)
# VHS always records a GIF; only the PNG is kept (the GIF is gitignored).
Output demo/screenshot.gif
Set Shell bash
Set FontSize 16
Set Width 900
Set Height 720
Set Padding 20
Set Theme "Catppuccin Mocha"

Hide
Type "vim -u demo/vimrc demo/example.song.txt" Enter
Sleep 1s
Type ":3 | echo" Enter
Sleep 300ms
Show
Sleep 500ms
Screenshot demo/screenshot.png
Sleep 200ms
Hide
Type ":qa!" Enter
