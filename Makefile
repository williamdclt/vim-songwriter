VADER := $(HOME)/.vim/pack/plugins/start/vader

# Run the full test suite. This is fast, default to doing that rather than running a single test.
test:
	vim -N -u NONE \
		-c "set rtp+=$(VADER),." \
		-c "runtime plugin/vader.vim" \
		-c "runtime plugin/songwriter.vim" \
		-c "Vader! test/*.vader" \
		-c "qa!"

.PHONY: test
