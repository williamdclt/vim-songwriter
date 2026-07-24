---
name: vader
description: Use when writing, reading, or debugging Vader (.vader) test files for Vimscript. Covers Given/Do/Execute/Then/Expect blocks, Before/After hooks, Include macros, assertions, isolated test environments, CI integration, and known pitfalls like feedkeys() and CursorMoved events.
---

# Vader — Vimscript Testing

Vader is a BDD-style testing framework for Vimscript. Tests are written in `.vader` files as flat sequences of blocks.

## Running tests

```vim
:Vader [file glob ...]    " run tests, stay in Vim
:Vader! [file glob ...]   " run tests, exit Vim with status 0 (pass) or 1 (fail)
```

One-liner from shell:

```bash
vim '+Vader! *.vader' && echo pass || echo fail
```

If a `Do` or `Execute` description contains `FIXME` or `TODO`, that block is treated as pending and does not affect exit status.

Set `VADER_OUTPUT_FILE` environment variable to write results to a file.

## File structure

A `.vader` file is a flat sequence of blocks. Each block starts with a label followed by content indented 2 spaces.

```
    Label (comment):
      content
      more content
```

End the label with `;` instead of `:` to skip the 2-space indent requirement:

```
    Label;
content without indent
```

## Block types

### Given

Pastes content into the workbench buffer for subsequent `Do`/`Execute` blocks.

```
    Given [filetype] [(comment)]:
      [input text]
```

Optional `filetype` sets `'filetype'` on the buffer and syntax-highlights the block in the `.vader` file.

### Do

Normal-mode keystrokes that can span multiple lines.

```
    Do [(comment)]:
      [keystrokes]
```

Special keys use angle brackets preceded by backslash: `\<Enter>`, `\<Esc>`, `\<C-C>`, etc.

Can be followed by `Expect` and/or `Then`.

### Execute

Plain Vimscript to execute.

```
    Execute [(comment)]:
      [vimscript]
```

Can be followed by `Expect` and/or `Then`.

To test language interfaces (Ruby/Python/Perl/Lua), specify the language:

```
    Execute ruby (call a Ruby function):
      puts "hello from Ruby"
```

### Then

Vimscript to run after a `Do` or `Execute` block. Used for assertions.

```
    Then [(comment)]:
      [vimscript]
```

Can be combined with `Expect`.

### Expect

Compares the result of the preceding `Do` or `Execute` block against expected content. Comparison is case-sensitive.

```
    Expect [filetype] [(comment)]:
      [expected output]
```

Optional `filetype` is used for syntax highlighting.

## Assertions (in Execute/Then)

```vim
Assert <boolean expr> [, message]
AssertEqual <expected>, <got> [, message]
AssertNotEqual <unexpected>, <got> [, message]
AssertThrows <command>
```

`AssertThrows` sets `g:vader_exception` (like `v:exception`) and `g:vader_throwpoint` (like `v:throwpoint`).

## Helper commands (in Execute)

```vim
Log "Message"            " print to test output
Save <name> [, ...]      " save state by name
Restore [<name>, ...]    " restore saved state
```

## Syntax helpers

```vim
SyntaxAt()              " syntax group at cursor
SyntaxAt(col)           " syntax group at given column on current line
SyntaxAt(lnum, col)     " syntax group at line and column
SyntaxOf(pattern)       " syntax group at first char of first match
SyntaxOf(pattern, nth)  " syntax group at first char of nth match
```

`g:vader_file` holds the path of the current `.vader` file.

## Hooks

### Before

Executed before every following `Do`/`Execute` block.

```
    Before [(comment)]:
      [vimscript]
```

### After

Executed after every following `Do`/`Execute` block.

```
    After [(comment)]:
      [vimscript]
```

## Macros

### Include

Include other `.vader` files at the point of use:

```
    Include: setup.vader

    Given (buffer):
      hello

    Include: cleanup.vader
```

## Comments

Lines starting with `#`, `"`, `=`, `-`, `~`, `^`, or `*` (without indentation) are comments:

```
    ###################
    # Test description #
    ###################

    Given (fixture):
    ================
      Hello world
```

## Complete example

```
    # Test assertions and syntax

    Execute (check line count):
      Assert 1 == line('$')

    Execute (set and check filetype):
      setf python
      AssertEqual 'python', &filetype

    Given ruby (a Ruby function):
      def a
        a = 1
        end

    Do (indent the block):
      vip=

    Expect ruby (properly indented):
      def a
        a = 1
      end

    Given c (C code):
      int i = 0;

    Execute (check syntax highlighting):
      AssertEqual SyntaxAt(1, 5), 'cType'
      AssertEqual SyntaxOf('0'), 'cNumber'
```

## Isolated test environment

When testing a plugin, isolate it from other plugins and settings:

```bash
vim -Nu <(cat << EOF
filetype off
set rtp+=~/.vim/bundle/vader.vim
set rtp+=~/.vim/bundle/my-plugin
set rtp+=~/.vim/bundle/my-plugin/after
filetype plugin indent on
syntax enable
EOF) +Vader\ test/*.vader
```

## CI integration

Minimal `.travis.yml`:

```yaml
language: vim

before_script: |
  git clone https://github.com/junegunn/vader.vim.git

script: |
  vim -Nu <(cat << VIMRC
  filetype off
  set rtp+=vader.vim
  set rtp+=.
  set rtp+=after
  filetype plugin indent on
  syntax enable
  VIMRC) -c 'Vader! test/*' > /dev/null
```

## Known issues

### feedkeys() cannot be tested

Keystrokes passed to `feedkeys()` are consumed only after Vader finishes the `Do`/`Execute` block. This means interleaving `feedkeys()` with other keystrokes produces unexpected ordering. No known workaround.

### CursorMoved events

`CursorMoved` autocommands may not fire inside `Do` blocks. Manually trigger with `:doautocmd CursorMoved\<CR>` mid-block:

```
    Do (with manual event):
      jjj
      :doautocmd CursorMoved\<CR>
```

### Search history

Search history may not update correctly during `Do` blocks. Avoid testing `histget()` for search patterns in `Do` blocks.

## Writing tests: practical tips

- Use `Given` to set up buffer content, `Do` for keystrokes, `Execute`/`Then` for assertions
- Use `Expect` to verify buffer content after `Do` blocks
- Use `Before`/`After` for repeated setup/teardown
- Use `Include` to share common fixtures between test files
- Mark known-broken tests with `FIXME` or `TODO` in the description so they don't fail CI
- Always test against an isolated Vim runtime to avoid plugin interference
