;;; srecode/filters.el --- Filters for use in template variables.

;; Copyright (C) 2007, 2008, 2009, 2010 Free Software Foundation, Inc.

;; Author: Eric M. Ludlam <eric@siege-engine.com>

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
;; Various useful srecoder template functions.

;;; Code:

(require 'newcomment)
(require 'srecode/table)
(require 'srecode/insert)

(defun srecode-comment-prefix (str)
  "Prefix each line of STR with the comment prefix characters."
  (let* ((dict srecode-inserter-variable-current-dictionary)
	 ;; Derive the comment characters to put in front of each line.
	 (cs (or (and dict
		      (srecode-dictionary-lookup-name dict "comment_prefix"))
		 (and comment-multi-line comment-continue)
		 (and (not comment-multi-line) comment-start)))
	 (strs (split-string str "\n"))
	 (newstr "")
	 )
    (while strs
      (cond ((and (not comment-multi-line) (string= (car strs) ""))
	     ; (setq newstr (concat newstr "\n")))
	     )
	    (t
	     (setq newstr (concat newstr cs " " (car strs)))))
      (setq strs (cdr strs))
      (when strs (setq newstr (concat newstr "\n"))))
    newstr))

(provide 'srecode/filters)

;;; srecode/filters.el ends here

;; arch-tag: fcc95ddc-8d9a-4b15-bb51-2707ead986c7
