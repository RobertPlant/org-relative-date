;;; org-relative-date.el --- Live relative-date overlays on org timestamps  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Rob Plant

;; Author: Rob Plant <rob@robertplant.io>
;; Assisted-by: Claude:claude-opus-4-8
;; Maintainer: Rob Plant <rob@robertplant.io>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: calendar, org, convenience
;; URL: https://github.com/RobertPlant/org-relative-date

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; `org-relative-date-mode' paints a live "(N days away)" / "(N days ago)"
;; annotation *after* every Org timestamp in the buffer, without modifying the
;; file.  It is the spiritual successor to `time-uuid-mode': rather than
;; replacing text via a `display' property, it appends an `after-string' overlay,
;; so the raw `<2027-01-09 Sat .+6m>' stays visible and editable.
;;
;; Overlays are painted lazily through `jit-lock' (only the visible region is
;; scanned, so large agenda/journal files stay responsive), and a daily timer
;; re-runs them so the counts do not go stale at midnight.
;;
;; Usage:
;;
;;   (add-hook 'org-mode-hook #'org-relative-date-mode)
;;
;; or turn it on everywhere with `global-org-relative-date-mode'.

;;; Code:

(require 'org)

(defgroup org-relative-date nil
  "Live relative-date overlays on Org timestamps."
  :group 'org
  :prefix "org-relative-date-")

(defcustom org-relative-date-include-inactive t
  "When non-nil, annotate inactive [timestamps] as well as active <ones>.
Inactive timestamps include CLOSED: markers and logbook entries."
  :type 'boolean
  :group 'org-relative-date)

(defcustom org-relative-date-formatter #'org-relative-date-default-formatter
  "Function mapping a day delta (integer) to the overlay string.
Positive means in the future, negative means in the past, 0 is today.
The returned string is shown verbatim after the timestamp, so include
any desired leading space."
  :type 'function
  :group 'org-relative-date)

(defface org-relative-date-face
  '((((background dark))  :foreground "#c5cdd9" :slant italic)
    (((background light)) :foreground "#4c4c4c" :slant italic)
    (t                    :inherit font-lock-comment-face :slant italic))
  "Face for the relative-date overlay text.
Brighter than a plain comment so the annotation is easy to scan, while
staying italic to mark it as non-buffer text.  The foreground adapts to
light and dark backgrounds; override this face to taste."
  :group 'org-relative-date)

(defvar org-relative-date--timer nil
  "Shared daily timer that refreshes overlays so counts stay current.")

(defun org-relative-date-default-formatter (days)
  "Default DAYS -> label mapping (e.g. -1 -> \" yesterday\")."
  (cond ((=  days  0) " today")
        ((=  days  1) " tomorrow")
        ((= days -1) " yesterday")
        ((>  days  0) (format " %dd away" days))
        (t            (format " %dd ago" (- days)))))

(defun org-relative-date--regexp ()
  "Return the timestamp regexp to scan for, honouring user options."
  (if org-relative-date-include-inactive org-ts-regexp-both org-ts-regexp))

(defun org-relative-date--days (inside)
  "Return whole-day delta from today for INSIDE, the text between brackets.
INSIDE looks like \"2027-01-09 Sat .+6m\"; only the date head is used.
Uses absolute Gregorian day numbers so the count is immune to DST and
timezone drift."
  (- (org-time-string-to-absolute (car (split-string inside)))
     (org-today)))

(defun org-relative-date--clear (beg end)
  "Delete this mode's overlays between BEG and END."
  (dolist (o (overlays-in beg end))
    (when (overlay-get o 'org-relative-date) (delete-overlay o))))

(defun org-relative-date--apply (beg end)
  "`jit-lock' worker: (re)annotate every timestamp between BEG and END."
  (save-excursion
    (goto-char beg)
    (org-relative-date--clear (line-beginning-position) end)
    (let ((re (org-relative-date--regexp)))
      (while (re-search-forward re end t)
        (let ((o (make-overlay (match-end 0) (match-end 0)))
              (days (org-relative-date--days (match-string 1))))
          (overlay-put o 'org-relative-date t)
          (overlay-put o 'after-string
                       (propertize (funcall org-relative-date-formatter days)
                                   'face 'org-relative-date-face)))))))

(defun org-relative-date--refresh-all ()
  "Re-run overlays in every buffer where the mode is active.
Called by the daily timer so open buffers do not show yesterday's counts."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (bound-and-true-p org-relative-date-mode)
        (jit-lock-refontify)))))

;;;###autoload
(define-minor-mode org-relative-date-mode
  "Show a live \"(N days away)\" overlay after every Org timestamp."
  :lighter " RelDate"
  (if org-relative-date-mode
      (progn
        (jit-lock-register #'org-relative-date--apply)
        (unless org-relative-date--timer
          (setq org-relative-date--timer
                (run-at-time "00:01" 86400 #'org-relative-date--refresh-all))))
    (jit-lock-unregister #'org-relative-date--apply)
    (org-relative-date--clear (point-min) (point-max))))

(defun org-relative-date--turn-on ()
  "Enable `org-relative-date-mode' in Org buffers only.
Buffer-predicate for `global-org-relative-date-mode', which would
otherwise try to switch the mode on in every buffer."
  (when (derived-mode-p 'org-mode)
    (org-relative-date-mode 1)))

;;;###autoload
(define-globalized-minor-mode global-org-relative-date-mode
  org-relative-date-mode org-relative-date--turn-on
  :group 'org-relative-date)

;; To enable everywhere, add to your init:
;;   (add-hook 'org-mode-hook #'org-relative-date-mode)
;; or:
;;   (global-org-relative-date-mode 1)

(provide 'org-relative-date)
;;; org-relative-date.el ends here
