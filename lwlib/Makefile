# Copyright (C) 1992, 1993 Lucid, Inc.
# Copyright (C) 1994, 2001, 2002, 2003, 2004, 2005, 2006,
#   2007, 2008, 2009, 2010 Free Software Foundation, Inc.
# 
# This file is part of the Lucid Widget Library.
# 
# The Lucid Widget Library is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 1, or (at your option)
# any later version.
# 
# The Lucid Widget Library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with GNU Emacs; see the file COPYING.  If not, write to
# the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.


# This was taken from the output of Imake using Lucid's Imakefile.
# and set up to be configured by ../configure.

srcdir=/home/debian/local/github/emacs/lwlib
VPATH=/home/debian/local/github/emacs/lwlib
C_SWITCH_X_SITE=

CC=gcc
CFLAGS=-g -O2 -Wdeclaration-after-statement -Wno-pointer-sign  
CPP=gcc -E
CPPFLAGS=-D_BSD_SOURCE  
LN_S=ln -s
RANLIB=ranlib
# See below--none is used below.
USE_X_TOOLKIT=none

              TOP = .

               AR = ar cq

               LN = ln -s
               RM = rm -f

     LUCID_OBJS = lwlib-Xlw.o xlwmenu.o lwlib-Xaw.o
     MOTIF_OBJS = lwlib-Xm.o

TOOLKIT_DEFINES = 
   TOOLKIT_OBJS = $(none_OBJS)

           OBJS = lwlib.o $(TOOLKIT_OBJS) lwlib-utils.o

# ../src is needed to find config.h.
ALL_CFLAGS= $(C_SWITCH_SYSTEM) $(C_SWITCH_X_SITE) \
  $(C_SWITCH_X_SYSTEM) $(C_SWITCH_MACHINE) $(CFLAGS) \
  -DHAVE_CONFIG_H -Demacs -I. -I../src -I${srcdir} -I${srcdir}/../src

.c.o:
	$(CC) -c $(CPPFLAGS) ${ALL_CFLAGS} $<

all:: liblw.a

liblw.a: $(OBJS)
	$(RM) $@
	$(AR) $@ $(OBJS)
	$(RANLIB) $@

# Depend on Makefile so that we recompile if TOOLKIT_DEFINES changes.
lwlib.o:  $(srcdir)/lwlib.c  Makefile
	$(CC) -c $(CPPFLAGS) $(TOOLKIT_DEFINES) $(ALL_CFLAGS) $(srcdir)/lwlib.c

lwlib-utils.o: lwlib-utils.c lwlib-utils.h
lwlib.o:       lwlib.c lwlib.h lwlib-int.h lwlib-Xaw.h lwlib-Xlw.h
lwlib-Xlw.o:   lwlib-Xlw.c lwlib.h lwlib-int.h lwlib-Xlw.h
lwlib-Xaw.o:   lwlib-Xaw.c lwlib-Xaw.h lwlib.h lwlib-int.h
lwlib-Xm.o:    lwlib-Xm.c lwlib-Xm.h lwlib.h lwlib-int.h lwlib-utils.h
xlwmenu.o: xlwmenu.c xlwmenu.h lwlib.h xlwmenuP.h

mostlyclean:
	$(RM) *.o core errs ,* *.a .emacs_* make.log MakeOut \#*

clean: mostlyclean
distclean: clean
	$(RM) Makefile
maintainer-clean: distclean
	$(RM) TAGS

TAGS:
	../lib-src/etags $(srcdir)/*.[ch]
tags: TAGS
.PHONY: tags
