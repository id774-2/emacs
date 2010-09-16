/* Hey Emacs, this is -*- C -*- code!  */
/* Copyright (C) 1993, 1995, 1997, 1999, 2001, 2002, 2003, 2004,
                 2005, 2006, 2007, 2008, 2009, 2010 Free Software Foundation, Inc.

This file is part of GNU Emacs.

GNU Emacs is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

GNU Emacs is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.  */


/* The default search path for Lisp function "load".
   This sets load-path.  */
#define PATH_LOADSEARCH "/opt/emacs/23.2/share/emacs/23.2/site-lisp:/opt/emacs/23.2/share/emacs/site-lisp:/opt/emacs/23.2/share/emacs/23.2/lisp:/opt/emacs/23.2/share/emacs/23.2/leim"

/* Like PATH_LOADSEARCH, but used only when Emacs is dumping.  This
   path is usually identical to PATH_LOADSEARCH except that the entry
   for the directory containing the installed lisp files has been
   replaced with ../lisp.  */
#define PATH_DUMPLOADSEARCH "/home/debian/local/github/emacs/lisp"

/* The extra search path for programs to invoke.  This is appended to
   whatever the PATH environment variable says to set the Lisp
   variable exec-path and the first file name in it sets the Lisp
   variable exec-directory.  exec-directory is used for finding
   executables and other architecture-dependent files.  */
#define PATH_EXEC "/opt/emacs/23.2/libexec/emacs/23.2/i686-pc-linux-gnu"

/* Where Emacs should look for its architecture-independent data
   files, like the NEWS file.  The lisp variable data-directory
   is set to this value.  */
#define PATH_DATA "/opt/emacs/23.2/share/emacs/23.2/etc"

/* Where Emacs should look for X bitmap files.
   The lisp variable x-bitmap-file-path is set based on this value.  */
#define PATH_BITMAPS ""

/* Where Emacs should look for its docstring file.  The lisp variable
   doc-directory is set to this value.  */
#define PATH_DOC "/opt/emacs/23.2/share/emacs/23.2/etc"

/* Where the configuration process believes the info tree lives.  The
   lisp variable configure-info-directory gets its value from this
   macro, and is then used to set the Info-default-directory-list.  */
#define PATH_INFO "/opt/emacs/23.2/share/info"

/* Where Emacs should store game score files.  */
#define PATH_GAME "/opt/emacs/23.2/var/games/emacs"

/* Where Emacs should look for the application default file. */
#define PATH_X_DEFAULTS ""

/*
   (do not change this comment) */
