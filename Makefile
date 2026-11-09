# Vader.vim checkout used by the tests. Override with `make test VADER=/path`.
# When missing, it is cloned on first run.
VADER ?= $(HOME)/.vim/pack/plugins/start/vader

# Run the full test suite. This is fast, default to doing that rather than running a single test.
# -n: no swap files, so test buffers leave nothing behind in the repo.
test: $(VADER)
	vim -N -n -u NONE \
		-c "set rtp+=$(VADER),." \
		-c "filetype plugin on" \
		-c "runtime plugin/vader.vim" \
		-c "runtime plugin/songwriter.vim" \
		-c "Vader! test/*.vader" \
		-c "qa!"

$(VADER):
	git clone --depth 1 https://github.com/junegunn/vader.vim $(VADER)

# Use the tracked git hooks (pre-commit runs the tests).
hooks:
	git config core.hooksPath githooks

.PHONY: test hooks
