/* Machine description file for ARM-based non-RISCiX machines.
   Copyright (C) 1994, 2001, 2002, 2003, 2004, 2005, 2006, 2007,
                 2008, 2009, 2010  Free Software Foundation, Inc.

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



/* Define WORDS_BIG_ENDIAN if lowest-numbered byte in a word
   is the most significant byte.  */

#undef WORDS_BIG_ENDIAN

/* Define NO_ARG_ARRAY if you cannot take the address of the first of a
 * group of arguments and treat it as an array of the arguments.  We can't
 * do this on the arm with gcc, since the first 4 args are in registers.  */

#ifdef __GNUC__
#define NO_ARG_ARRAY
#else
#undef NO_ARG_ARRAY
#endif

#define NO_REMAP

/* armin76@gentoo.org reported that the lgcc_s flag is necessary to
   build on ARM EABI under GNU/Linux (Bug#5518).  */
#ifdef GNU_LINUX
#define LIB_GCC -lgcc_s
#endif

/* arch-tag: 07856f0c-f0c8-4bd8-99af-0b7fa1e5ee42
   (do not change this comment) */
