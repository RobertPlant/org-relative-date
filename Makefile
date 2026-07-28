EMACS ?= emacs
BATCH  = $(EMACS) -Q --batch -L . -L test

SRC  = org-relative-date.el
TEST = test/org-relative-date-test.el

.PHONY: all compile checkdoc test clean

all: compile checkdoc test

## Byte-compile with warnings promoted to errors, as MELPA does.
compile:
	$(BATCH) --eval '(setq byte-compile-error-on-warn t)' \
	         -f batch-byte-compile $(SRC) $(TEST)

## checkdoc only prints; the wrapper turns findings into a non-zero exit.
checkdoc:
	$(BATCH) -l test/checkdoc-batch.el $(SRC)

test:
	$(BATCH) -l $(TEST) -f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc test/*.elc
