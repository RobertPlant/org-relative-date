# org-relative-date

Live **"(N days away)" / "(N days ago)"** annotations after every Org timestamp,
without ever touching the file.

```org
* TODO Renew domain
  SCHEDULED: <2027-01-09 Sat>          166d away
* DONE Ship release
  CLOSED: [2026-07-27 Mon 15:30]       today
* Meeting notes
  <2026-07-28 Tue 10:00>               tomorrow
```

The greyed-out labels above are overlays — the buffer text is still just the raw
`<2027-01-09 Sat>`, so nothing is written to disk, timestamps stay editable, and
point/column math is unaffected.

## Why

Org's *agenda* shows relative days, but only in the agenda buffer. This annotates
timestamps **inline, in the file itself**, so a plain `TODO` list or journal reads
at a glance without switching to the agenda.

It's a spiritual successor to `time-uuid-mode`: where that *replaced* text via a
`display` property, this *appends* an `after-string` overlay, keeping the original
text visible and editable.

## Install

Once on [MELPA](https://melpa.org):

```elisp
(use-package org-relative-date
  :hook (org-mode . org-relative-date-mode))
```

Meanwhile, straight from GitHub (Doom Emacs example):

```elisp
;; packages.el
(package! org-relative-date
  :recipe (:host github :repo "RobertPlant/org-relative-date"))

;; config.el
(add-hook 'org-mode-hook #'org-relative-date-mode)
```

## Usage

Enable `org-relative-date-mode` in any Org buffer (the hook above does this
automatically). Toggle it off to remove every overlay.

To turn it on for every Org buffer at once without a hook, enable the
globalized mode instead:

```elisp
(global-org-relative-date-mode 1)
```

Overlays are painted lazily through `jit-lock`, so only the visible portion of a
buffer is scanned — large journals and agenda files stay responsive. A daily timer
refreshes the counts at 00:01 so an open buffer never shows yesterday's numbers.

## Customization

| Option | Default | Meaning |
|---|---|---|
| `org-relative-date-include-inactive` | `t` | Also annotate inactive `[…]` timestamps (`CLOSED:`, logbook lines), not just active `<…>` ones. Set to `nil` for a quieter, appointment-only view. |
| `org-relative-date-formatter` | `org-relative-date-default-formatter` | Function mapping a day delta (integer; negative = past, `0` = today) to the label string. Override to change wording, e.g. `"in 3 days"` instead of `"3d away"`. |
| `org-relative-date-face` | inherits `font-lock-comment-face`, italic | Face applied to the overlay text. |

Example — custom wording and active-only:

```elisp
(setq org-relative-date-include-inactive nil)
(setq org-relative-date-formatter
      (lambda (days)
        (cond ((=  days 0) " (today)")
              ((>  days 0) (format " (in %d days)" days))
              (t           (format " (%d days ago)" (- days))))))
```

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
