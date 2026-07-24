VADER := $(HOME)/.vim/pack/plugins/start/vader

test:
	vim -N -u NONE \
		-c "set rtp+=$(VADER),." \
		-c "runtime plugin/vader.vim" \
		-c "runtime plugin/songwriter.vim" \
		-c "Vader! test/*.vader" \
		-c "qa!"

.PHONY: test
