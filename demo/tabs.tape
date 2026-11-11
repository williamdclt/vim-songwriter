# Demo of tab editing for the README.
# Regenerate with: vhs demo/tabs.tape (from the repository root)
Output demo/tabs.gif
Set Shell bash
Set FontSize 20
Set Width 1000
Set Height 330
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 150ms

Hide
Type `R=$PWD; cd "$(mktemp -d)"; vim -u "$R/demo/vimrc" riff.song.txt` Enter
Sleep 1s

Hide
Type ":Cap New empty tab:  :SongwriterNewTab" Enter
Sleep 100ms
Show
Sleep 1200ms
Type ":SongwriterNewTab"
Sleep 400ms
Enter
Sleep 1500ms

Hide
Type ":Cap Type notes, one after another:  3 5 7" Enter
Sleep 100ms
Show
Sleep 1200ms
Type "jjjj"
Sleep 500ms
Type "357"
Sleep 1500ms

Hide
Type ":Cap A whole chord, rooted on this string:  =C <Enter>" Enter
Sleep 100ms
Show
Sleep 1200ms
Type " "
Sleep 400ms
Type "=C"
Sleep 400ms
Enter
Sleep 600ms
Escape
Sleep 1500ms

Hide
Type ":Cap Change its quality:  =7 <Enter>" Enter
Sleep 100ms
Show
Sleep 1200ms
Type "=7"
Sleep 400ms
Enter
Sleep 1500ms

Hide
Type ":Cap Copy the time column, paste it:  yy p" Enter
Sleep 100ms
Show
Sleep 1200ms
Type "yy"
Sleep 400ms
Type "p"
Sleep 1500ms

Hide
Type ":Cap Move a note one string up:  sk" Enter
Sleep 100ms
Show
Sleep 1200ms
Type "HHH"
Sleep 600ms
Type "sk"
Sleep 1500ms

Hide
Type ":Cap Raise it a fret:  Ctrl-A" Enter
Sleep 100ms
Show
Sleep 1200ms
Ctrl+A
Sleep 500ms
Ctrl+A
Sleep 1500ms

Hide
Type ":Cap Push the time column one dash later:  >>" Enter
Sleep 100ms
Show
Sleep 1200ms
Type ">>"
Sleep 500ms
Type ">>"
Sleep 1500ms
Sleep 1s
Hide
Type ":qa!" Enter
