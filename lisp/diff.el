;;; diff.el --- run `diff' in compilation-mode

;; Copyright (C) 1992, 1994, 1996, 2001, 2002, 2003, 2004, 2005, 2006,
;;   2007, 2008, 2009, 2010 Free Software Foundation, Inc.

;; Author: Frank Bresz
;; (according to authors.el)
;; Maintainer: FSF
;; Keywords: unix, tools

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package helps you explore differences between files, using the
;; UNIX command diff(1).  The commands are `diff' and `diff-backup'.
;; You can specify options with `diff-switches'.

;;; Code:

(defgroup diff nil
  "Comparing files with `diff'."
  :group 'tools)

;;;###autoload
(defcustom diff-switches (purecopy "-c")
  "A string or list of strings specifying switches to be passed to diff."
  :type '(choice string (repeat string))
  :group 'diff)

;;;###autoload
(defcustom diff-command (purecopy "diff")
  "The command to use to run diff."
  :type 'string
  :group 'diff)

(defvar diff-old-temp-file nil
  "This is the name of a temp file to be deleted after diff finishes.")
(defvar diff-new-temp-file nil
  "This is the name of a temp file to be deleted after diff finishes.")

;; prompt if prefix arg present
(defun diff-switches ()
  (if current-prefix-arg
      (read-string "Diff switches: "
		   (if (stringp diff-switches)
		       diff-switches
		     (mapconcat 'identity diff-switches " ")))))

(defun diff-sentinel (code)
  "Code run when the diff process exits.
CODE is the exit code of the process.  It should be 0 only if no diffs
were found."
  (if diff-old-temp-file (delete-file diff-old-temp-file))
  (if diff-new-temp-file (delete-file diff-new-temp-file))
  (save-excursion
    (goto-char (point-max))
    (let ((inhibit-read-only t))
      (insert (format "\nDiff finished%s.  %s\n"
		      (cond ((equal 0 code) " (no differences)")
			    ((equal 2 code) " (diff error)")
			    (t ""))
		      (current-time-string))))))

(defvar diff-old-file nil)
(defvar diff-new-file nil)
(defvar diff-extra-args nil)

;;;###autoload
(defun diff (old new &optional switches no-async)
  "Find and display the differences between OLD and NEW files.
When called interactively, read OLD and NEW using the minibuffer;
the default for NEW is the current buffer's file name, and the
default for OLD is a backup file for NEW, if one exists.
If NO-ASYNC is non-nil, call diff synchronously.

When called interactively with a prefix argument, prompt
interactively for diff switches.  Otherwise, the switches
specified in `diff-switches' are passed to the diff command."
  (interactive
   (let (oldf newf)
     (setq newf (buffer-file-name)
	   newf (if (and newf (file-exists-p newf))
		    (read-file-name
		     (concat "Diff new file (default "
			     (file-name-nondirectory newf) "): ")
		     nil newf t)
		  (read-file-name "Diff new file: " nil nil t)))
     (setq oldf (file-newest-backup newf)
	   oldf (if (and oldf (file-exists-p oldf))
		    (read-file-name
		     (concat "Diff original file (default "
			     (file-name-nondirectory oldf) "): ")
		     (file-name-directory oldf) oldf t)
		  (read-file-name "Diff original file: "
				  (file-name-directory newf) nil t)))
     (list oldf newf (diff-switches))))
  (setq new (expand-file-name new)
	old (expand-file-name old))
  (or switches (setq switches diff-switches)) ; If not specified, use default.
  (let* ((old-alt (file-local-copy old))
	(new-alt (file-local-copy new))
	 (command
	  (mapconcat 'identity
		     `(,diff-command
		       ;; Use explicitly specified switches
		       ,@(if (listp switches) switches (list switches))
		       ,@(if (or old-alt new-alt)
			     (list "-L" old "-L" new))
		       ,(shell-quote-argument (or old-alt old))
		       ,(shell-quote-argument (or new-alt new)))
		     " "))
	 (buf (get-buffer-create "*Diff*"))
	 (thisdir default-directory)
	 proc)
    (save-excursion
      (display-buffer buf)
      (set-buffer buf)
      (setq buffer-read-only nil)
      (buffer-disable-undo (current-buffer))
      (let ((inhibit-read-only t))
	(erase-buffer))
      (buffer-enable-undo (current-buffer))
      (diff-mode)
      ;; Use below 2 vars for backward-compatibility.
      (set (make-local-variable 'diff-old-file) old)
      (set (make-local-variable 'diff-new-file) new)
      (set (make-local-variable 'diff-extra-args) (list switches no-async))
      (set (make-local-variable 'revert-buffer-function)
	   (lambda (ignore-auto noconfirm)
             (apply 'diff diff-old-file diff-new-file diff-extra-args)))
      (set (make-local-variable 'diff-old-temp-file) old-alt)
      (set (make-local-variable 'diff-new-temp-file) new-alt)
      (setq default-directory thisdir)
      (let ((inhibit-read-only t))
	(insert command "\n"))
      (if (and (not no-async) (fboundp 'start-process))
	  (progn
	    (setq proc (start-process "Diff" buf shell-file-name
				      shell-command-switch command))
	    (set-process-filter proc 'diff-process-filter)
	    (set-process-sentinel
	     proc (lambda (proc msg)
		    (with-current-buffer (process-buffer proc)
		      (diff-sentinel (process-exit-status proc))))))
	;; Async processes aren't available.
	(let ((inhibit-read-only t))
	  (diff-sentinel
	   (call-process shell-file-name nil buf nil
			 shell-command-switch command)))))
    buf))

(defun diff-process-filter (proc string)
  (with-current-buffer (process-buffer proc)
    (let ((moving (= (point) (process-mark proc))))
      (save-excursion
	;; Insert the text, advancing the process marker.
	(goto-char (process-mark proc))
	(let ((inhibit-read-only t))
	  (insert string))
	(set-marker (process-mark proc) (point)))
      (if moving (goto-char (process-mark proc))))))

;;;###autoload
(defun diff-backup (file &optional switches)
  "Diff this file with its backup file or vice versa.
Uses the latest backup, if there are several numerical backups.
If this file is a backup, diff it with its original.
The backup file is the first file given to `diff'.
With prefix arg, prompt for diff switches."
  (interactive (list (read-file-name "Diff (file with backup): ")
		     (diff-switches)))
  (let (bak ori)
    (if (backup-file-name-p file)
	(setq bak file
	      ori (file-name-sans-versions file))
      (setq bak (or (diff-latest-backup-file file)
		    (error "No backup found for %s" file))
	    ori file))
    (diff bak ori switches)))

(defun diff-latest-backup-file (fn)	; actually belongs into files.el
  "Return the latest existing backup of FILE, or nil."
  (let ((handler (find-file-name-handler fn 'diff-latest-backup-file)))
    (if handler
	(funcall handler 'diff-latest-backup-file fn)
      (file-newest-backup fn))))

(provide 'diff)

;; arch-tag: 7de2c29b-7ea5-4b85-9b9d-72dd860de2bd
;;; diff.el ends here
