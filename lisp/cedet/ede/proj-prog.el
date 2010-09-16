;;; ede-proj-prog.el --- EDE Generic Project program support

;; Copyright (C) 1998, 1999, 2000, 2001, 2005, 2008, 2009, 2010
;;   Free Software Foundation, Inc.

;; Author: Eric M. Ludlam <zappo@gnu.org>
;; Keywords: project, make

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
;;
;; Handle building programs from object files in and EDE Project file.

(eval-when-compile (require 'cl))
(require 'ede/pmake)
(require 'ede/proj-obj)

(declare-function ede-shell-run-something "ede/shell")

;;; Code:
(defclass ede-proj-target-makefile-program
  (ede-proj-target-makefile-objectcode)
  ((ldlibs :initarg :ldlibs
	   :initform nil
	   :type list
	   :custom (repeat (string :tag "Library"))
	   :documentation
	   "Libraries, such as \"m\" or \"Xt\" which this program depends on.
The linker flag \"-l\" is automatically prepended.  Do not include a \"lib\"
prefix, or a \".so\" suffix.

Note: Currently only used for Automake projects."
	   )
   (ldflags :initarg :ldflags
	    :initform nil
	    :type list
	    :custom (repeat (string :tag "Link Flag"))
	    :documentation
	    "Additional flags to add when linking this target.
Use ldlibs to add addition libraries.  Use this to specify specific
options to the linker.

Note: Not currently used.  This bug needs to be fixed.")
   )
   "This target is an executable program.")

(defmethod ede-proj-makefile-insert-automake-pre-variables
  ((this ede-proj-target-makefile-program))
  "Insert bin_PROGRAMS variables needed by target THIS."
  (ede-pmake-insert-variable-shared "bin_PROGRAMS"
    (insert (ede-name this)))
  (call-next-method))

(defmethod ede-proj-makefile-insert-automake-post-variables
  ((this ede-proj-target-makefile-program))
  "Insert bin_PROGRAMS variables needed by target THIS."
  (ede-pmake-insert-variable-shared
      (concat (ede-name this) "_LDADD")
    (mapc (lambda (c) (insert " -l" c)) (oref this ldlibs)))
  ;; For other targets THIS depends on
  ;;
  ;; NOTE: FIX THIS
  ;;
  ;;(ede-pmake-insert-variable-shared
  ;;    (concat (ede-name this) "_DEPENDENCIES")
  ;;  (mapcar (lambda (d) (insert d)) (oref this FOOOOOOOO)))
  (call-next-method))

(defmethod ede-proj-makefile-insert-rules ((this ede-proj-target-makefile-program))
  "Insert rules needed by THIS target."
  (let ((ede-proj-compiler-object-linkflags
	 (mapconcat 'identity (oref this ldflags) " ")))
    (with-slots (ldlibs) this
      (if ldlibs
	  (setq ede-proj-compiler-object-linkflags
		(concat ede-proj-compiler-object-linkflags
			" -l"
			(mapconcat 'identity ldlibs " -l")))))
    (call-next-method)))

(defmethod project-debug-target ((obj ede-proj-target-makefile-program))
  "Debug a program target OBJ."
  (let ((tb (get-buffer-create " *padt*"))
	(dd (if (not (string= (oref obj path) ""))
		(oref obj path)
	      default-directory))
	(cmd nil))
    (unwind-protect
	(progn
	  (set-buffer tb)
	  (setq default-directory dd)
	  (setq cmd (read-from-minibuffer
		     "Run (like this): "
		     (concat (symbol-name ede-debug-program-function)
			     " " (ede-target-name obj))))
	  (funcall ede-debug-program-function cmd))
      (kill-buffer tb))))

(defmethod project-run-target ((obj ede-proj-target-makefile-program) &optional command)
  "Run a program target OBJ.
Optional COMMAND is the command to run in place of asking the user."
  (require 'ede/shell)
  (let ((tb (get-buffer-create " *padt*"))
	(dd (if (not (string= (oref obj path) ""))
		(oref obj path)
	      default-directory))
	(cmd nil))
    (unwind-protect
	(progn
	  (set-buffer tb)
	  (setq default-directory dd)
	  (setq cmd (or command
			(read-from-minibuffer
			 "Run (like this): "
			 (concat "./" (ede-target-name obj)))))
	  (ede-shell-run-something obj cmd)
	  )
      (kill-buffer tb))))

(provide 'ede/proj-prog)

;; arch-tag: 0bfa9364-f385-4745-a846-462146a79a25
;;; ede/proj-prog.el ends here
