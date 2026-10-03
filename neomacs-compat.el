;;; neomacs-compat.el --- Compatibility shims for Neomacs -*- lexical-binding: t; -*-

;; Loaded from `dotspacemacs/user-init' in init.el, which runs before
;; `configuration-layer/load' installs packages.  Kept in its own file so that
;; `git pull upstream main' never has to merge it.

;;; Commentary:

;; Neomacs is a from-scratch Rust reimplementation of Emacs rather than a fork
;; of the C sources, so the Lisp layer is genuine Emacs but every *primitive*
;; is re-implemented -- and primitives are where the compatibility gaps live.
;;
;; Each shim below is written to engage only after the real primitive fails,
;; so this file is inert on GNU Emacs and goes quiet by itself once Neomacs
;; fixes the underlying bug.  That means one configuration runs unchanged on
;; either binary, with no feature detection and nothing to remember to undo.

;;; Code:


;;; `set-file-times' fails on directories
;;
;; Neomacs 0.0.19 (Emacs 31.1, aarch64-apple-darwin) signals
;;
;;     (file-error "Setting file times" "Is a directory" "/path/to/dir/")
;;
;; for any directory, where GNU Emacs succeeds.  That is the signature of
;; implementing the primitive as futimens(open(path, O_WRONLY)) instead of
;; utimensat(AT_FDCWD, path, ...) -- open(2) on a directory with write intent
;; returns EISDIR.
;;
;; `copy-directory' calls `set-file-times' on its destination when KEEP-TIME is
;; non-nil and that destination already exists.  quelpa does exactly that when
;; building Spacemacs' bundled local packages (core/libs/quelpa.el, in
;; `quelpa-check-hash': delete-directory -> make-directory -> copy-directory
;; with KEEP-TIME t).  So all seven fail to install:
;;
;;     holy-mode  hybrid-mode  evil-evilified-state  spacemacs-whitespace-cleanup
;;     spacemacs-purpose-popwin  space-doc  evil-unimpaired
;;
;; and startup dies three layers downstream of the actual fault, with
;;
;;     Symbol's value as variable is void: evil-evilified-state-map
;;
;; touch(1) sets times on directories perfectly well, so fall back to it.

(defvar neomacs-compat--touch-warned nil
  "Non-nil once we have warned that touch(1) could not be found.")

(defun neomacs-compat--set-file-times-via-touch (filename &optional timestamp flag)
  "Set FILENAME's times using touch(1).
TIMESTAMP and FLAG are as for `set-file-times'.  Return t on success."
  (let ((touch (executable-find "touch")))
    (if (null touch)
        (progn
          (unless neomacs-compat--touch-warned
            (setq neomacs-compat--touch-warned t)
            (display-warning
             'neomacs-compat
             "`set-file-times' fails on directories and touch(1) was not found; directory timestamps will not be preserved"
             :warning))
          nil)
      (eq 0 (apply #'call-process touch nil nil nil
                   (append (and (eq flag 'nofollow) '("-h"))
                           (list "-t" (format-time-string
                                       "%Y%m%d%H%M.%S"
                                       (or timestamp (current-time)))
                                 (expand-file-name filename))))))))

(define-advice set-file-times
    (:around (orig filename &optional timestamp flag) neomacs-directory-fallback)
  "Retry via touch(1) when Neomacs refuses to time-stamp a directory.
Anything that is not a local directory re-signals unchanged, so a genuine
permission or missing-file error still surfaces normally."
  (condition-case err
      (funcall orig filename timestamp flag)
    (file-error
     (if (and (not (file-remote-p filename))
              (file-directory-p filename))
         (neomacs-compat--set-file-times-via-touch filename timestamp flag)
       (signal (car err) (cdr err))))))


(provide 'neomacs-compat)

;;; neomacs-compat.el ends here
