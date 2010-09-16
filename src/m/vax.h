/* machine description file for vax.
   Copyright (C) 1985, 1986, 2001, 2002, 2003, 2004, 2005, 2006, 2007,
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


/* The following line tells the configuration script what sort of
   operating system this machine is likely to run.
   USUAL-OPSYS="note"

NOTE-START
The vax (-machine=vax) runs zillions of different operating systems.

NOTE-END  */

/* Define WORDS_BIG_ENDIAN if lowest-numbered byte in a word
   is the most significant byte.  */

#undef WORDS_BIG_ENDIAN

/* #define vax    -- appears to be done automatically  */

/* crt0.c should use the vax-bsd style of entry, with no dummy args.  */

#define CRT0_DUMMIES

#ifdef BSD_SYSTEM
/* USG systems I know of running on Vaxes do not actually
   support the load average, so disable it for them.  */

/* Data type of load average, as read out of kmem.  */

#define LOAD_AVE_TYPE double

/* Convert that into an integer that is 100 for a load average of 1.0  */

#define LOAD_AVE_CVT(x) ((int) ((x) * 100.0))

#endif /* BSD_SYSTEM */

#ifdef BSD4_2
#define HAVE_FTIME
#endif

/* arch-tag: 508bdf7a-01a0-4ce0-8eba-0704d0df55a0
   (do not change this comment) */
