;;; org-relative-date-test.el --- Tests for org-relative-date  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Rob Plant

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Run with:
;;
;;   make test
;;
;; or directly:
;;
;;   emacs -Q --batch -L . -L test \
;;     -l test/org-relative-date-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org-relative-date)

;;;; Helpers

(defun org-relative-date-test--labels ()
  "Return the overlay labels currently painted in the buffer, in order."
  (let (labels)
    (dolist (o (sort (overlays-in (point-min) (point-max))
                     (lambda (a b) (< (overlay-start a) (overlay-start b)))))
      (when (overlay-get o 'org-relative-date)
        (push (substring-no-properties (overlay-get o 'after-string)) labels)))
    (nreverse labels)))

(defmacro org-relative-date-test--with-org (text &rest body)
  "Run BODY in a temporary Org buffer containing TEXT, point at `point-min'.
The mode's global timer is torn down afterwards so tests cannot leak
state into one another."
  (declare (indent 1) (debug (form body)))
  `(unwind-protect
       (with-temp-buffer
         (delay-mode-hooks (org-mode))
         (insert ,text)
         (goto-char (point-min))
         ,@body)
     (when org-relative-date--timer
       (cancel-timer org-relative-date--timer)
       (setq org-relative-date--timer nil))))

(defun org-relative-date-test--stamp (days)
  "Return an active Org timestamp DAYS from today."
  (format-time-string "<%Y-%m-%d %a>"
                      (time-add nil (days-to-time days))))

;;;; Day arithmetic and formatting

(ert-deftest org-relative-date-test-default-formatter ()
  "The default formatter special-cases the three nearby days."
  (should (equal (org-relative-date-default-formatter 0) " today"))
  (should (equal (org-relative-date-default-formatter 1) " tomorrow"))
  (should (equal (org-relative-date-default-formatter -1) " yesterday"))
  (should (equal (org-relative-date-default-formatter 12) " 12d away"))
  (should (equal (org-relative-date-default-formatter -12) " 12d ago")))

(ert-deftest org-relative-date-test-days-ignores-time-and-repeater ()
  "Only the date head matters; time-of-day and repeaters are ignored."
  (let ((today (format-time-string "%Y-%m-%d")))
    (should (= 0 (org-relative-date--days today)))
    (should (= 0 (org-relative-date--days (concat today " Mon"))))
    (should (= 0 (org-relative-date--days (concat today " Mon 23:59"))))
    (should (= 0 (org-relative-date--days (concat today " Mon .+6m"))))))

(ert-deftest org-relative-date-test-days-is-dst-proof ()
  "Day deltas use absolute day numbers, so DST boundaries do not shift them.
Europe/London springs forward on 2027-03-28; a delta spanning it must
still come out as a whole number of days."
  (let ((process-environment (cons "TZ=Europe/London" process-environment)))
    (should (= 1 (- (org-time-string-to-absolute "2027-03-29")
                    (org-time-string-to-absolute "2027-03-28"))))))

;;;; Painting

(ert-deftest org-relative-date-test-annotates-active-and-inactive ()
  "Both <active> and [inactive] timestamps get a label by default."
  (org-relative-date-test--with-org
      (concat "SCHEDULED: " (org-relative-date-test--stamp 1) "\n"
              "CLOSED: [" (format-time-string "%Y-%m-%d %a 15:30") "]\n")
    (let ((org-relative-date-include-inactive t))
      (org-relative-date--apply (point-min) (point-max))
      (should (equal (org-relative-date-test--labels)
                     '(" tomorrow" " today"))))))

(ert-deftest org-relative-date-test-include-inactive-nil ()
  "With `org-relative-date-include-inactive' nil, only <active> ones count."
  (org-relative-date-test--with-org
      (concat "SCHEDULED: " (org-relative-date-test--stamp 1) "\n"
              "CLOSED: [" (format-time-string "%Y-%m-%d %a 15:30") "]\n")
    (let ((org-relative-date-include-inactive nil))
      (org-relative-date--apply (point-min) (point-max))
      (should (equal (org-relative-date-test--labels) '(" tomorrow"))))))

(ert-deftest org-relative-date-test-custom-formatter ()
  "`org-relative-date-formatter' controls the label text."
  (org-relative-date-test--with-org (org-relative-date-test--stamp 3)
    (let ((org-relative-date-formatter (lambda (d) (format " (in %d days)" d))))
      (org-relative-date--apply (point-min) (point-max))
      (should (equal (org-relative-date-test--labels) '(" (in 3 days)"))))))

(ert-deftest org-relative-date-test-buffer-text-untouched ()
  "Overlays must not modify the buffer text or mark it dirty."
  (let ((text (concat "* TODO a\n  SCHEDULED: "
                      (org-relative-date-test--stamp 5) "\n")))
    (org-relative-date-test--with-org text
      (set-buffer-modified-p nil)
      (org-relative-date--apply (point-min) (point-max))
      (should (equal (buffer-string) text))
      (should-not (buffer-modified-p)))))

;;;; Idempotence at region boundaries

(ert-deftest org-relative-date-test-reapply-does-not-duplicate ()
  "Re-running over the same region replaces labels rather than stacking them."
  (org-relative-date-test--with-org
      (concat "SCHEDULED: " (org-relative-date-test--stamp 1) "\n")
    (org-relative-date--apply (point-min) (point-max))
    (org-relative-date--apply (point-min) (point-max))
    (should (equal (org-relative-date-test--labels) '(" tomorrow")))))

(ert-deftest org-relative-date-test-reapply-at-region-end ()
  "A timestamp ending exactly at the region END is not double-annotated.
`overlays-in' omits empty overlays at END unless END is `point-max', so
the clear range has to be padded; this is the regression guard for that."
  (org-relative-date-test--with-org
      (concat (org-relative-date-test--stamp 1) "trailing text\n")
    (let ((end (1+ (length (org-relative-date-test--stamp 1)))))
      (org-relative-date--apply (point-min) end)
      (org-relative-date--apply (point-min) end)
      (should (equal (org-relative-date-test--labels) '(" tomorrow"))))))

;;;; Mode lifecycle

(ert-deftest org-relative-date-test-disable-clears-overlays ()
  "Turning the mode off removes every overlay it painted."
  (org-relative-date-test--with-org
      (concat "SCHEDULED: " (org-relative-date-test--stamp 1) "\n")
    (org-relative-date-mode 1)
    (org-relative-date--apply (point-min) (point-max))
    (should (org-relative-date-test--labels))
    (org-relative-date-mode -1)
    (should-not (org-relative-date-test--labels))))

(ert-deftest org-relative-date-test-disable-clears-past-narrowing ()
  "Overlays outside a narrowing are cleared too.
`org-narrow-to-subtree' is routine, and a plain point-min/point-max
clear would strand every overlay outside the visible region."
  (org-relative-date-test--with-org
      (concat "* a\n" (org-relative-date-test--stamp 1) "\n"
              "* b\n" (org-relative-date-test--stamp 2) "\n")
    (org-relative-date-mode 1)
    (org-relative-date--apply (point-min) (point-max))
    (should (= 2 (length (org-relative-date-test--labels))))
    (narrow-to-region (point-min) (+ (point-min) 4))
    (org-relative-date-mode -1)
    (widen)
    (should-not (org-relative-date-test--labels))))

(ert-deftest org-relative-date-test-timer-lifecycle ()
  "The shared timer starts on first enable and stops after the last disable."
  (let ((b1 (generate-new-buffer " *ord-test-1*"))
        (b2 (generate-new-buffer " *ord-test-2*")))
    (unwind-protect
        (progn
          (with-current-buffer b1 (delay-mode-hooks (org-mode))
                               (org-relative-date-mode 1))
          (should org-relative-date--timer)
          (with-current-buffer b2 (delay-mode-hooks (org-mode))
                               (org-relative-date-mode 1))
          (with-current-buffer b1 (org-relative-date-mode -1))
          (should org-relative-date--timer)
          (with-current-buffer b2 (org-relative-date-mode -1))
          ;; Both the handle and the actual scheduled timer must be gone;
          ;; nilling the variable alone would orphan a running timer.
          (should-not org-relative-date--timer)
          (should-not (cl-find-if
                       (lambda (T)
                         (eq (timer--function T)
                             #'org-relative-date--refresh-all))
                       timer-list)))
      (when org-relative-date--timer
        (cancel-timer org-relative-date--timer)
        (setq org-relative-date--timer nil))
      (kill-buffer b1)
      (kill-buffer b2))))

;;;; Globalized mode

(ert-deftest org-relative-date-test-turn-on-skips-non-org ()
  "The globalized mode's predicate leaves non-Org buffers alone."
  (with-temp-buffer
    (fundamental-mode)
    (org-relative-date--turn-on)
    (should-not (bound-and-true-p org-relative-date-mode))))

(ert-deftest org-relative-date-test-turn-on-enables-in-org ()
  "The globalized mode's predicate does enable the mode in Org buffers."
  (org-relative-date-test--with-org ""
    (org-relative-date--turn-on)
    (should (bound-and-true-p org-relative-date-mode))
    (org-relative-date-mode -1)))

;;;; Options

(ert-deftest org-relative-date-test-option-set-repaints ()
  "Changing an option through Custom repaints buffers that are already on."
  (let ((original org-relative-date-include-inactive))
    (org-relative-date-test--with-org
        (concat "CLOSED: [" (format-time-string "%Y-%m-%d %a 15:30") "]\n"
                (org-relative-date-test--stamp 1) "\n")
      (unwind-protect
          (progn
            (org-relative-date-mode 1)
            (org-relative-date--apply (point-min) (point-max))
            (should (= 2 (length (org-relative-date-test--labels))))
            (customize-set-variable 'org-relative-date-include-inactive nil)
            ;; `--refresh-all' schedules the repaint via jit-lock; batch mode
            ;; never redisplays, so drive the repaint explicitly.
            (org-relative-date--apply (point-min) (point-max))
            (should (equal (org-relative-date-test--labels) '(" tomorrow"))))
        (customize-set-variable 'org-relative-date-include-inactive original)
        (org-relative-date-mode -1)))))

(ert-deftest org-relative-date-test-options-use-our-setter ()
  "Both options route user changes through `org-relative-date--set-option'."
  (dolist (sym '(org-relative-date-include-inactive
                 org-relative-date-formatter))
    (should (eq (get sym 'custom-set) #'org-relative-date--set-option))))

(ert-deftest org-relative-date-test-loads-cleanly-in-fresh-emacs ()
  "The file must load without error in a virgin Emacs.
The options' `:set' function calls `org-relative-date--refresh-all',
which is defined further down the file, so the default
`custom-initialize-reset' — which invokes `:set' to seed the initial
value — would raise void-function during `defcustom'.  Only a fresh
process catches this; by the time this suite runs, everything is
already defined."
  (let ((dir (file-name-directory (locate-library "org-relative-date")))
        (emacs (expand-file-name invocation-name invocation-directory)))
    (should (eq 0 (call-process emacs nil nil nil
                                "-Q" "--batch" "-L" dir
                                "-l" "org-relative-date")))))

(provide 'org-relative-date-test)
;;; org-relative-date-test.el ends here
