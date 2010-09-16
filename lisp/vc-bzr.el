;;; vc-bzr.el --- VC backend for the bzr revision control system

;; Copyright (C) 2006, 2007, 2008, 2009, 2010  Free Software Foundation, Inc.

;; Author: Dave Love <fx@gnu.org>
;; 	   Riccardo Murri <riccardo.murri@gmail.com>
;; Keywords: tools
;; Created: Sept 2006
;; Version: 2008-01-04 (Bzr revno 25)
;; URL: http://launchpad.net/vc-bzr

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

;; See <URL:http://bazaar-vcs.org/> concerning bzr.  See
;; <URL:http://launchpad.net/vc-bzr> for alternate development
;; branches of `vc-bzr'.

;; Load this library to register bzr support in VC.

;; Known bugs
;; ==========

;; When editing a symlink and *both* the symlink and its target
;; are bzr-versioned, `vc-bzr` presently runs `bzr status` on the
;; symlink, thereby not detecting whether the actual contents
;; (that is, the target contents) are changed.
;; See https://bugs.launchpad.net/vc-bzr/+bug/116607

;; For an up-to-date list of bugs, please see:
;;   https://bugs.launchpad.net/vc-bzr/+bugs

;;; Properties of the backend

(defun vc-bzr-revision-granularity () 'repository)
(defun vc-bzr-checkout-model (files) 'implicit)

;;; Code:

(eval-when-compile
  (require 'cl)
  (require 'vc)  ;; for vc-exec-after
  (require 'vc-dir))

;; Clear up the cache to force vc-call to check again and discover
;; new functions when we reload this file.
(put 'Bzr 'vc-functions nil)

(defgroup vc-bzr nil
  "VC bzr backend."
  :version "22.2"
  :group 'vc)

(defcustom vc-bzr-program "bzr"
  "Name of the bzr command (excluding any arguments)."
  :group 'vc-bzr
  :type 'string)

(defcustom vc-bzr-diff-switches nil
  "String or list of strings specifying switches for bzr diff under VC.
If nil, use the value of `vc-diff-switches'.  If t, use no switches."
  :type '(choice (const :tag "Unspecified" nil)
                 (const :tag "None" t)
                 (string :tag "Argument String")
                 (repeat :tag "Argument List" :value ("") string))
  :group 'vc-bzr)

(defcustom vc-bzr-log-switches nil
  "String or list of strings specifying switches for bzr log under VC."
  :type '(choice (const :tag "None" nil)
                 (string :tag "Argument String")
                 (repeat :tag "Argument List" :value ("") string))
  :group 'vc-bzr)

;; since v0.9, bzr supports removing the progress indicators
;; by setting environment variable BZR_PROGRESS_BAR to "none".
(defun vc-bzr-command (bzr-command buffer okstatus file-or-list &rest args)
  "Wrapper round `vc-do-command' using `vc-bzr-program' as COMMAND.
Invoke the bzr command adding `BZR_PROGRESS_BAR=none' and
`LC_MESSAGES=C' to the environment."
  (let ((process-environment
         (list* "BZR_PROGRESS_BAR=none" ; Suppress progress output (bzr >=0.9)
                "LC_MESSAGES=C"         ; Force English output
                process-environment)))
    (apply 'vc-do-command (or buffer "*vc*") okstatus vc-bzr-program
           file-or-list bzr-command args)))


;;;###autoload
(defconst vc-bzr-admin-dirname ".bzr"
  "Name of the directory containing Bzr repository status files.")
;;;###autoload
(defconst vc-bzr-admin-checkout-format-file
  (concat vc-bzr-admin-dirname "/checkout/format"))
(defconst vc-bzr-admin-dirstate
  (concat vc-bzr-admin-dirname "/checkout/dirstate"))
(defconst vc-bzr-admin-branch-format-file
  (concat vc-bzr-admin-dirname "/branch/format"))
(defconst vc-bzr-admin-revhistory
  (concat vc-bzr-admin-dirname "/branch/revision-history"))
(defconst vc-bzr-admin-lastrev
  (concat vc-bzr-admin-dirname "/branch/last-revision"))

;;;###autoload (defun vc-bzr-registered (file)
;;;###autoload   (if (vc-find-root file vc-bzr-admin-checkout-format-file)
;;;###autoload       (progn
;;;###autoload         (load "vc-bzr")
;;;###autoload         (vc-bzr-registered file))))

(defun vc-bzr-root (file)
  "Return the root directory of the bzr repository containing FILE."
  ;; Cache technique copied from vc-arch.el.
  (or (vc-file-getprop file 'bzr-root)
      (let ((root (vc-find-root file vc-bzr-admin-checkout-format-file)))
	(when root (vc-file-setprop file 'bzr-root root)))))

(require 'sha1)                         ;For sha1-program

(defun vc-bzr-sha1 (file)
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (let ((prog sha1-program)
          (args nil)
	  process-file-side-effects)
      (when (consp prog)
	(setq args (cdr prog))
        (setq prog (car prog)))
      (apply 'process-file prog (file-relative-name file) t nil args)
      (buffer-substring (point-min) (+ (point-min) 40)))))

(defun vc-bzr-state-heuristic (file)
  "Like `vc-bzr-state' but hopefully without running Bzr."
  ;; `bzr status' was excrutiatingly slow with large histories and
  ;; pending merges, so try to avoid using it until they fix their
  ;; performance problems.
  ;; This function tries first to parse Bzr internal file
  ;; `checkout/dirstate', but it may fail if Bzr internal file format
  ;; has changed.  As a safeguard, the `checkout/dirstate' file is
  ;; only parsed if it contains the string `#bazaar dirstate flat
  ;; format 3' in the first line.
  ;; If the `checkout/dirstate' file cannot be parsed, fall back to
  ;; running `vc-bzr-state'."
  (lexical-let ((root (vc-bzr-root file)))
    (when root    ; Short cut.
      ;; This looks at internal files.  May break if they change
      ;; their format.
      (lexical-let ((dirstate (expand-file-name vc-bzr-admin-dirstate root)))
        (condition-case nil
            (with-temp-buffer
              (insert-file-contents dirstate)
              (goto-char (point-min))
              (if (not (looking-at "#bazaar dirstate flat format 3"))
                  (vc-bzr-state file)   ; Some other unknown format?
                (let* ((relfile (file-relative-name file root))
                       (reldir (file-name-directory relfile)))
                  (if (re-search-forward
                       (concat "^\0"
                               (if reldir (regexp-quote
                                           (directory-file-name reldir)))
                               "\0"
                               (regexp-quote (file-name-nondirectory relfile))
                               "\0"
                               "[^\0]*\0"     ;id?
                               "\\([^\0]*\\)\0" ;"a/f/d", a=removed?
                               "\\([^\0]*\\)\0" ;sha1 (empty if conflicted)?
                               "\\([^\0]*\\)\0" ;size?p
                               "[^\0]*\0"       ;"y/n", executable?
                               "[^\0]*\0"       ;?
                               "\\([^\0]*\\)\0" ;"a/f/d" a=added?
                               "\\([^\0]*\\)\0" ;sha1 again?
                               "\\([^\0]*\\)\0" ;size again?
                               "[^\0]*\0" ;"y/n", executable again?
                               "[^\0]*\0" ;last revid?
                               ;; There are more fields when merges are pending.
                               )
                       nil t)
                      ;; Apparently the second sha1 is the one we want: when
                      ;; there's a conflict, the first sha1 is absent (and the
                      ;; first size seems to correspond to the file with
                      ;; conflict markers).
                      (cond
                       ((eq (char-after (match-beginning 1)) ?a) 'removed)
                       ((eq (char-after (match-beginning 4)) ?a) 'added)
                       ((or (and (eq (string-to-number (match-string 3))
                                 (nth 7 (file-attributes file)))
                             (equal (match-string 5)
                                    (vc-bzr-sha1 file)))
			    (and
			     ;; It looks like for lightweight
			     ;; checkouts \2 is empty and we need to
			     ;; look for size in \6.
			     (eq (match-beginning 2) (match-end 2))
			     (eq (string-to-number (match-string 6))
				 (nth 7 (file-attributes file)))
			     (equal (match-string 5)
				    (vc-bzr-sha1 file))))
                        'up-to-date)
                       (t 'edited))
                    'unregistered))))
          ;; Either the dirstate file can't be read, or the sha1
          ;; executable is missing, or ...
          ;; In either case, recent versions of Bzr aren't that slow
          ;; any more.
          (error (vc-bzr-state file)))))))


(defun vc-bzr-registered (file)
  "Return non-nil if FILE is registered with bzr."
  (let ((state (vc-bzr-state-heuristic file)))
    (not (memq state '(nil unregistered ignored)))))

(defconst vc-bzr-state-words
  "added\\|ignored\\|kind changed\\|modified\\|removed\\|renamed\\|unknown"
  "Regexp matching file status words as reported in `bzr' output.")

(defun vc-bzr-file-name-relative (filename)
  "Return file name FILENAME stripped of the initial Bzr repository path."
  (lexical-let*
      ((filename* (expand-file-name filename))
       (rootdir (vc-bzr-root filename*)))
    (when rootdir
         (file-relative-name filename* rootdir))))

(defun vc-bzr-status (file)
  "Return FILE status according to Bzr.
Return value is a cons (STATUS . WARNING), where WARNING is a
string or nil, and STATUS is one of the symbols: `added',
`ignored', `kindchanged', `modified', `removed', `renamed', `unknown',
which directly correspond to `bzr status' output, or 'unchanged
for files whose copy in the working tree is identical to the one
in the branch repository, or nil for files that are not
registered with Bzr.

If any error occurred in running `bzr status', then return nil."
  (with-temp-buffer
    (let ((ret (condition-case nil
                   (vc-bzr-command "status" t 0 file)
                 (file-error nil)))     ; vc-bzr-program not found.
          (status 'unchanged))
          ;; the only secure status indication in `bzr status' output
          ;; is a couple of lines following the pattern::
          ;;   | <status>:
          ;;   |   <file name>
          ;; if the file is up-to-date, we get no status report from `bzr',
          ;; so if the regexp search for the above pattern fails, we consider
          ;; the file to be up-to-date.
          (goto-char (point-min))
          (when (re-search-forward
                 ;; bzr prints paths relative to the repository root.
                 (concat "^\\(" vc-bzr-state-words "\\):[ \t\n]+"
                         (regexp-quote (vc-bzr-file-name-relative file))
                         ;; Bzr appends a '/' to directory names and
                         ;; '*' to executable files
                         (if (file-directory-p file) "/?" "\\*?")
                         "[ \t\n]*$")
                 nil t)
            (lexical-let ((statusword (match-string 1)))
              ;; Erase the status text that matched.
              (delete-region (match-beginning 0) (match-end 0))
              (setq status
                    (intern (replace-regexp-in-string " " "" statusword)))))
          (when status
            (goto-char (point-min))
            (skip-chars-forward " \n\t") ;Throw away spaces.
            (cons status
                  ;; "bzr" will output warnings and informational messages to
                  ;; stderr; due to Emacs' `vc-do-command' (and, it seems,
                  ;; `start-process' itself) limitations, we cannot catch stderr
                  ;; and stdout into different buffers.  So, if there's anything
                  ;; left in the buffer after removing the above status
                  ;; keywords, let us just presume that any other message from
                  ;; "bzr" is a user warning, and display it.
                  (unless (eobp) (buffer-substring (point) (point-max))))))))

(defun vc-bzr-state (file)
  (lexical-let ((result (vc-bzr-status file)))
    (when (consp result)
      (when (cdr result)
	(message "Warnings in `bzr' output: %s" (cdr result)))
      (cdr (assq (car result)
                 '((added . added)
                   (kindchanged . edited)
                   (renamed . edited)
                   (modified . edited)
                   (removed . removed)
                   (ignored . ignored)
                   (unknown . unregistered)
                   (unchanged . up-to-date)))))))

(defun vc-bzr-resolve-when-done ()
  "Call \"bzr resolve\" if the conflict markers have been removed."
  (save-excursion
    (goto-char (point-min))
    (unless (re-search-forward "^<<<<<<< " nil t)
      (vc-bzr-command "resolve" nil 0 buffer-file-name)
      ;; Remove the hook so that it is not called multiple times.
      (remove-hook 'after-save-hook 'vc-bzr-resolve-when-done t))))

(defun vc-bzr-find-file-hook ()
  (when (and buffer-file-name
             ;; FIXME: We should check that "bzr status" says "conflict".
             (file-exists-p (concat buffer-file-name ".BASE"))
             (file-exists-p (concat buffer-file-name ".OTHER"))
             (file-exists-p (concat buffer-file-name ".THIS"))
             ;; If "bzr status" says there's a conflict but there are no
             ;; conflict markers, it's not clear what we should do.
             (save-excursion
               (goto-char (point-min))
               (re-search-forward "^<<<<<<< " nil t)))
    ;; TODO: the merge algorithm used in `bzr merge' is nicely configurable,
    ;; but the one in `bzr pull' isn't, so it would be good to provide an
    ;; elisp function to remerge from the .BASE/OTHER/THIS files.
    (smerge-start-session)
    (add-hook 'after-save-hook 'vc-bzr-resolve-when-done nil t)
    (message "There are unresolved conflicts in this file")))

(defun vc-bzr-workfile-unchanged-p (file)
  (eq 'unchanged (car (vc-bzr-status file))))

(defun vc-bzr-working-revision (file)
  ;; Together with the code in vc-state-heuristic, this makes it possible
  ;; to get the initial VC state of a Bzr file even if Bzr is not installed.
  (lexical-let*
      ((rootdir (vc-bzr-root file))
       (branch-format-file (expand-file-name vc-bzr-admin-branch-format-file
                                             rootdir))
       (revhistory-file (expand-file-name vc-bzr-admin-revhistory rootdir))
       (lastrev-file (expand-file-name vc-bzr-admin-lastrev rootdir)))
    ;; This looks at internal files to avoid forking a bzr process.
    ;; May break if they change their format.
    (if (and (file-exists-p branch-format-file)
	     ;; For lightweight checkouts (obtained with bzr checkout --lightweight)
	     ;; the branch-format-file does not contain the revision
	     ;; information, we need to look up the branch-format-file
	     ;; in the place where the lightweight checkout comes
	     ;; from.  We only do that if it's a local file.
	     (let ((location-fname (expand-file-name
				    (concat vc-bzr-admin-dirname
					    "/branch/location") rootdir)))
	       ;; The existence of this file is how we distinguish
	       ;; lightweight checkouts.
	       (if (file-exists-p location-fname)
		   (with-temp-buffer
		     (insert-file-contents location-fname)
		     ;; If the lightweight checkout points to a
		     ;; location in the local file system, then we can
		     ;; look there for the version information.
		     (when (re-search-forward "file://\\(.+\\)" nil t)
		       (let ((l-c-parent-dir (match-string 1)))
			 (when (and (memq system-type '(ms-dos windows-nt))
				    (string-match-p "^/[[:alpha:]]:" l-c-parent-dir))
			   ;;; The non-Windows code takes a shortcut by using the host/path
			   ;;; separator slash as the start of the absolute path.  That
			   ;;; does not work on Windows, so we must remove it (bug#5345)
			   (setq l-c-parent-dir (substring l-c-parent-dir 1)))
			 (setq branch-format-file
			       (expand-file-name vc-bzr-admin-branch-format-file
						 l-c-parent-dir))
			 (setq lastrev-file
			       (expand-file-name vc-bzr-admin-lastrev l-c-parent-dir))
			 ;; FIXME: maybe it's overkill to check if both these files exist.
			 (and (file-exists-p branch-format-file)
			      (file-exists-p lastrev-file)))))
		 t)))
        (with-temp-buffer
          (insert-file-contents branch-format-file)
          (goto-char (point-min))
          (cond
           ((or
             (looking-at "Bazaar-NG branch, format 0.0.4")
             (looking-at "Bazaar-NG branch format 5"))
            ;; count lines in .bzr/branch/revision-history
            (insert-file-contents revhistory-file)
            (number-to-string (count-lines (line-end-position) (point-max))))
           ((or
	     (looking-at "Bazaar Branch Format 6 (bzr 0.15)")
	     (looking-at "Bazaar Branch Format 7 (needs bzr 1.6)"))
            ;; revno is the first number in .bzr/branch/last-revision
            (insert-file-contents lastrev-file)
            (when (re-search-forward "[0-9]+" nil t)
	      (buffer-substring (match-beginning 0) (match-end 0))))))
      ;; fallback to calling "bzr revno"
      (lexical-let*
          ((result (vc-bzr-command-discarding-stderr
                    vc-bzr-program "revno" (file-relative-name file)))
           (exitcode (car result))
           (output (cdr result)))
        (cond
         ((eq exitcode 0) (substring output 0 -1))
         (t nil))))))

(defun vc-bzr-create-repo ()
  "Create a new Bzr repository."
  (vc-bzr-command "init" nil 0 nil))

(defun vc-bzr-init-revision (&optional file)
  "Always return nil, as Bzr cannot register explicit versions."
  nil)

(defun vc-bzr-previous-revision (file rev)
  (if (string-match "\\`[0-9]+\\'" rev)
      (number-to-string (1- (string-to-number rev)))
    (concat "before:" rev)))

(defun vc-bzr-next-revision (file rev)
  (if (string-match "\\`[0-9]+\\'" rev)
      (number-to-string (1+ (string-to-number rev)))
    (error "Don't know how to compute the next revision of %s" rev)))

(defun vc-bzr-register (files &optional rev comment)
  "Register FILE under bzr.
Signal an error unless REV is nil.
COMMENT is ignored."
  (if rev (error "Can't register explicit revision with bzr"))
  (vc-bzr-command "add" nil 0 files))

;; Could run `bzr status' in the directory and see if it succeeds, but
;; that's relatively expensive.
(defalias 'vc-bzr-responsible-p 'vc-bzr-root
  "Return non-nil if FILE is (potentially) controlled by bzr.
The criterion is that there is a `.bzr' directory in the same
or a superior directory.")

(defun vc-bzr-could-register (file)
  "Return non-nil if FILE could be registered under bzr."
  (and (vc-bzr-responsible-p file)      ; shortcut
       (condition-case ()
           (with-temp-buffer
             (vc-bzr-command "add" t 0 file "--dry-run")
             ;; The command succeeds with no output if file is
             ;; registered (in bzr 0.8).
             (goto-char (point-min))
             (looking-at "added "))
         (error))))

(defun vc-bzr-unregister (file)
  "Unregister FILE from bzr."
  (vc-bzr-command "remove" nil 0 file "--keep"))

(defun vc-bzr-checkin (files rev comment)
  "Check FILE in to bzr with log message COMMENT.
REV non-nil gets an error."
  (if rev (error "Can't check in a specific revision with bzr"))
  (vc-bzr-command "commit" nil 0 files "-m" comment))

(defun vc-bzr-find-revision (file rev buffer)
  "Fetch revision REV of file FILE and put it into BUFFER."
    (with-current-buffer buffer
      (if (and rev (stringp rev) (not (string= rev "")))
          (vc-bzr-command "cat" t 0 file "-r" rev)
        (vc-bzr-command "cat" t 0 file))))

(defun vc-bzr-checkout (file &optional editable rev)
  (if rev (error "Operation not supported")
    ;; Else, there's nothing to do.
    nil))

(defun vc-bzr-revert (file &optional contents-done)
  (unless contents-done
    (with-temp-buffer (vc-bzr-command "revert" t 0 file))))

(defvar log-view-message-re)
(defvar log-view-file-re)
(defvar log-view-font-lock-keywords)
(defvar log-view-current-tag-function)
(defvar log-view-per-file-logs)
(defvar vc-short-log)

(define-derived-mode vc-bzr-log-view-mode log-view-mode "Bzr-Log-View"
  (remove-hook 'log-view-mode-hook 'vc-bzr-log-view-mode) ;Deactivate the hack.
  (require 'add-log)
  (set (make-local-variable 'log-view-per-file-logs) nil)
  (set (make-local-variable 'log-view-file-re) "\\`a\\`")
  (set (make-local-variable 'log-view-message-re)
       (if vc-short-log
	   "^ *\\([0-9.]+\\): \\(.*?\\)[ \t]+\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)\\( \\[merge\\]\\)?"
	 "^ *\\(?:revno: \\([0-9.]+\\)\\|merged: .+\\)"))
  (set (make-local-variable 'log-view-font-lock-keywords)
       ;; log-view-font-lock-keywords is careful to use the buffer-local
       ;; value of log-view-message-re only since Emacs-23.
       (if vc-short-log
	 (append `((,log-view-message-re
		    (1 'log-view-message-face)
		    (2 'change-log-name)
		    (3 'change-log-date)
		    (4 'change-log-list nil lax))))
	 (append `((,log-view-message-re . 'log-view-message-face))
		 ;; log-view-font-lock-keywords
		 '(("^ *\\(?:committer\\|author\\): \
\\([^<(]+?\\)[  ]*[(<]\\([[:alnum:]_.+-]+@[[:alnum:]_.-]+\\)[>)]"
		    (1 'change-log-name)
		    (2 'change-log-email))
		   ("^ *timestamp: \\(.*\\)" (1 'change-log-date-face)))))))

(defun vc-bzr-print-log (files buffer &optional shortlog start-revision limit)
  "Get bzr change log for FILES into specified BUFFER."
  ;; `vc-do-command' creates the buffer, but we need it before running
  ;; the command.
  (vc-setup-buffer buffer)
  ;; If the buffer exists from a previous invocation it might be
  ;; read-only.
  ;; FIXME: `vc-bzr-command' runs `bzr log' with `LC_MESSAGES=C', so
  ;; the log display may not what the user wants - but I see no other
  ;; way of getting the above regexps working.
  (with-current-buffer buffer
    (apply 'vc-bzr-command "log" buffer 'async files
	   (append
	    (when shortlog '("--line"))
	    (when start-revision (list (format "-r..%s" start-revision)))
	    (when limit (list "-l" (format "%s" limit)))
	    (if (stringp vc-bzr-log-switches)
		(list vc-bzr-log-switches)
	      vc-bzr-log-switches)))))

(defun vc-bzr-show-log-entry (revision)
  "Find entry for patch name REVISION in bzr change log buffer."
  (goto-char (point-min))
  (when revision
    (let (case-fold-search
	  found)
      (if (re-search-forward
	   ;; "revno:" can appear either at the beginning of a line,
	   ;; or indented.
	   (concat "^[ ]*-+\n[ ]*revno: "
		   ;; The revision can contain ".", quote it so that it
		   ;; does not interfere with regexp matching.
		   (regexp-quote revision) "$") nil t)
	  (progn
	    (beginning-of-line 0)
	    (setq found t))
	(goto-char (point-min)))
      found)))

(defun vc-bzr-diff (files &optional rev1 rev2 buffer)
  "VC bzr backend for diff."
  ;; `bzr diff' exits with code 1 if diff is non-empty.
  (apply #'vc-bzr-command "diff" (or buffer "*vc-diff*")
	 (if vc-disable-async-diff 1 'async) files
         "--diff-options" (mapconcat 'identity
                                     (vc-switches 'bzr 'diff)
				     " ")
         ;; This `when' is just an optimization because bzr-1.2 is *much*
         ;; faster when the revision argument is not given.
         (when (or rev1 rev2)
           (list "-r" (format "%s..%s"
                              (or rev1 "revno:-1")
                              (or rev2 ""))))))


;; FIXME: vc-{next,previous}-revision need fixing in vc.el to deal with
;; straight integer revisions.

(defun vc-bzr-delete-file (file)
  "Delete FILE and delete it in the bzr repository."
  (condition-case ()
      (delete-file file)
    (file-error nil))
  (vc-bzr-command "remove" nil 0 file))

(defun vc-bzr-rename-file (old new)
  "Rename file from OLD to NEW using `bzr mv'."
  (vc-bzr-command "mv" nil 0 new old))

(defvar vc-bzr-annotation-table nil
  "Internal use.")
(make-variable-buffer-local 'vc-bzr-annotation-table)

(defun vc-bzr-annotate-command (file buffer &optional revision)
  "Prepare BUFFER for `vc-annotate' on FILE.
Each line is tagged with the revision number, which has a `help-echo'
property containing author and date information."
  (apply #'vc-bzr-command "annotate" buffer 'async file "--long" "--all"
         (if revision (list "-r" revision)))
  (lexical-let ((table (make-hash-table :test 'equal)))
    (set-process-filter
     (get-buffer-process buffer)
     (lambda (proc string)
       (when (process-buffer proc)
         (with-current-buffer (process-buffer proc)
           (setq string (concat (process-get proc :vc-left-over) string))
           (while (string-match "^\\( *[0-9.]+ *\\) \\([^\n ]+\\) +\\([0-9]\\{8\\}\\)\\( |.*\n\\)" string)
             (let* ((rev (match-string 1 string))
                    (author (match-string 2 string))
                    (date (match-string 3 string))
                    (key (substring string (match-beginning 0)
                                    (match-beginning 4)))
                    (line (match-string 4 string))
                    (tag (gethash key table))
                    (inhibit-read-only t))
               (setq string (substring string (match-end 0)))
	       (unless tag
		 (setq tag
		       (propertize
			(format "%s %-7.7s" rev author)
			'help-echo (format "Revision: %d, author: %s, date: %s"
					   (string-to-number rev)
					   author date)
			'mouse-face 'highlight))
                 (puthash key tag table))
               (goto-char (process-mark proc))
               (insert tag line)
               (move-marker (process-mark proc) (point))))
           (process-put proc :vc-left-over string)))))))

(declare-function vc-annotate-convert-time "vc-annotate" (time))

(defun vc-bzr-annotate-time ()
  (when (re-search-forward "^ *[0-9.]+ +[^\n ]* +|" nil t)
    (let ((prop (get-text-property (line-beginning-position) 'help-echo)))
      (string-match "[0-9]+\\'" prop)
      (let ((str (match-string-no-properties 0 prop)))
      (vc-annotate-convert-time
       (encode-time 0 0 0
                      (string-to-number (substring str 6 8))
                      (string-to-number (substring str 4 6))
                      (string-to-number (substring str 0 4))))))))

(defun vc-bzr-annotate-extract-revision-at-line ()
  "Return revision for current line of annoation buffer, or nil.
Return nil if current line isn't annotated."
  (save-excursion
    (beginning-of-line)
    (if (looking-at "^ *\\([0-9.]+\\) +[^\n ]* +|")
        (match-string-no-properties 1))))

(defun vc-bzr-command-discarding-stderr (command &rest args)
  "Execute shell command COMMAND (with ARGS); return its output and exitcode.
Return value is a cons (EXITCODE . OUTPUT), where EXITCODE is
the (numerical) exit code of the process, and OUTPUT is a string
containing whatever the process sent to its standard output
stream.  Standard error output is discarded."
  (with-temp-buffer
    (cons
     (apply #'process-file command nil (list (current-buffer) nil) nil args)
     (buffer-substring (point-min) (point-max)))))

(defstruct (vc-bzr-extra-fileinfo
            (:copier nil)
            (:constructor vc-bzr-create-extra-fileinfo (extra-name))
            (:conc-name vc-bzr-extra-fileinfo->))
  extra-name)         ;; original name for rename targets, new name for

(defun vc-bzr-dir-printer (info)
  "Pretty-printer for the vc-dir-fileinfo structure."
  (let ((extra (vc-dir-fileinfo->extra info)))
    (vc-default-dir-printer 'Bzr info)
    (when extra
      (insert (propertize
	       (format "   (renamed from %s)"
		       (vc-bzr-extra-fileinfo->extra-name extra))
	       'face 'font-lock-comment-face)))))

;; FIXME: this needs testing, it's probably incomplete.
(defun vc-bzr-after-dir-status (update-function relative-dir)
  (let ((status-str nil)
	(translation '(("+N " . added)
		       ("-D " . removed)
		       (" M " . edited) ;; file text modified
		       ("  *" . edited) ;; execute bit changed
		       (" M*" . edited) ;; text modified + execute bit changed
		       ;; FIXME: what about ignored files?
		       (" D " . missing)
                       ;; For conflicts, should we list the .THIS/.BASE/.OTHER?
		       ("C  " . conflict)
		       ("?  " . unregistered)
		       ;; No such state, but we need to distinguish this case.
		       ("R  " . renamed)
		       ("RM " . renamed)
		       ;; For a non existent file FOO, the output is:
		       ;; bzr: ERROR: Path(s) do not exist: FOO
		       ("bzr" . not-found)
		       ;; If the tree is not up to date, bzr will print this warning:
		       ;; working tree is out of date, run 'bzr update'
		       ;; ignore it.
		       ;; FIXME: maybe this warning can be put in the vc-dir header...
		       ("wor" . not-found)
                       ;; Ignore "P " and "P." for pending patches.
		       ("P  " . not-found)
		       ("P. " . not-found)
                       ))
	(translated nil)
	(result nil))
      (goto-char (point-min))
      (while (not (eobp))
	(setq status-str
	      (buffer-substring-no-properties (point) (+ (point) 3)))
	(setq translated (cdr (assoc status-str translation)))
	(cond
	 ((eq translated 'conflict)
	  ;; For conflicts the file appears twice in the listing: once
	  ;; with the M flag and once with the C flag, so take care
	  ;; not to add it twice to `result'.  Ugly.
	  (let* ((file
		  (buffer-substring-no-properties
		   ;;For files with conflicts the format is:
		   ;;C   Text conflict in FILENAME
		   ;; Bah.
		   (+ (point) 21) (line-end-position)))
		 (entry (assoc file result)))
	    (when entry
	      (setf (nth 1 entry) 'conflict))))
	 ((eq translated 'renamed)
	  (re-search-forward "R[ M]  \\(.*\\) => \\(.*\\)$" (line-end-position) t)
	  (let ((new-name (file-relative-name (match-string 2) relative-dir))
		(old-name (file-relative-name (match-string 1) relative-dir)))
	    (push (list new-name 'edited
		      (vc-bzr-create-extra-fileinfo old-name)) result)))
	 ;; do nothing for non existent files
	 ((eq translated 'not-found))
	 (t
	  (push (list (file-relative-name
		       (buffer-substring-no-properties
			(+ (point) 4)
			(line-end-position)) relative-dir)
		      translated) result)))
	(forward-line))
      (funcall update-function result)))

(defun vc-bzr-dir-status (dir update-function)
  "Return a list of conses (file . state) for DIR."
  (vc-bzr-command "status" (current-buffer) 'async dir "-v" "-S")
  (vc-exec-after
   `(vc-bzr-after-dir-status (quote ,update-function)
			     ;; "bzr status" results are relative to
			     ;; the bzr root directory, NOT to the
			     ;; directory "bzr status" was invoked in.
			     ;; Ugh.
			     ;; We pass the relative directory here so
			     ;; that `vc-bzr-after-dir-status' can
			     ;; frob the results accordingly.
			     (file-relative-name ,dir (vc-bzr-root ,dir)))))

(defun vc-bzr-dir-status-files (dir files default-state update-function)
  "Return a list of conses (file . state) for DIR."
  (apply 'vc-bzr-command "status" (current-buffer) 'async dir "-v" "-S" files)
  (vc-exec-after
   `(vc-bzr-after-dir-status (quote ,update-function)
			     (file-relative-name ,dir (vc-bzr-root ,dir)))))

(defvar vc-bzr-shelve-map
  (let ((map (make-sparse-keymap)))
    ;; Turn off vc-dir marking
    (define-key map [mouse-2] 'ignore)

    (define-key map [down-mouse-3] 'vc-bzr-shelve-menu)
    (define-key map "\C-k" 'vc-bzr-shelve-delete-at-point)
    ;; (define-key map "=" 'vc-bzr-shelve-show-at-point)
    ;; (define-key map "\C-m" 'vc-bzr-shelve-show-at-point)
    (define-key map "P" 'vc-bzr-shelve-apply-at-point)
    map))

(defvar vc-bzr-shelve-menu-map
  (let ((map (make-sparse-keymap "Bzr Shelve")))
    (define-key map [de]
      '(menu-item "Delete shelf" vc-bzr-shelve-delete-at-point
		  :help "Delete the current shelf"))
    (define-key map [po]
      '(menu-item "Apply and remove shelf (pop)" vc-bzr-shelve-apply-at-point
		  :help "Apply the current shelf and remove it"))
    ;; (define-key map [sh]
    ;;   '(menu-item "Show shelve" vc-bzr-shelve-show-at-point
    ;; 		  :help "Show the contents of the current shelve"))
    map))

(defvar vc-bzr-extra-menu-map
  (let ((map (make-sparse-keymap)))
    (define-key map [bzr-sh]
      '(menu-item "Shelve..." vc-bzr-shelve
		  :help "Shelve changes"))
    map))

(defun vc-bzr-extra-menu () vc-bzr-extra-menu-map)

(defun vc-bzr-extra-status-menu () vc-bzr-extra-menu-map)

(defun vc-bzr-dir-extra-headers (dir)
  (let*
      ((str (with-temp-buffer
	      (vc-bzr-command "info" t 0 dir)
	      (buffer-string)))
       (shelve (vc-bzr-shelve-list))
       (shelve-help-echo "Use M-x vc-bzr-shelve to create shelves")
       (root-dir (vc-bzr-root dir))
       (pending-merge
	;; FIXME: looking for .bzr/checkout/merge-hashes is not a
	;; reliable method to detect pending merges, disable this
	;; until a proper solution is implemented.
	(and nil
	 (file-exists-p
	 (expand-file-name ".bzr/checkout/merge-hashes" root-dir))))
       (pending-merge-help-echo
	(format "A merge has been performed.\nA commit from the top-level directory (%s)\nis required before being able to check in anything else" root-dir))
       (light-checkout
	(when (string-match ".+light checkout root: \\(.+\\)$" str)
	  (match-string 1 str)))
       (light-checkout-branch
	(when light-checkout
	  (when (string-match ".+checkout of branch: \\(.+\\)$" str)
	    (match-string 1 str)))))
    (concat
     (propertize "Parent branch      : " 'face 'font-lock-type-face)
     (propertize
      (if (string-match "parent branch: \\(.+\\)$" str)
 	  (match-string 1 str)
 	"None")
       'face 'font-lock-variable-name-face)
     "\n"
      (when light-checkout
	(concat
	 (propertize "Light checkout root: " 'face 'font-lock-type-face)
	 (propertize light-checkout 'face 'font-lock-variable-name-face)
	 "\n"))
      (when light-checkout-branch
	(concat
	 (propertize "Checkout of branch : " 'face 'font-lock-type-face)
	 (propertize light-checkout-branch 'face 'font-lock-variable-name-face)
	 "\n"))
      (when pending-merge
	(concat
	 (propertize "Warning            : " 'face 'font-lock-warning-face
		     'help-echo pending-merge-help-echo)
	 (propertize "Pending merges, commit recommended before any other action"
		     'help-echo pending-merge-help-echo
		     'face 'font-lock-warning-face)
	 "\n"))
      (if shelve
	  (concat
	   (propertize "Shelves            :\n" 'face 'font-lock-type-face
		       'help-echo shelve-help-echo)
	   (mapconcat
	    (lambda (x)
	      (propertize x
			  'face 'font-lock-variable-name-face
			  'mouse-face 'highlight
			  'help-echo "mouse-3: Show shelve menu\nA: Apply and keep shelf\nP: Apply and remove shelf (pop)\nS: Snapshot to a shelf\nC-k: Delete shelf"
			  'keymap vc-bzr-shelve-map))
	    shelve "\n"))
	(concat
	 (propertize "Shelves            : " 'face 'font-lock-type-face
		     'help-echo shelve-help-echo)
	 (propertize "No shelved changes"
		     'help-echo shelve-help-echo
		     'face 'font-lock-variable-name-face))))))

(defun vc-bzr-shelve (name)
  "Create a shelve."
  (interactive "sShelf name: ")
  (let ((root (vc-bzr-root default-directory)))
    (when root
      (vc-bzr-command "shelve" nil 0 nil "--all" "-m" name)
      (vc-resynch-buffer root t t))))

;; (defun vc-bzr-shelve-show (name)
;;   "Show the contents of shelve NAME."
;;   (interactive "sShelve name: ")
;;   (vc-setup-buffer "*vc-bzr-shelve*")
;;   ;; FIXME: how can you show the contents of a shelf?
;;   (vc-bzr-command "shelve" "*vc-bzr-shelve*" 'async nil name)
;;   (set-buffer "*vc-bzr-shelve*")
;;   (diff-mode)
;;   (setq buffer-read-only t)
;;   (pop-to-buffer (current-buffer)))

(defun vc-bzr-shelve-apply (name)
  "Apply shelve NAME and remove it afterwards."
  (interactive "sApply (and remove) shelf: ")
  (vc-bzr-command "unshelve" "*vc-bzr-shelve*" 0 nil "--apply" name)
  (vc-resynch-buffer (vc-bzr-root default-directory) t t))

(defun vc-bzr-shelve-list ()
  (with-temp-buffer
    (vc-bzr-command "shelve" (current-buffer) 1 nil "--list" "-q")
    (delete
     ""
     (split-string
      (buffer-substring (point-min) (point-max))
      "\n"))))

(defun vc-bzr-shelve-get-at-point (point)
  (save-excursion
    (goto-char point)
    (beginning-of-line)
    (if (looking-at "^ +\\([0-9]+\\):")
	(match-string 1)
      (error "Cannot find shelf at point"))))

(defun vc-bzr-shelve-delete-at-point ()
  (interactive)
  (let ((shelve (vc-bzr-shelve-get-at-point (point))))
    (when (y-or-n-p (format "Remove shelf %s ?" shelve))
      (vc-bzr-command "unshelve" nil 0 nil "--delete-only" shelve)
      (vc-dir-refresh))))

;; (defun vc-bzr-shelve-show-at-point ()
;;   (interactive)
;;   (vc-bzr-shelve-show (vc-bzr-shelve-get-at-point (point))))

(defun vc-bzr-shelve-apply-at-point ()
  (interactive)
  (vc-bzr-shelve-apply (vc-bzr-shelve-get-at-point (point))))

(defun vc-bzr-shelve-menu (e)
  (interactive "e")
  (vc-dir-at-event e (popup-menu vc-bzr-shelve-menu-map e)))

(defun vc-bzr-revision-table (files)
  (let ((vc-bzr-revisions '())
        (default-directory (file-name-directory (car files))))
    (with-temp-buffer
      (vc-bzr-command "log" t 0 files "--line")
      (let ((start (point-min))
            (loglines (buffer-substring-no-properties (point-min) (point-max))))
        (while (string-match "^\\([0-9]+\\):" loglines)
          (push (match-string 1 loglines) vc-bzr-revisions)
          (setq start (+ start (match-end 0)))
          (setq loglines (buffer-substring-no-properties start (point-max))))))
    vc-bzr-revisions))

;;; Revision completion

(eval-and-compile
  (defconst vc-bzr-revision-keywords
    '("revno" "revid" "last" "before"
      "tag" "date" "ancestor" "branch" "submit")))

(defun vc-bzr-revision-completion-table (files)
  (lexical-let ((files files))
    ;; What about using `files'?!?  --Stef
    (lambda (string pred action)
      (cond
       ((string-match "\\`\\(ancestor\\|branch\\|\\(revno:\\)?[-0-9]+:\\):"
                      string)
        (completion-table-with-context (substring string 0 (match-end 0))
                                       'completion-file-name-table
                                       (substring string (match-end 0))
                                       ;; Dropping `pred' for no good reason.
                                       'file-directory-p
                                       action))
       ((string-match "\\`\\(before\\):" string)
        (completion-table-with-context (substring string 0 (match-end 0))
                                       (vc-bzr-revision-completion-table files)
                                       (substring string (match-end 0))
                                       pred
                                       action))
       ((string-match "\\`\\(tag\\):" string)
        (let ((prefix (substring string 0 (match-end 0)))
              (tag (substring string (match-end 0)))
              (table nil)
	      process-file-side-effects)
          (with-temp-buffer
            ;; "bzr-1.2 tags" is much faster with --show-ids.
            (process-file vc-bzr-program nil '(t) nil "tags" "--show-ids")
            ;; The output is ambiguous, unless we assume that revids do not
            ;; contain spaces.
            (goto-char (point-min))
            (while (re-search-forward "^\\(.*[^ \n]\\) +[^ \n]*$" nil t)
              (push (match-string-no-properties 1) table)))
          (completion-table-with-context prefix table tag pred action)))

       ((string-match "\\`\\([a-z]+\\):" string)
        ;; no actual completion for the remaining keywords.
        (completion-table-with-context (substring string 0 (match-end 0))
                                       (if (member (match-string 1 string)
                                                   vc-bzr-revision-keywords)
                                           ;; If it's a valid keyword,
                                           ;; use a non-empty table to
                                           ;; indicate it.
                                           '("") nil)
                                       (substring string (match-end 0))
                                       pred
                                       action))
       (t
        ;; Could use completion-table-with-terminator, except that it
        ;; currently doesn't work right w.r.t pcm and doesn't give
        ;; the *Completions* output we want.
        (complete-with-action action (eval-when-compile
                                       (mapcar (lambda (s) (concat s ":"))
                                               vc-bzr-revision-keywords))
                              string pred))))))

(eval-after-load "vc"
  '(add-to-list 'vc-directory-exclusion-list vc-bzr-admin-dirname t))

(provide 'vc-bzr)
;; arch-tag: 8101bad8-4e92-4e7d-85ae-d8e08b4e7c06
;;; vc-bzr.el ends here
