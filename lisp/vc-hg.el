;;; vc-hg.el --- VC backend for the mercurial version control system

;; Copyright (C) 2006, 2007, 2008, 2009, 2010 Free Software Foundation, Inc.

;; Author: Ivan Kanis
;; Keywords: tools

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

;; This is a mercurial version control backend

;;; Thanks:

;;; Bugs:

;;; Installation:

;;; Todo:

;; 1) Implement the rest of the vc interface. See the comment at the
;; beginning of vc.el. The current status is:

;; FUNCTION NAME                               STATUS
;; BACKEND PROPERTIES
;; * revision-granularity                      OK
;; STATE-QUERYING FUNCTIONS
;; * registered (file)                         OK
;; * state (file)                              OK
;; - state-heuristic (file)                    NOT NEEDED
;; - dir-status (dir update-function)          OK
;; - dir-status-files (dir files ds uf)        OK
;; - dir-extra-headers (dir)                   OK
;; - dir-printer (fileinfo)                    OK
;; * working-revision (file)                   OK
;; - latest-on-branch-p (file)                 ??
;; * checkout-model (files)                    OK
;; - workfile-unchanged-p (file)               OK
;; - mode-line-string (file)                   NOT NEEDED
;; STATE-CHANGING FUNCTIONS
;; * register (files &optional rev comment)    OK
;; * create-repo ()                            OK
;; - init-revision ()                          NOT NEEDED
;; - responsible-p (file)                      OK
;; - could-register (file)                     OK
;; - receive-file (file rev)                   ?? PROBABLY NOT NEEDED
;; - unregister (file)                         COMMENTED OUT, MAY BE INCORRECT
;; * checkin (files rev comment)               OK
;; * find-revision (file rev buffer)           OK
;; * checkout (file &optional editable rev)    OK
;; * revert (file &optional contents-done)     OK
;; - rollback (files)                          ?? PROBABLY NOT NEEDED
;; - merge (file rev1 rev2)                    NEEDED
;; - merge-news (file)                         NEEDED
;; - steal-lock (file &optional revision)      NOT NEEDED
;; HISTORY FUNCTIONS
;; * print-log (files buffer &optional shortlog start-revision limit) OK
;; - log-view-mode ()                          OK
;; - show-log-entry (revision)                 NOT NEEDED, DEFAULT IS GOOD
;; - comment-history (file)                    NOT NEEDED
;; - update-changelog (files)                  NOT NEEDED
;; * diff (files &optional rev1 rev2 buffer)   OK
;; - revision-completion-table (files)         OK?
;; - annotate-command (file buf &optional rev) OK
;; - annotate-time ()                          OK
;; - annotate-current-time ()                  NOT NEEDED
;; - annotate-extract-revision-at-line ()      OK
;; TAG SYSTEM
;; - create-tag (dir name branchp)             NEEDED
;; - retrieve-tag (dir name update)            NEEDED
;; MISCELLANEOUS
;; - make-version-backups-p (file)             ??
;; - repository-hostname (dirname)             ??
;; - previous-revision (file rev)              OK
;; - next-revision (file rev)                  OK
;; - check-headers ()                          ??
;; - clear-headers ()                          ??
;; - delete-file (file)                        TEST IT
;; - rename-file (old new)                     OK
;; - find-file-hook ()                         PROBABLY NOT NEEDED

;; 2) Implement Stefan Monnier's advice:
;; vc-hg-registered and vc-hg-state
;; Both of those functions should be super extra careful to fail gracefully in
;; unexpected circumstances. The reason this is important is that any error
;; there will prevent the user from even looking at the file :-(
;; Ideally, just like in vc-arch and vc-cvs, checking that the file is under
;; mercurial's control and extracting the current revision should be done
;; without even using `hg' (this way even if you don't have `hg' installed,
;; Emacs is able to tell you this file is under mercurial's control).

;;; History:
;;

;;; Code:

(eval-when-compile
  (require 'cl)
  (require 'vc)
  (require 'vc-dir))

;;; Customization options

(defcustom vc-hg-global-switches nil
  "Global switches to pass to any Hg command."
  :type '(choice (const :tag "None" nil)
         (string :tag "Argument String")
         (repeat :tag "Argument List" :value ("") string))
  :version "22.2"
  :group 'vc)

(defcustom vc-hg-diff-switches t ; Hg doesn't support common args like -u
  "String or list of strings specifying switches for Hg diff under VC.
If nil, use the value of `vc-diff-switches'.  If t, use no switches."
  :type '(choice (const :tag "Unspecified" nil)
                 (const :tag "None" t)
                 (string :tag "Argument String")
                 (repeat :tag "Argument List" :value ("") string))
  :version "23.1"
  :group 'vc)


;;; Properties of the backend

(defun vc-hg-revision-granularity () 'repository)
(defun vc-hg-checkout-model (files) 'implicit)

;;; State querying functions

;;;###autoload (defun vc-hg-registered (file)
;;;###autoload   "Return non-nil if FILE is registered with hg."
;;;###autoload   (if (vc-find-root file ".hg")       ; short cut
;;;###autoload       (progn
;;;###autoload         (load "vc-hg")
;;;###autoload         (vc-hg-registered file))))

;; Modeled after the similar function in vc-bzr.el
(defun vc-hg-registered (file)
  "Return non-nil if FILE is registered with hg."
  (when (vc-hg-root file)           ; short cut
    (let ((state (vc-hg-state file)))  ; expensive
      (and state (not (memq state '(ignored unregistered)))))))

(defun vc-hg-state (file)
  "Hg-specific version of `vc-state'."
  (let*
      ((status nil)
       (default-directory (file-name-directory file))
       (out
        (with-output-to-string
          (with-current-buffer
              standard-output
            (setq status
                  (condition-case nil
                      ;; Ignore all errors.
		      (let ((process-environment
			     ;; Avoid localization of messages so we
			     ;; can parse the output.
			     (append (list "TERM=dumb" "LANGUAGE=C" "HGRCPATH=")
				     process-environment)))
			(process-file
			 "hg" nil t nil
			 "status" "-A" (file-relative-name file)))
                    ;; Some problem happened.  E.g. We can't find an `hg'
                    ;; executable.
                    (error nil)))))))
    (when (eq 0 status)
        (when (null (string-match ".*: No such file or directory$" out))
          (let ((state (aref out 0)))
            (cond
             ((eq state ?=) 'up-to-date)
             ((eq state ?A) 'added)
             ((eq state ?M) 'edited)
             ((eq state ?I) 'ignored)
             ((eq state ?R) 'removed)
             ((eq state ?!) 'missing)
             ((eq state ??) 'unregistered)
             ((eq state ?C) 'up-to-date) ;; Older mercurials use this
             (t 'up-to-date)))))))

(defun vc-hg-working-revision (file)
  "Hg-specific version of `vc-working-revision'."
  (let*
      ((status nil)
       (default-directory (file-name-directory file))
       ;; Avoid localization of messages so we can parse the output.
       (avoid-local-env (append (list "TERM=dumb" "LANGUAGE=C" "HGRCPATH=")
				     process-environment))
       (out
        (with-output-to-string
          (with-current-buffer
              standard-output
            (setq status
                  (condition-case nil
		      (let ((process-environment avoid-local-env))
			;; Ignore all errors.
			(process-file
			 "hg" nil t nil
			 "parents" "--template" "{rev}" (file-relative-name file)))
                    ;; Some problem happened.  E.g. We can't find an `hg'
                    ;; executable.
                    (error nil)))))))
    (if (eq 0 status)
	out
      ;; Check if the file is in the 'added state, the above hg
      ;; command does not distinguish between 'added and 'unregistered.
      (setq status
	    (condition-case nil
		(let ((process-environment avoid-local-env))
		  (process-file
		   "hg" nil nil nil
		   ;; We use "log" here, if there's a faster command
		   ;; that returns true for an 'added file and false
		   ;; for an 'unregistered one, we could use that.
		   "log" "-l1" (file-relative-name file)))
	      ;; Some problem happened.  E.g. We can't find an `hg'
	      ;; executable.
	      (error nil)))
      (when (eq 0 status) "0"))))

;;; History functions

(defcustom vc-hg-log-switches nil
  "String or list of strings specifying switches for hg log under VC."
  :type '(choice (const :tag "None" nil)
                 (string :tag "Argument String")
                 (repeat :tag "Argument List" :value ("") string))
  :group 'vc-hg)

(defun vc-hg-print-log (files buffer &optional shortlog start-revision limit)
  "Get change log associated with FILES."
  ;; `vc-do-command' creates the buffer, but we need it before running
  ;; the command.
  (vc-setup-buffer buffer)
  ;; If the buffer exists from a previous invocation it might be
  ;; read-only.
  (let ((inhibit-read-only t))
    (with-current-buffer
	buffer
      (apply 'vc-hg-command buffer 0 files "log"
	     (append
	      (when start-revision (list (format "-r%s:" start-revision)))
	      (when limit (list "-l" (format "%s" limit)))
	      (when shortlog '("--style" "compact"))
	      vc-hg-log-switches)))))

(defvar log-view-message-re)
(defvar log-view-file-re)
(defvar log-view-font-lock-keywords)
(defvar log-view-per-file-logs)
(defvar vc-short-log)

(define-derived-mode vc-hg-log-view-mode log-view-mode "Hg-Log-View"
  (require 'add-log) ;; we need the add-log faces
  (set (make-local-variable 'log-view-file-re) "\\`a\\`")
  (set (make-local-variable 'log-view-per-file-logs) nil)
  (set (make-local-variable 'log-view-message-re)
       (if vc-short-log
           "^\\([0-9]+\\)\\(?:\\[.*\\]\\)? +\\([0-9a-z]\\{12\\}\\) +\\(\\(?:[0-9]+\\)-\\(?:[0-9]+\\)-\\(?:[0-9]+\\) \\(?:[0-9]+\\):\\(?:[0-9]+\\) \\(?:[-+0-9]+\\)\\) +\\(.*\\)$"
         "^changeset:[ \t]*\\([0-9]+\\):\\(.+\\)"))
  (set (make-local-variable 'log-view-font-lock-keywords)
       (if vc-short-log
           (append `((,log-view-message-re
                      (1 'log-view-message-face)
                      (2 'log-view-message-face)
                      (3 'change-log-date)
                      (4 'change-log-name))))
       (append
        log-view-font-lock-keywords
        '(
          ;; Handle the case:
          ;; user: FirstName LastName <foo@bar>
          ("^user:[ \t]+\\([^<(]+?\\)[ \t]*[(<]\\([A-Za-z0-9_.+-]+@[A-Za-z0-9_.-]+\\)[>)]"
           (1 'change-log-name)
           (2 'change-log-email))
          ;; Handle the cases:
          ;; user: foo@bar
          ;; and
          ;; user: foo
          ("^user:[ \t]+\\([A-Za-z0-9_.+-]+\\(?:@[A-Za-z0-9_.-]+\\)?\\)"
           (1 'change-log-email))
          ("^date: \\(.+\\)" (1 'change-log-date))
            ("^summary:[ \t]+\\(.+\\)" (1 'log-view-message)))))))

(defun vc-hg-diff (files &optional oldvers newvers buffer)
  "Get a difference report using hg between two revisions of FILES."
  (let* ((firstfile (car files))
         (working (and firstfile (vc-working-revision firstfile))))
    (when (and (equal oldvers working) (not newvers))
      (setq oldvers nil))
    (when (and (not oldvers) newvers)
      (setq oldvers working))
    (apply #'vc-hg-command (or buffer "*vc-diff*") nil files "diff"
           (append
            (vc-switches 'hg 'diff)
            (when oldvers
              (if newvers
                  (list "-r" oldvers "-r" newvers)
                (list "-r" oldvers)))))))

(defun vc-hg-revision-table (files)
  (let ((default-directory (file-name-directory (car files))))
    (with-temp-buffer
      (vc-hg-command t nil files "log" "--template" "{rev} ")
      (split-string
       (buffer-substring-no-properties (point-min) (point-max))))))

;; Modeled after the similar function in vc-cvs.el
(defun vc-hg-revision-completion-table (files)
  (lexical-let ((files files)
                table)
    (setq table (lazy-completion-table
                 table (lambda () (vc-hg-revision-table files))))
    table))

(defun vc-hg-annotate-command (file buffer &optional revision)
  "Execute \"hg annotate\" on FILE, inserting the contents in BUFFER.
Optional arg REVISION is a revision to annotate from."
  (vc-hg-command buffer 0 file "annotate" "-d" "-n" "--follow"
                 (when revision (concat "-r" revision))))

(declare-function vc-annotate-convert-time "vc-annotate" (time))

;; The format for one line output by "hg annotate -d -n" looks like this:
;;215 Wed Jun 20 21:22:58 2007 -0700: CONTENTS
;; i.e: VERSION_NUMBER DATE: CONTENTS
;; If the user has set the "--follow" option, the output looks like:
;;215 Wed Jun 20 21:22:58 2007 -0700 foo.c: CONTENTS
;; i.e. VERSION_NUMBER DATE FILENAME: CONTENTS
(defconst vc-hg-annotate-re
  "^[ \t]*\\([0-9]+\\) \\(.\\{30\\}\\)\\(?:\\(: \\)\\|\\(?: +\\(.+\\): \\)\\)")

(defun vc-hg-annotate-time ()
  (when (looking-at vc-hg-annotate-re)
    (goto-char (match-end 0))
    (vc-annotate-convert-time
     (date-to-time (match-string-no-properties 2)))))

(defun vc-hg-annotate-extract-revision-at-line ()
  (save-excursion
    (beginning-of-line)
    (when (looking-at vc-hg-annotate-re)
      (if (match-beginning 3)
	  (match-string-no-properties 1)
	(cons (match-string-no-properties 1)
	      (expand-file-name (match-string-no-properties 4)
				(vc-hg-root default-directory)))))))

(defun vc-hg-previous-revision (file rev)
  (let ((newrev (1- (string-to-number rev))))
    (when (>= newrev 0)
      (number-to-string newrev))))

(defun vc-hg-next-revision (file rev)
  (let ((newrev (1+ (string-to-number rev)))
        (tip-revision
         (with-temp-buffer
           (vc-hg-command t 0 nil "tip")
           (goto-char (point-min))
           (re-search-forward "^changeset:[ \t]*\\([0-9]+\\):")
           (string-to-number (match-string-no-properties 1)))))
    ;; We don't want to exceed the maximum possible revision number, ie
    ;; the tip revision.
    (when (<= newrev tip-revision)
      (number-to-string newrev))))

;; Modeled after the similar function in vc-bzr.el
(defun vc-hg-delete-file (file)
  "Delete FILE and delete it in the hg repository."
  (condition-case ()
      (delete-file file)
    (file-error nil))
  (vc-hg-command nil 0 file "remove" "--after" "--force"))

;; Modeled after the similar function in vc-bzr.el
(defun vc-hg-rename-file (old new)
  "Rename file from OLD to NEW using `hg mv'."
  (vc-hg-command nil 0 new "mv" old))

(defun vc-hg-register (files &optional rev comment)
  "Register FILES under hg.
REV is ignored.
COMMENT is ignored."
  (vc-hg-command nil 0 files "add"))

(defun vc-hg-create-repo ()
  "Create a new Mercurial repository."
  (vc-hg-command nil 0 nil "init"))

(defalias 'vc-hg-responsible-p 'vc-hg-root)

;; Modeled after the similar function in vc-bzr.el
(defun vc-hg-could-register (file)
  "Return non-nil if FILE could be registered under hg."
  (and (vc-hg-responsible-p file)      ; shortcut
       (condition-case ()
           (with-temp-buffer
             (vc-hg-command t nil file "add" "--dry-run"))
             ;; The command succeeds with no output if file is
             ;; registered.
         (error))))

;; FIXME: This would remove the file. Is that correct?
;; (defun vc-hg-unregister (file)
;;   "Unregister FILE from hg."
;;   (vc-hg-command nil nil file "remove"))

(defun vc-hg-checkin (files rev comment)
  "Hg-specific version of `vc-backend-checkin'.
REV is ignored."
  (vc-hg-command nil 0 files  "commit" "-m" comment))

(defun vc-hg-find-revision (file rev buffer)
  (let ((coding-system-for-read 'binary)
        (coding-system-for-write 'binary))
    (if rev
        (vc-hg-command buffer 0 file "cat" "-r" rev)
      (vc-hg-command buffer 0 file "cat"))))

;; Modeled after the similar function in vc-bzr.el
(defun vc-hg-checkout (file &optional editable rev)
  "Retrieve a revision of FILE.
EDITABLE is ignored.
REV is the revision to check out into WORKFILE."
  (let ((coding-system-for-read 'binary)
        (coding-system-for-write 'binary))
  (with-current-buffer (or (get-file-buffer file) (current-buffer))
    (if rev
        (vc-hg-command t 0 file "cat" "-r" rev)
      (vc-hg-command t 0 file "cat")))))

;; Modeled after the similar function in vc-bzr.el
(defun vc-hg-workfile-unchanged-p (file)
  (eq 'up-to-date (vc-hg-state file)))

;; Modeled after the similar function in vc-bzr.el
(defun vc-hg-revert (file &optional contents-done)
  (unless contents-done
    (with-temp-buffer (vc-hg-command t 0 file "revert"))))

;;; Hg specific functionality.

(defvar vc-hg-extra-menu-map
  (let ((map (make-sparse-keymap)))
    (define-key map [incoming] '(menu-item "Show incoming" vc-hg-incoming))
    (define-key map [outgoing] '(menu-item "Show outgoing" vc-hg-outgoing))
    map))

(defun vc-hg-extra-menu () vc-hg-extra-menu-map)

(defun vc-hg-extra-status-menu () vc-hg-extra-menu-map)

(defvar log-view-vc-backend)

(define-derived-mode vc-hg-outgoing-mode vc-hg-log-view-mode "Hg-Outgoing"
  "Mode for browsing Hg outgoing changes."
  (set (make-local-variable 'log-view-vc-backend) 'Hg))

(define-derived-mode vc-hg-incoming-mode vc-hg-log-view-mode "Hg-Incoming"
  "Mode for browsing Hg incoming changes."
  (set (make-local-variable 'log-view-vc-backend) 'Hg))

(defstruct (vc-hg-extra-fileinfo
            (:copier nil)
            (:constructor vc-hg-create-extra-fileinfo (rename-state extra-name))
            (:conc-name vc-hg-extra-fileinfo->))
  rename-state        ;; rename or copy state
  extra-name)         ;; original name for copies and rename targets, new name for

(declare-function vc-default-dir-printer "vc-dir" (backend fileentry))

(defun vc-hg-dir-printer (info)
  "Pretty-printer for the vc-dir-fileinfo structure."
  (let ((extra (vc-dir-fileinfo->extra info)))
    (vc-default-dir-printer 'Hg info)
    (when extra
      (insert (propertize
               (format "   (%s %s)"
                       (case (vc-hg-extra-fileinfo->rename-state extra)
                         ('copied "copied from")
                         ('renamed-from "renamed from")
                         ('renamed-to "renamed to"))
                       (vc-hg-extra-fileinfo->extra-name extra))
               'face 'font-lock-comment-face)))))

(defun vc-hg-after-dir-status (update-function)
  (let ((status-char nil)
        (file nil)
        (translation '((?= . up-to-date)
                       (?C . up-to-date)
                       (?A . added)
                       (?R . removed)
                       (?M . edited)
                       (?I . ignored)
                       (?! . missing)
                       (?  . copy-rename-line)
                       (?? . unregistered)))
        (translated nil)
        (result nil)
        (last-added nil)
        (last-line-copy nil))
      (goto-char (point-min))
      (while (not (eobp))
        (setq translated (cdr (assoc (char-after) translation)))
        (setq file
              (buffer-substring-no-properties (+ (point) 2)
                                              (line-end-position)))
        (cond ((not translated)
               (setq last-line-copy nil))
              ((eq translated 'up-to-date)
               (setq last-line-copy nil))
              ((eq translated 'copy-rename-line)
               ;; For copied files the output looks like this:
               ;; A COPIED_FILE_NAME
               ;;   ORIGINAL_FILE_NAME
               (setf (nth 2 last-added)
                     (vc-hg-create-extra-fileinfo 'copied file))
               (setq last-line-copy t))
              ((and last-line-copy (eq translated 'removed))
               ;; For renamed files the output looks like this:
               ;; A NEW_FILE_NAME
               ;;   ORIGINAL_FILE_NAME
               ;; R ORIGINAL_FILE_NAME
               ;; We need to adjust the previous entry to not think it is a copy.
               (setf (vc-hg-extra-fileinfo->rename-state (nth 2 last-added))
                     'renamed-from)
               (push (list file translated
                           (vc-hg-create-extra-fileinfo
                            'renamed-to (nth 0 last-added))) result)
               (setq last-line-copy nil))
              (t
               (setq last-added (list file translated nil))
               (push last-added result)
               (setq last-line-copy nil)))
        (forward-line))
      (funcall update-function result)))

(defun vc-hg-dir-status (dir update-function)
  (vc-hg-command (current-buffer) 'async dir "status" "-C")
  (vc-exec-after
   `(vc-hg-after-dir-status (quote ,update-function))))

(defun vc-hg-dir-status-files (dir files default-state update-function)
  (apply 'vc-hg-command (current-buffer) 'async dir "status" "-C" files)
  (vc-exec-after
   `(vc-hg-after-dir-status (quote ,update-function))))

(defun vc-hg-dir-extra-header (name &rest commands)
  (concat (propertize name 'face 'font-lock-type-face)
          (propertize
           (with-temp-buffer
             (apply 'vc-hg-command (current-buffer) 0 nil commands)
             (buffer-substring-no-properties (point-min) (1- (point-max))))
           'face 'font-lock-variable-name-face)))

(defun vc-hg-dir-extra-headers (dir)
  "Generate extra status headers for a Mercurial tree."
  (let ((default-directory dir))
    (concat
     (vc-hg-dir-extra-header "Root       : " "root") "\n"
     (vc-hg-dir-extra-header "Branch     : " "id" "-b") "\n"
     (vc-hg-dir-extra-header "Tags       : " "id" "-t") ; "\n"
     ;; these change after each commit
     ;; (vc-hg-dir-extra-header "Local num  : " "id" "-n") "\n"
     ;; (vc-hg-dir-extra-header "Global id  : " "id" "-i")
     )))

;; FIXME: this adds another top level menu, instead figure out how to
;; replace the Log-View menu.
(easy-menu-define log-view-mode-menu vc-hg-outgoing-mode-map
  "Hg-outgoing Display Menu"
  `("Hg-outgoing"
    ["Push selected"  vc-hg-push]))

(easy-menu-define log-view-mode-menu vc-hg-incoming-mode-map
  "Hg-incoming Display Menu"
  `("Hg-incoming"
    ["Pull selected"  vc-hg-pull]))

(defun vc-hg-outgoing ()
  (interactive)
  (let ((bname "*Hg outgoing*")
	(vc-short-log nil))
    (vc-hg-command bname 1 nil "outgoing" "-n")
    (pop-to-buffer bname)
    (vc-hg-outgoing-mode)))

(defun vc-hg-incoming ()
  (interactive)
  (let ((bname "*Hg incoming*")
	(vc-short-log nil))
    (vc-hg-command bname 0 nil "incoming" "-n")
    (pop-to-buffer bname)
    (vc-hg-incoming-mode)))

(declare-function log-view-get-marked "log-view" ())

;; XXX maybe also add key bindings for these functions.
(defun vc-hg-push ()
  (interactive)
  (let ((marked-list (log-view-get-marked)))
    (if marked-list
        (vc-hg-command
         nil 0 nil
         (cons "push"
               (apply 'nconc
                      (mapcar (lambda (arg) (list "-r" arg)) marked-list))))
         (error "No log entries selected for push"))))

(defun vc-hg-pull ()
  (interactive)
  (let ((marked-list (log-view-get-marked)))
    (if marked-list
        (vc-hg-command
         nil 0 nil
         (cons "pull"
               (apply 'nconc
                      (mapcar (lambda (arg) (list "-r" arg)) marked-list))))
      (error "No log entries selected for pull"))))

;;; Internal functions

(defun vc-hg-command (buffer okstatus file-or-list &rest flags)
  "A wrapper around `vc-do-command' for use in vc-hg.el.
The difference to vc-do-command is that this function always invokes `hg',
and that it passes `vc-hg-global-switches' to it before FLAGS."
  (apply 'vc-do-command (or buffer "*vc*") okstatus "hg" file-or-list
         (if (stringp vc-hg-global-switches)
             (cons vc-hg-global-switches flags)
           (append vc-hg-global-switches
                   flags))))

(defun vc-hg-root (file)
  (vc-find-root file ".hg"))

(provide 'vc-hg)

;; arch-tag: bd094dc5-715a-434f-a331-37b9fb7cd954
;;; vc-hg.el ends here
