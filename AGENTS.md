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
- Never `funcall` a symbol looked up from an alist or built with `intern`. Calling the user's
  `org-relative-date-formatter` is fine.
- Functions under ~50 lines. Comments are rare one-line notes on why.
- New behaviour gets an ERT test in `test/org-relative-date-test.el`, and the test has to fail without the
  change.
- No em-dashes in code, comments or docs. Use a comma, hyphen or full stop.
