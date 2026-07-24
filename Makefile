VADER := $(HOME)/.vim/pack/plugins/start/vader

test:
	vim -N -u NONE \
		-c "set rtp+=$(VADER),." \
		-c "runtime plugin/vader.vim" \
		-c "Vader! test/*.vader"

.PHONY: test
