;;; checkdoc-batch.el --- Fail the build on any checkdoc complaint  -*- lexical-binding: t; -*-

;;; Commentary:

;; `checkdoc-file' only reports its findings; it never signals and never sets
;; a non-zero exit status, so CI would happily go green on a docstring that
;; checkdoc hates.  This wrapper makes any finding fatal.
;;
;; Under --batch, checkdoc reports through `display-warning' (straight to
;; stderr) and leaves the diagnostic buffer empty, so watching that buffer
;; alone silently passes everything.  Hook both paths.
;;
;; Usage: emacs -Q --batch -l test/checkdoc-batch.el FILE...

;;; Code:

(require 'checkdoc)

(defvar checkdoc-batch--found nil
  "Set when checkdoc reports anything at all.")

(defun checkdoc-batch--note (&rest _)
  "Record that checkdoc had something to say."
  (setq checkdoc-batch--found t))

(advice-add 'display-warning :before #'checkdoc-batch--note)

(dolist (file command-line-args-left)
  (checkdoc-file file))

(advice-remove 'display-warning #'checkdoc-batch--note)

(let ((buf (get-buffer checkdoc-diagnostic-buffer)))
  (when (and buf (> (buffer-size buf) 0))
    (princ (with-current-buffer buf (buffer-string)))
    (setq checkdoc-batch--found t)))

(when checkdoc-batch--found
  (message "checkdoc: findings above must be fixed")
  (kill-emacs 1))

(provide 'checkdoc-batch)
;;; checkdoc-batch.el ends here
