# Vader.vim checkout used by the tests. Override with `make test VADER=/path`.
# When missing, it is cloned on first run.
VADER ?= $(HOME)/.vim/pack/plugins/start/vader

# Number of test files run at once. Override with `make test JOBS=1`.
JOBS ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)

TESTS := $(wildcard test/*.vader)

# Run the full test suite. This is fast, default to doing that rather than running a single test.
# Each file runs in its own Vim, JOBS at a time.
test: $(VADER)
	@$(MAKE) --no-print-directory -k -j$(JOBS) $(TESTS:%=%.run)

# One test file. Vader writes its report to a log, printed whole once the file
# is done (so that parallel reports do not interleave): the whole report on
# failure (without Vader's `vim --version` banner), a one-line summary otherwise.
# -n: no swap files, so test buffers leave nothing behind in the repo.
# --not-a-term: Vim's output goes to /dev/null; without it Vim pauses 2s.
# nofsync: Vader appends to the log with writefile() once per line, and an
# fsync each time doubles the run.
%.vader.run:
	@log=$$(mktemp); \
	if VADER_OUTPUT_FILE=$$log vim --not-a-term -N -n -u NONE \
		-c "set rtp+=$(VADER),. nofsync" \
		-c "filetype plugin on" \
		-c "runtime plugin/vader.vim" \
		-c "runtime plugin/songwriter.vim" \
		-c "let g:songwriter_check = 1" \
		-c "Vader! $*.vader" \
		-c "qa!" </dev/null >/dev/null 2>&1; then \
		echo "ok   $*.vader: $$(grep -o 'Success/Total: [0-9/]*' $$log | tail -1)"; \
		rm -f $$log; \
	else \
		sed -n '/^Starting Vader/,$$p' $$log; echo "FAIL $*.vader"; rm -f $$log; exit 1; \
	fi

# The fuzz tests (test/invariants/fuzz.vader) with more seeds and longer key
# sequences than `make test` runs. Override with `make fuzz FUZZ_SEEDS=200`;
# replay one failing seed with `make fuzz FUZZ_SEED=17`.
FUZZ_SEEDS ?= 20
FUZZ_LENGTH ?= 30
fuzz: $(VADER)
	@FUZZ_SEEDS=$(FUZZ_SEEDS) FUZZ_LENGTH=$(FUZZ_LENGTH) FUZZ_SEED=$(FUZZ_SEED) \
		$(MAKE) --no-print-directory -k -j$(JOBS) $(patsubst %,%.run,$(wildcard test/songwriter_invariants_fuzz*.vader))

$(VADER):
	git clone --depth 1 https://github.com/junegunn/vader.vim $(VADER)

# Use the tracked git hooks (pre-commit runs the tests).
hooks:
	git config core.hooksPath githooks

.PHONY: test fuzz hooks
