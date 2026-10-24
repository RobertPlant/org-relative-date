# AGENTS.md

## Code style

Run `make` before committing: byte-compile with warnings as errors, `checkdoc`, then the ERT suite. CI runs
the same three on Emacs 27.1 to 31.1, so nothing newer than `Package-Requires` allows.

- Every symbol starts with `org-relative-date-`, and internal ones with `org-relative-date--`.
- `defgroup`, `defcustom`, `defface` and `defvar` at the top of the file. Every `defcustom` has `:type` and
  `:group`, and the options keep `:set` / `:initialize` so changing one repaints open buffers.
- A one-line docstring on every function and variable, in the imperative ("Remove overlays between BEG and
  END."). `checkdoc` must stay clean.
- `;;;###autoload` on the modes and interactive commands only.
- `let*` names each step and each condition (`(is-org (derived-mode-p 'org-mode))`), then `when` for guards
  and `cond` / `pcase` for cases. Close parens on the last line, never on their own.
- Helpers compute and return values. Overlays, timers and hooks only change in the mode functions and the
  `jit-lock` callback. Buffer-local hooks use the `nil t` local arguments.
- `seq-*` and `mapcar` over loops. `dolist` only where the body is a side effect (making overlays).
- Nothing destructive on values you were given: `remove` not `delete`, `append` not `nconc`, `reverse` not
  `nreverse`. No `setq` on an argument, plain `let` for temporaries.
- Nor change a value once it's made, a list a call returned included: no `sort`, `setcar` or `nconc` on it.
  `seq-sort` copies (keyword `sort` is Emacs 30, newer than `Package-Requires`). A list the function is still
  building with `push` is fine.
- Values first, then effects: the `let*` bindings work out everything the body needs, label text included,
  then the body makes the overlays and changes timers and hooks together. Only a value that needs an effect's
  result comes after it.
- A list is plural and each thing in it singular, a lambda's argument included: `(dolist (overlay (overlays-in
  beg end)) ...)`, never `o`, `buf` or `x`. A sort's comparator keeps `(a b)`. No abbreviations.
- A function's name is a verb and its object: `count` / `format` for a value worked out from what it's given,
  `add` / `remove` for overlays, `-p` for a predicate. Not a bare noun (`--days`, `--labels`) or a noun and a
  preposition.
- No banner comments over a group of functions or tests (`;;;; Helpers`); the names say what they are.
  `;;; Commentary:` and `;;; Code:` are package headers and stay.
- Never `funcall` a symbol looked up from an alist or built with `intern`. Calling the user's
  `org-relative-date-formatter` is fine.
- Functions under ~50 lines. Comments are rare one-line notes on why.
- New behaviour gets an ERT test in `test/org-relative-date-test.el`, and the test has to fail without the
  change.
- No em-dashes in code, comments or docs. Use a comma, hyphen or full stop.
- Commit messages are one line, past tense, full stop, under about 60 characters: `Added an optional
  format-time-string suffix after the label.` Say what changed, not how. A body only for the why the diff
  can't show.
