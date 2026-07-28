EMACS ?= emacs
BATCH  = $(EMACS) -Q --batch -L . -L test

SRC   = org-relative-date.el
TESTS = test/org-relative-date-test.el test/run-tests.el

.PHONY: all compile checkdoc test clean

all: compile checkdoc test

## Byte-compile with warnings promoted to errors, as MELPA does.
compile:
	$(BATCH) --eval '(setq byte-compile-error-on-warn t)' \
	         -f batch-byte-compile $(SRC) $(TESTS)

## checkdoc only prints; the wrapper turns findings into a non-zero exit.
checkdoc:
	$(BATCH) -l test/checkdoc-batch.el $(SRC)

## The runner adds a floor on how many tests must run; a suite that stops
## being discovered would otherwise exit 0 having verified nothing.
test:
	$(BATCH) -l test/run-tests.el

clean:
	rm -f *.elc test/*.elc
