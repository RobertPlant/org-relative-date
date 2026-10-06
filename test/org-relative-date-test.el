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
  "Return an active Org timestamp DAYS from today.
Counted in whole days rather than adding 86400s, which lands on the
wrong date within an hour of midnight on a DST weekend."
  (format-time-string "<%Y-%m-%d %a>"
                      (org-time-from-absolute (+ (org-today) days))))

(defmacro org-relative-date-test--on (date text &rest body)
  "Run BODY in an Org buffer containing TEXT, with today pinned to DATE.
DATE is a \"YYYY-MM-DD\" string.  Pinning makes the edge cases run on
every CI run, not only on the day the calendar happens to reach them."
  (declare (indent 2) (debug (form form body)))
  `(cl-letf (((symbol-function 'org-today)
              (let ((day (org-time-string-to-absolute ,date)))
                (lambda () day))))
     (org-relative-date-test--with-org ,text ,@body)))

(defun org-relative-date-test--paint ()
  "Paint the whole buffer and return its labels."
  (org-relative-date--apply (point-min) (point-max))
  (org-relative-date-test--labels))

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

(ert-deftest org-relative-date-test-year-boundary ()
  "Counts run straight across New Year in both directions."
  (org-relative-date-test--on "2026-12-31"
      "<2027-01-01 Fri> [2026-01-01 Thu] <2027-12-31 Fri>"
    (should (equal (org-relative-date-test--paint)
                   '(" tomorrow" " 364d ago" " 365d away")))))

(ert-deftest org-relative-date-test-leap-day ()
  "28 Feb to 1 Mar is two days in a leap year and one otherwise."
  (org-relative-date-test--on "2028-02-28" "<2028-03-01 Wed>"
    (should (equal (org-relative-date-test--paint) '(" 2d away"))))
  (org-relative-date-test--on "2027-02-28" "<2027-03-01 Mon>"
    (should (equal (org-relative-date-test--paint) '(" tomorrow")))))

(ert-deftest org-relative-date-test-dst-changeovers ()
  "Both Europe/London changeovers give whole days, label and extra format.
The extra format converts the stamp to a time, which is where a DST
hour could push it onto the neighbouring date."
  (let ((tz (getenv "TZ")))
    (unwind-protect
        (progn
          (set-time-zone-rule "Europe/London")
          (let ((org-relative-date-extra-format " %F"))
            (org-relative-date-test--on "2027-03-27" "<2027-03-29 Mon>"
              (should (equal (org-relative-date-test--paint)
                             '(" 2d away 2027-03-29"))))
            (org-relative-date-test--on "2027-11-01" "[2027-10-30 Sat]"
              (should (equal (org-relative-date-test--paint)
                             '(" 2d ago 2027-10-30"))))))
      (set-time-zone-rule tz))))

;;;; Timestamp variants

(ert-deftest org-relative-date-test-date-range ()
  "Each end of a <a>--<b> range gets its own label."
  (org-relative-date-test--on "2027-01-10" "<2027-01-09 Sat>--<2027-01-12 Tue>"
    (should (equal (org-relative-date-test--paint) '(" yesterday" " 2d away")))))

(ert-deftest org-relative-date-test-time-range ()
  "A time range inside one stamp is a single date."
  (org-relative-date-test--on "2027-01-10" "<2027-01-10 Sun 10:00-12:00>"
    (should (equal (org-relative-date-test--paint) '(" today")))))

(ert-deftest org-relative-date-test-repeater-and-warning ()
  "Repeaters and warning delays are ignored; only the date counts."
  (org-relative-date-test--on "2027-01-10"
      "<2027-01-09 Sat .+6m> <2027-01-12 Tue +1w -2d>"
    (should (equal (org-relative-date-test--paint) '(" yesterday" " 2d away")))))

(ert-deftest org-relative-date-test-diary-sexp-ignored ()
  "Diary sexp stamps have no single date, so they get no label."
  (org-relative-date-test--on "2027-01-10" "<%%(diary-float t 4 2)>"
    (should-not (org-relative-date-test--paint))))

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

(ert-deftest org-relative-date-test-extra-format-nil-by-default ()
  "`org-relative-date-extra-format' is off unless the user sets it."
  (should-not (default-value 'org-relative-date-extra-format))
  (org-relative-date-test--with-org (org-relative-date-test--stamp 3)
    (org-relative-date--apply (point-min) (point-max))
    (should (equal (org-relative-date-test--labels) '(" 3d away")))))

(ert-deftest org-relative-date-test-extra-format-week-number ()
  "A `format-time-string' spec is appended, read off the timestamp's own date.
Not off today's date: the stamp here is three days out, so a
week-number that came from `current-time' would be wrong whenever
those three days cross a Monday."
  (let ((stamp (org-relative-date-test--stamp 3)))
    (org-relative-date-test--with-org stamp
      (let ((org-relative-date-extra-format " W%V"))
        (org-relative-date--apply (point-min) (point-max))
        (should (equal (org-relative-date-test--labels)
                       (list (format " 3d away W%s"
                                     (format-time-string
                                      "%V" (org-time-from-absolute
                                            (+ (org-today) 3)))))))))))

(ert-deftest org-relative-date-test-extra-format-iso-week-boundary ()
  "The week number is ISO-8601, so 2027-01-01 is week 53 of 2026, not week 1."
  (org-relative-date-test--with-org "<2027-01-01 Fri>"
    (let ((org-relative-date-extra-format " W%V")
          (org-relative-date-formatter (lambda (_days) "")))
      (org-relative-date--apply (point-min) (point-max))
      (should (equal (org-relative-date-test--labels) '(" W53"))))))

(ert-deftest org-relative-date-test-extra-format-survives-custom-formatter ()
  "The extra format is independent of the formatter, which may clobber match data.
A formatter doing its own `string-match' must not cost the extra
format the timestamp it is supposed to read."
  (org-relative-date-test--with-org "<2027-01-01 Fri>"
    (let ((org-relative-date-extra-format " W%V")
          (org-relative-date-formatter
           (lambda (_days) (string-match "x" "x") " soon")))
      (org-relative-date--apply (point-min) (point-max))
      (should (equal (org-relative-date-test--labels) '(" soon W53"))))))

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
                         (eq (timer--function T) #'org-relative-date--tick))
                       timer-list)))
      (when org-relative-date--timer
        (cancel-timer org-relative-date--timer)
        (setq org-relative-date--timer nil))
      (kill-buffer b1)
      (kill-buffer b2))))

;;;; Date-change timer

(ert-deftest org-relative-date-test-tick-repaints-only-on-new-day ()
  "The timer repaints once when the date changes and not on other ticks."
  (let ((org-relative-date--painted-day nil)
        (today (org-time-string-to-absolute "2027-10-31"))
        (repaints 0))
    (cl-letf (((symbol-function 'org-today) (lambda () today))
              ((symbol-function 'org-relative-date--refresh-all)
               (lambda () (cl-incf repaints))))
      (org-relative-date--tick)
      (org-relative-date--tick)
      (should (= repaints 1))
      (cl-incf today)
      (org-relative-date--tick)
      (org-relative-date--tick)
      (should (= repaints 2)))))

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
  "Every option routes user changes through `org-relative-date--set-option'."
  (dolist (sym '(org-relative-date-include-inactive
                 org-relative-date-formatter
                 org-relative-date-extra-format))
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
