---
name: vim-regex
description: Use when writing, reading, or debugging Vim regular expressions, :substitute, :global, search patterns, metacharacters, quantifiers, backreferences, or any Vim regex syntax. Covers s/pattern/replacement/, :g/pattern/cmd, anchors, character classes, grouping, alternation, and differences from Perl regex.
---

# Vim Regular Expressions

## Substitute command

```
:range s[ubstitute]/pattern/string/flags
```

**Flags:**

| Flag | Meaning |
|------|---------|
| `c` | Confirm each substitution |
| `g` | Replace all occurrences per line (without `g`, only first) |
| `i` | Ignore case |
| `I` | Don't ignore case |

Use any non-special character as separator to avoid backslash hell with paths:

```vim
" instead of: s/\/dir1\/dir2\/file/\/dir3\/file2/g
s:/dir1/dir2/file:/dir3/file2:g
```

## Line addressing / range

| Specifier | Meaning |
|-----------|---------|
| `number` | Absolute line number |
| `.` | Current line |
| `$` | Last line |
| `%` | Whole file (same as `1,$`) |
| `'t` | Position of mark `t` |
| `/pattern[/]` | Next line matching pattern |
| `?pattern[?]` | Previous line matching pattern |
| `\/` | Next line matching last search pattern |
| `\?` | Previous line matching last search pattern |
| `\&` | Next line matching last substitute pattern |

Each address can be followed by `+N` or `-N` to offset.

Semicolons chain addresses: `/Section 1/;/Subsection/-` finds Section 1 first, then searches forward for Subsection.

## Anchors

| Pattern | Matches |
|---------|---------|
| `^` | Start of line |
| `$` | End of line |
| `\<` | Start of word |
| `\>` | End of word |

```vim
s:\<vi\>:VIM:g        " whole word only
s:^vi\>:VIM:          " only at start of line
s:^vi$:VIM:           " only if vi is the entire line
```

## Metacharacters

| Pattern | Matches |
|---------|---------|
| `.` | Any character except newline |
| `\s` | Whitespace |
| `\S` | Non-whitespace |
| `\d` | Digit |
| `\D` | Non-digit |
| `\x` | Hex digit |
| `\X` | Non-hex digit |
| `\o` | Octal digit |
| `\O` | Non-octal digit |
| `\h` | Head-of-word character (`[a-zA-Z_]`) |
| `\H` | Non-head-of-word character |
| `\p` | Printable character |
| `\P` | Printable, excluding digits |
| `\w` | Word character |
| `\W` | Non-word character |
| `\a` | Alphabetic |
| `\A` | Non-alphabetic |
| `\l` | Lowercase letter |
| `\L` | Non-lowercase letter |
| `\u` | Uppercase letter |
| `\U` | Non-uppercase letter |

Examples:

```vim
\d\d/\d\d/\d\d\d\d    " matches a date like 09/01/2000
\u\w\w\w\w\w           " 6-letter word starting with capital
\u\w\+                 " word of any length starting with capital
```

## Quantifiers (greedy)

| Quantifier | Matches |
|------------|---------|
| `*` | 0 or more of preceding |
| `\+` | 1 or more of preceding |
| `\=` | 0 or 1 of preceding |
| `\{n,m}` | n to m of preceding |
| `\{n}` | Exactly n of preceding |
| `\{,m}` | At most m (0 to m) of preceding |
| `\{n,}` | At least n of preceding |

Greedy: matches as much as possible.

## Quantifiers (non-greedy)

| Quantifier | Matches |
|------------|---------|
| `\{-}` | 0 or more, as few as possible |
| `\{-n,m}` | Between n and m, as few as possible |
| `\{-n,}` | At least n, as few as possible |
| `\{-,m}` | At most m, as few as possible |

Non-greedy example — match the *first* quoted string only:

```vim
" greedy: matches everything between first and last "
/".*"/

" non-greedy: matches the first quoted string
/".\{-}"/
```

Note: `.\{-}` matches zero characters too, so `:s:.\{-}:_:g` inserts `_` between every character.

## Character ranges

```vim
[012345]      " any digit 0–5 (same as [0-5])
[a-z]         " any lowercase letter
[a-zA-Z]      " any letter
[0-9a-zA-Z]   " letters and digits
[^A-Z]        " anything except capital letters (^ negates when first)
[-0-9]        " digits and literal - (put - first to avoid range interpretation)
```

Inside `[...]` all metacharacters are treated as literals.

## Grouping and backreferences

Enclose with `\(` and `\)`. Reference captures as `\1` through `\9` (count opening parens left to right).

```vim
" swap first two words on the line
s:\(\w\+\)\(\s\+\)\(\w\+\):\3\2\1:
```

## Replacement special characters

| Symbol | Meaning |
|--------|---------|
| `&` | The whole matched pattern |
| `\0` | The whole matched pattern |
| `\1`–`\9` | Nth captured group |
| `~` | Previous substitute string |
| `\u` | Make next character uppercase |
| `\U` | Make following characters uppercase |
| `\l` | Make next character lowercase |
| `\L` | Make following characters lowercase |
| `\e` / `\E` | End `\U` or `\L` |
| `\r` | Split line in two at this point |

Example — capitalise first letter of each new sentence:

```vim
s:\([.!?]\)\s\+\([a-z]\):\1  \u\2:g
```

## Alternation

```vim
\(Date:\|Subject:\|From:\)\(\s.*\)
```

Vim alternation is **not greedy**: uses the first match, not the longest. Order matters.

## Operator precedence (highest to lowest)

| Precedence | Operator | Description |
|------------|----------|-------------|
| 1 | `\( \)` | Grouping |
| 2 | `\=`, `\+`, `*`, `\{n}`, etc. | Quantifiers |
| 3 | `abc\t\.\w` | Sequence of characters/metacharacters |
| 4 | `\|` | Alternation |

## Global command

```
:range g[lobal][!]/pattern/cmd
```

Executes Ex command `cmd` on every line matching `pattern` (or non-matching with `!`). Default range is the whole file. Default `cmd` is `:p`.

Runs in two passes: first marks matching lines, then executes `cmd` on each.

```vim
:g/^$/ d                    " delete all empty lines
:g/^$/,/./-j                " reduce multiple blank lines to one
:10,20g/^/ mo 10            " reverse lines 10–20
:'a,'b g/^Error/ . w >> errors.txt   " append Error lines to file
```

Chain commands with `|`:

```vim
:g/^Error:/ copy $ | s/Error/copy of the error/
```

## Practical examples

```vim
" strip trailing whitespace
s:\s\+$::

" match a sentence that starts with lowercase after punctuation
\.\s\+[a-z]

" match table column 3 and replace
:%s:\(\(\w\+\s\+\)\{2}\)Europe:\1Asia:

" swap first and last columns
:%s:\(\w\+\)\(.*\s\+\)\(\w\+\)$:\3\2\1:

" put \(\) pair into pattern quickly (insert mode mapping)
cmap ;\ \(\)<Left><Left>

" useful S&R mappings for .vimrc
noremap ;; :%s:::g<Left><Left><Left>
noremap ;' :%s:::cg<Left><Left><Left><Left>
```

## Vim vs Perl regex differences

- Vim requires backslashes before most operators (`\+`, `\=`, `\{`, `\|`, `\(`, `\)`). Perl does not.
- Perl non-greedy: add `?` after any quantifier (`*?`, `+?`). Vim uses `\{-}`.
- Perl supports extended options embedded in patterns; Vim does not.
- Perl supports variable interpolation in patterns; Vim does not.

