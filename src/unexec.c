/* Copyright (C) 1985, 1986, 1987, 1988, 1992, 1993, 1994, 2001, 2002, 2003,
                 2004, 2005, 2006, 2007, 2008, 2009, 2010  Free Software Foundation, Inc.

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


/*
 * unexec.c - Convert a running program into an a.out file.
 *
 * Author:	Spencer W. Thomas
 * 		Computer Science Dept.
 * 		University of Utah
 * Date:	Tue Mar  2 1982
 * Modified heavily since then.
 *
 * Synopsis:
 *	unexec (new_name, a_name, data_start, bss_start, entry_address)
 *	char *new_name, *a_name;
 *	unsigned data_start, bss_start, entry_address;
 *
 * Takes a snapshot of the program and makes an a.out format file in the
 * file named by the string argument new_name.
 * If a_name is non-NULL, the symbol table will be taken from the given file.
 * On some machines, an existing a_name file is required.
 *
 * The boundaries within the a.out file may be adjusted with the data_start
 * and bss_start arguments.  Either or both may be given as 0 for defaults.
 *
 * Data_start gives the boundary between the text segment and the data
 * segment of the program.  The text segment can contain shared, read-only
 * program code and literal data, while the data segment is always unshared
 * and unprotected.  Data_start gives the lowest unprotected address.
 * The value you specify may be rounded down to a suitable boundary
 * as required by the machine you are using.
 *
 * Specifying zero for data_start means the boundary between text and data
 * should not be the same as when the program was loaded.
 * If NO_REMAP is defined, the argument data_start is ignored and the
 * segment boundaries are never changed.
 *
 * Bss_start indicates how much of the data segment is to be saved in the
 * a.out file and restored when the program is executed.  It gives the lowest
 * unsaved address, and is rounded up to a page boundary.  The default when 0
 * is given assumes that the entire data segment is to be stored, including
 * the previous data and bss as well as any additional storage allocated with
 * break (2).
 *
 * The new file is set up to start at entry_address.
 *
 * If you make improvements I'd like to get them too.
 * harpo!utah-cs!thomas, thomas@Utah-20
 *
 */

/* Modified to support SysVr3 shared libraries by James Van Artsdalen
 * of Dell Computer Corporation.  james@bigtex.cactus.org.
 */

/* There are several compilation parameters affecting unexec:

* COFF

Define this if your system uses COFF for executables.

* NO_REMAP

Define this if you do not want to try to save Emacs's pure data areas
as part of the text segment.

Saving them as text is good because it allows users to share more.

However, on machines that locate the text area far from the data area,
the boundary cannot feasibly be moved.  Such machines require
NO_REMAP.

Also, remapping can cause trouble with the built-in startup routine
/lib/crt0.o, which defines `environ' as an initialized variable.
Dumping `environ' as pure does not work!  So, to use remapping,
you must write a startup routine for your machine in Emacs's crt0.c.
If NO_REMAP is defined, Emacs uses the system's crt0.o.

* SECTION_ALIGNMENT

Some machines that use COFF executables require that each section
start on a certain boundary *in the COFF file*.  Such machines should
define SECTION_ALIGNMENT to a mask of the low-order bits that must be
zero on such a boundary.  This mask is used to control padding between
segments in the COFF file.

If SECTION_ALIGNMENT is not defined, the segments are written
consecutively with no attempt at alignment.  This is right for
unmodified system V.

* SEGMENT_MASK

Some machines require that the beginnings and ends of segments
*in core* be on certain boundaries.  For most machines, a page
boundary is sufficient.  That is the default.  When a larger
boundary is needed, define SEGMENT_MASK to a mask of
the bits that must be zero on such a boundary.

* ADJUST_EXEC_HEADER

This macro can be used to generate statements to adjust or
initialize nonstandard fields in the file header

*/

#ifndef emacs
#define PERROR(arg) perror (arg); return -1
#else
#include <config.h>
#define PERROR(file) report_error (file, new)
#endif

#ifndef CANNOT_DUMP  /* all rest of file!  */

#ifdef HAVE_COFF_H
#include <coff.h>
#ifdef MSDOS
#if __DJGPP__ > 1
#include <fcntl.h>  /* for O_RDONLY, O_RDWR */
#include <crt0.h>   /* for _crt0_startup_flags and its bits */
static int save_djgpp_startup_flags;
#endif /* __DJGPP__ > 1 */
#define filehdr external_filehdr
#define scnhdr external_scnhdr
#define syment external_syment
#define auxent external_auxent
#define n_numaux e_numaux
#define n_type e_type
struct aouthdr
{
  unsigned short	magic;	/* type of file				*/
  unsigned short	vstamp;	/* version stamp			*/
  unsigned long		tsize;	/* text size in bytes, padded to FW bdry*/
  unsigned long		dsize;	/* initialized data "  "		*/
  unsigned long		bsize;	/* uninitialized data "   "		*/
  unsigned long		entry;	/* entry pt.				*/
  unsigned long	 	text_start;/* base of text used for this file */
  unsigned long	 	data_start;/* base of data used for this file */
};
#endif /* not MSDOS */
#else  /* not HAVE_COFF_H */
#include <a.out.h>
#endif /* not HAVE_COFF_H */

/* Define getpagesize if the system does not.
   Note that this may depend on symbols defined in a.out.h.  */
#include "getpagesize.h"

#ifndef makedev			/* Try to detect types.h already loaded */
#include <sys/types.h>
#endif /* makedev */
#include <stdio.h>
#include <sys/stat.h>
#include <errno.h>

#include <sys/file.h>

#ifndef O_RDONLY
#define O_RDONLY 0
#endif
#ifndef O_RDWR
#define O_RDWR 2
#endif


extern char *start_of_text ();		/* Start of text */
extern char *start_of_data ();		/* Start of initialized data */

static long block_copy_start;		/* Old executable start point */
static struct filehdr f_hdr;		/* File header */
static struct aouthdr f_ohdr;		/* Optional file header (a.out) */
long bias;			/* Bias to add for growth */
long lnnoptr;			/* Pointer to line-number info within file */
#define SYMS_START block_copy_start

static long text_scnptr;
static long data_scnptr;

static long coff_offset;

static int pagemask;

/* Correct an int which is the bit pattern of a pointer to a byte
   into an int which is the number of a byte.
   This is a no-op on ordinary machines, but not on all.  */

#define ADDR_CORRECT(x) ((char *)(x) - (char*)0)

#ifdef emacs

#include <setjmp.h>
#include "lisp.h"

static
report_error (file, fd)
     char *file;
     int fd;
{
  if (fd)
    close (fd);
  report_file_error ("Cannot unexec", Fcons (build_string (file), Qnil));
}
#endif /* emacs */

#define ERROR0(msg) report_error_1 (new, msg, 0, 0); return -1
#define ERROR1(msg,x) report_error_1 (new, msg, x, 0); return -1
#define ERROR2(msg,x,y) report_error_1 (new, msg, x, y); return -1

static
report_error_1 (fd, msg, a1, a2)
     int fd;
     char *msg;
     int a1, a2;
{
  close (fd);
#ifdef emacs
  error (msg, a1, a2);
#else
  fprintf (stderr, msg, a1, a2);
  fprintf (stderr, "\n");
#endif
}

static int make_hdr ();
static int copy_text_and_data ();
static int copy_sym ();
static void mark_x ();

/* ****************************************************************
 * make_hdr
 *
 * Make the header in the new a.out from the header in core.
 * Modify the text and data sizes.
 */
static int
make_hdr (new, a_out, data_start, bss_start, entry_address, a_name, new_name)
     int new, a_out;
     unsigned data_start, bss_start, entry_address;
     char *a_name;
     char *new_name;
{
  int tem;
  auto struct scnhdr f_thdr;		/* Text section header */
  auto struct scnhdr f_dhdr;		/* Data section header */
  auto struct scnhdr f_bhdr;		/* Bss section header */
  auto struct scnhdr scntemp;		/* Temporary section header */
  register int scns;
  unsigned int bss_end;

  pagemask = getpagesize () - 1;

  /* Adjust text/data boundary. */
#ifdef NO_REMAP
  data_start = (int) start_of_data ();
#else /* not NO_REMAP */
  if (!data_start)
    data_start = (int) start_of_data ();
#endif /* not NO_REMAP */
  data_start = ADDR_CORRECT (data_start);

#ifdef SEGMENT_MASK
  data_start = data_start & ~SEGMENT_MASK; /* (Down) to segment boundary. */
#else
  data_start = data_start & ~pagemask; /* (Down) to page boundary. */
#endif

  bss_end = ADDR_CORRECT (sbrk (0)) + pagemask;
  bss_end &= ~ pagemask;

  /* Adjust data/bss boundary. */
  if (bss_start != 0)
    {
      bss_start = (ADDR_CORRECT (bss_start) + pagemask);
      /* (Up) to page bdry. */
      bss_start &= ~ pagemask;
      if (bss_start > bss_end)
	{
	  ERROR1 ("unexec: Specified bss_start (%u) is past end of program",
		  bss_start);
	}
    }
  else
    bss_start = bss_end;

  if (data_start > bss_start)	/* Can't have negative data size. */
    {
      ERROR2 ("unexec: data_start (%u) can't be greater than bss_start (%u)",
	      data_start, bss_start);
    }

  coff_offset = 0L;		/* stays zero, except in DJGPP */

  /* Salvage as much info from the existing file as possible */
  if (a_out >= 0)
    {
#ifdef MSDOS
#if __DJGPP__ > 1
      /* Support the coff-go32-exe format with a prepended stub, since
	 this is what GCC 2.8.0 and later generates by default in DJGPP.  */
      unsigned short mz_header[3];

      if (read (a_out, &mz_header, sizeof (mz_header)) != sizeof (mz_header))
	{
	  PERROR (a_name);
	}
      if (mz_header[0] == 0x5a4d || mz_header[0] == 0x4d5a) /* "MZ" or "ZM" */
	{
	  coff_offset = (long)mz_header[2] * 512L;
	  if (mz_header[1])
	    coff_offset += (long)mz_header[1] - 512L;
	  lseek (a_out, coff_offset, 0);
	}
      else
	lseek (a_out, 0L, 0);
#endif /* __DJGPP__ > 1 */
#endif /* MSDOS */
      if (read (a_out, &f_hdr, sizeof (f_hdr)) != sizeof (f_hdr))
	{
	  PERROR (a_name);
	}
      block_copy_start += sizeof (f_hdr);
      if (f_hdr.f_opthdr > 0)
	{
	  if (read (a_out, &f_ohdr, sizeof (f_ohdr)) != sizeof (f_ohdr))
	    {
	      PERROR (a_name);
	    }
	  block_copy_start += sizeof (f_ohdr);
	}
      /* Loop through section headers, copying them in */
      lseek (a_out, coff_offset + sizeof (f_hdr) + f_hdr.f_opthdr, 0);
      for (scns = f_hdr.f_nscns; scns > 0; scns--) {
	if (read (a_out, &scntemp, sizeof (scntemp)) != sizeof (scntemp))
	  {
	    PERROR (a_name);
	  }
	if (scntemp.s_scnptr > 0L)
	  {
            if (block_copy_start < scntemp.s_scnptr + scntemp.s_size)
	      block_copy_start = scntemp.s_scnptr + scntemp.s_size;
	  }
	if (strcmp (scntemp.s_name, ".text") == 0)
	  {
	    f_thdr = scntemp;
	  }
	else if (strcmp (scntemp.s_name, ".data") == 0)
	  {
	    f_dhdr = scntemp;
	  }
	else if (strcmp (scntemp.s_name, ".bss") == 0)
	  {
	    f_bhdr = scntemp;
	  }
      }
    }
  else
    {
      ERROR0 ("can't build a COFF file from scratch yet");
    }

  /* Now we alter the contents of all the f_*hdr variables
     to correspond to what we want to dump.  */

  f_hdr.f_flags |= (F_RELFLG | F_EXEC);
#ifndef NO_REMAP
  f_ohdr.text_start = (long) start_of_text ();
  f_ohdr.tsize = data_start - f_ohdr.text_start;
  f_ohdr.data_start = data_start;
#endif /* NO_REMAP */
  f_ohdr.dsize = bss_start - f_ohdr.data_start;
  f_ohdr.bsize = bss_end - bss_start;
  /* On some machines, the old values are right.
     ??? Maybe on all machines with NO_REMAP.  */
  f_thdr.s_size = f_ohdr.tsize;
  f_thdr.s_scnptr = sizeof (f_hdr) + sizeof (f_ohdr);
  f_thdr.s_scnptr += (f_hdr.f_nscns) * (sizeof (f_thdr));
  lnnoptr = f_thdr.s_lnnoptr;
#ifdef SECTION_ALIGNMENT
  /* Some systems require special alignment
     of the sections in the file itself.  */
  f_thdr.s_scnptr
    = (f_thdr.s_scnptr + SECTION_ALIGNMENT) & ~SECTION_ALIGNMENT;
#endif /* SECTION_ALIGNMENT */
  text_scnptr = f_thdr.s_scnptr;
  f_dhdr.s_paddr = f_ohdr.data_start;
  f_dhdr.s_vaddr = f_ohdr.data_start;
  f_dhdr.s_size = f_ohdr.dsize;
  f_dhdr.s_scnptr = f_thdr.s_scnptr + f_thdr.s_size;
#ifdef SECTION_ALIGNMENT
  /* Some systems require special alignment
     of the sections in the file itself.  */
  f_dhdr.s_scnptr
    = (f_dhdr.s_scnptr + SECTION_ALIGNMENT) & ~SECTION_ALIGNMENT;
#endif /* SECTION_ALIGNMENT */
#ifdef DATA_SECTION_ALIGNMENT
  /* Some systems require special alignment
     of the data section only.  */
  f_dhdr.s_scnptr
    = (f_dhdr.s_scnptr + DATA_SECTION_ALIGNMENT) & ~DATA_SECTION_ALIGNMENT;
#endif /* DATA_SECTION_ALIGNMENT */
  data_scnptr = f_dhdr.s_scnptr;
  f_bhdr.s_paddr = f_ohdr.data_start + f_ohdr.dsize;
  f_bhdr.s_vaddr = f_ohdr.data_start + f_ohdr.dsize;
  f_bhdr.s_size = f_ohdr.bsize;
  f_bhdr.s_scnptr = 0L;
  bias = f_dhdr.s_scnptr + f_dhdr.s_size - block_copy_start;

  if (f_hdr.f_symptr > 0L)
    {
      f_hdr.f_symptr += bias;
    }

  if (f_thdr.s_lnnoptr > 0L)
    {
      f_thdr.s_lnnoptr += bias;
    }

#ifdef ADJUST_EXEC_HEADER
  ADJUST_EXEC_HEADER;
#endif /* ADJUST_EXEC_HEADER */

  if (write (new, &f_hdr, sizeof (f_hdr)) != sizeof (f_hdr))
    {
      PERROR (new_name);
    }

  if (write (new, &f_ohdr, sizeof (f_ohdr)) != sizeof (f_ohdr))
    {
      PERROR (new_name);
    }

  if (write (new, &f_thdr, sizeof (f_thdr)) != sizeof (f_thdr))
    {
      PERROR (new_name);
    }

  if (write (new, &f_dhdr, sizeof (f_dhdr)) != sizeof (f_dhdr))
    {
      PERROR (new_name);
    }

  if (write (new, &f_bhdr, sizeof (f_bhdr)) != sizeof (f_bhdr))
    {
      PERROR (new_name);
    }

  return (0);

}

write_segment (new, ptr, end)
     int new;
     register char *ptr, *end;
{
  register int i, nwrite, ret;
  char buf[80];
#ifndef USE_CRT_DLL
  extern int errno;
#endif
  /* This is the normal amount to write at once.
     It is the size of block that NFS uses.  */
  int writesize = 1 << 13;
  int pagesize = getpagesize ();
  char zeros[1 << 13];

  bzero (zeros, sizeof (zeros));

  for (i = 0; ptr < end;)
    {
      /* Distance to next multiple of writesize.  */
      nwrite = (((int) ptr + writesize) & -writesize) - (int) ptr;
      /* But not beyond specified end.  */
      if (nwrite > end - ptr) nwrite = end - ptr;
      ret = write (new, ptr, nwrite);
      /* If write gets a page fault, it means we reached
	 a gap between the old text segment and the old data segment.
	 This gap has probably been remapped into part of the text segment.
	 So write zeros for it.  */
      if (ret == -1
#ifdef EFAULT
	  && errno == EFAULT
#endif
	  )
	{
	  /* Write only a page of zeros at once,
	     so that we don't overshoot the start
	     of the valid memory in the old data segment.  */
	  if (nwrite > pagesize)
	    nwrite = pagesize;
	  write (new, zeros, nwrite);
	}
#if 0 /* Now that we have can ask `write' to write more than a page,
	 it is legit for write do less than the whole amount specified.  */
      else if (nwrite != ret)
	{
	  sprintf (buf,
		   "unexec write failure: addr 0x%x, fileno %d, size 0x%x, wrote 0x%x, errno %d",
		   ptr, new, nwrite, ret, errno);
	  PERROR (buf);
	}
#endif
      i += nwrite;
      ptr += nwrite;
    }
}
/* ****************************************************************
 * copy_text_and_data
 *
 * Copy the text and data segments from memory to the new a.out
 */
static int
copy_text_and_data (new, a_out)
     int new, a_out;
{
  register char *end;
  register char *ptr;

#ifdef MSDOS
#if __DJGPP__ >= 2
  /* Dump the original table of exception handlers, not the one
     where our exception hooks are registered.  */
  __djgpp_exception_toggle ();

  /* Switch off startup flags that might have been set at runtime
     and which might change the way that dumped Emacs works.  */
  save_djgpp_startup_flags = _crt0_startup_flags;
  _crt0_startup_flags &= ~(_CRT0_FLAG_NO_LFN | _CRT0_FLAG_NEARPTR);
#endif
#endif

  lseek (new, (long) text_scnptr, 0);
  ptr = (char *) f_ohdr.text_start;
  end = ptr + f_ohdr.tsize;
  write_segment (new, ptr, end);

  lseek (new, (long) data_scnptr, 0);
  ptr = (char *) f_ohdr.data_start;
  end = ptr + f_ohdr.dsize;
  write_segment (new, ptr, end);

#ifdef MSDOS
#if __DJGPP__ >= 2
  /* Restore our exception hooks.  */
  __djgpp_exception_toggle ();

  /* Restore the startup flags.  */
  _crt0_startup_flags = save_djgpp_startup_flags;
#endif
#endif


  return 0;
}

/* ****************************************************************
 * copy_sym
 *
 * Copy the relocation information and symbol table from the a.out to the new
 */
static int
copy_sym (new, a_out, a_name, new_name)
     int new, a_out;
     char *a_name, *new_name;
{
  char page[1024];
  int n;

  if (a_out < 0)
    return 0;

  if (SYMS_START == 0L)
    return 0;

  if (lnnoptr)			/* if there is line number info */
    lseek (a_out, coff_offset + lnnoptr, 0);	/* start copying from there */
  else
    lseek (a_out, coff_offset + SYMS_START, 0);	/* Position a.out to symtab. */

  while ((n = read (a_out, page, sizeof page)) > 0)
    {
      if (write (new, page, n) != n)
	{
	  PERROR (new_name);
	}
    }
  if (n < 0)
    {
      PERROR (a_name);
    }
  return 0;
}

/* ****************************************************************
 * mark_x
 *
 * After successfully building the new a.out, mark it executable
 */
static void
mark_x (name)
     char *name;
{
  struct stat sbuf;
  int um;
  int new = 0;  /* for PERROR */

  um = umask (777);
  umask (um);
  if (stat (name, &sbuf) == -1)
    {
      PERROR (name);
    }
  sbuf.st_mode |= 0111 & ~um;
  if (chmod (name, sbuf.st_mode) == -1)
    PERROR (name);
}

#ifndef COFF_BSD_SYMBOLS

/*
 *	If the COFF file contains a symbol table and a line number section,
 *	then any auxiliary entries that have values for x_lnnoptr must
 *	be adjusted by the amount that the line number section has moved
 *	in the file (bias computed in make_hdr).  The #@$%&* designers of
 *	the auxiliary entry structures used the absolute file offsets for
 *	the line number entry rather than an offset from the start of the
 *	line number section!
 *
 *	When I figure out how to scan through the symbol table and pick out
 *	the auxiliary entries that need adjustment, this routine will
 *	be fixed.  As it is now, all such entries are wrong and sdb
 *	will complain.   Fred Fish, UniSoft Systems Inc.
 */

/* This function is probably very slow.  Instead of reopening the new
   file for input and output it should copy from the old to the new
   using the two descriptors already open (WRITEDESC and READDESC).
   Instead of reading one small structure at a time it should use
   a reasonable size buffer.  But I don't have time to work on such
   things, so I am installing it as submitted to me.  -- RMS.  */

adjust_lnnoptrs (writedesc, readdesc, new_name)
     int writedesc;
     int readdesc;
     char *new_name;
{
  register int nsyms;
  register int new;
  struct syment symentry;
  union auxent auxentry;

  if (!lnnoptr || !f_hdr.f_symptr)
    return 0;

#ifdef MSDOS
  if ((new = writedesc) < 0)
#else
  if ((new = open (new_name, O_RDWR)) < 0)
#endif
    {
      PERROR (new_name);
      return -1;
    }

  lseek (new, f_hdr.f_symptr, 0);
  for (nsyms = 0; nsyms < f_hdr.f_nsyms; nsyms++)
    {
      read (new, &symentry, SYMESZ);
      if (symentry.n_numaux)
	{
	  read (new, &auxentry, AUXESZ);
	  nsyms++;
	  if (ISFCN (symentry.n_type) || symentry.n_type == 0x2400)
	    {
	      auxentry.x_sym.x_fcnary.x_fcn.x_lnnoptr += bias;
	      lseek (new, -AUXESZ, 1);
	      write (new, &auxentry, AUXESZ);
	    }
	}
    }
#ifndef MSDOS
  close (new);
#endif
  return 0;
}

#endif /* COFF_BSD_SYMBOLS */

/* ****************************************************************
 * unexec
 *
 * driving logic.
 */
unexec (new_name, a_name, data_start, bss_start, entry_address)
     char *new_name, *a_name;
     unsigned data_start, bss_start, entry_address;
{
  int new, a_out = -1;

  if (a_name && (a_out = open (a_name, O_RDONLY)) < 0)
    {
      PERROR (a_name);
    }
  if ((new = creat (new_name, 0666)) < 0)
    {
      PERROR (new_name);
    }

  if (make_hdr (new, a_out, data_start, bss_start, entry_address, a_name, new_name) < 0
      || copy_text_and_data (new, a_out) < 0
      || copy_sym (new, a_out, a_name, new_name) < 0
#ifndef COFF_BSD_SYMBOLS
      || adjust_lnnoptrs (new, a_out, new_name) < 0
#endif
      )
    {
      close (new);
      /* unlink (new_name);	    	/* Failed, unlink new a.out */
      return -1;
    }

  close (new);
  if (a_out >= 0)
    close (a_out);
  mark_x (new_name);
  return 0;
}

#endif /* not CANNOT_DUMP */

/* arch-tag: 62409b69-e27a-4a7c-9413-0210d6b54e7f
   (do not change this comment) */
