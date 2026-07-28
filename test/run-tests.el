;;; run-tests.el --- Batch ERT runner with a test-count floor  -*- lexical-binding: t; -*-

;;; Commentary:

;; `ert-run-tests-batch-and-exit' exits 0 when it runs *no* tests, so a suite
;; that silently stops being discovered - a rename, a load failure swallowed
;; somewhere, a selector that matches nothing - reports a green build having
;; verified nothing at all.  This runner additionally fails when fewer than
;; `run-tests-minimum' tests ran.
;;
;; The floor is a floor, not an exact count: adding tests never breaks it,
;; but losing a chunk of the suite does.
;;
;; Usage: emacs -Q --batch -L . -L test -l test/run-tests.el

;;; Code:

(require 'ert)
(require 'org-relative-date-test)

(defconst run-tests-minimum 15
  "Fail the run if fewer than this many tests execute.")

(let* ((stats (ert-run-tests-batch t))
       (total (ert-stats-total stats))
       (unexpected (ert-stats-completed-unexpected stats)))
  (cond
   ((< total run-tests-minimum)
    (message "\nrun-tests: only %d test(s) ran, expected at least %d.\n\
The suite is not being discovered properly; a green run here would be\n\
meaningless." total run-tests-minimum)
    (kill-emacs 1))
   ((> unexpected 0)
    (kill-emacs 1))
   (t
    (kill-emacs 0))))

(provide 'run-tests)
;;; run-tests.el ends here
