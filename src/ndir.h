/*
	<dir.h> -- definitions for 4.2BSD-compatible directory access

	last edit:	09-Jul-1983	D A Gwyn

 * The code here is forced by the interface, and is not subject to
 * copyright, constituting the only possible expression of the
 * algorithm in this format.
 */

#define DIRBLKSIZ	512		/* size of directory block */
#ifdef WINDOWSNT
#define MAXNAMLEN	255
#else  /* not WINDOWSNT */
#define MAXNAMLEN	15		/* maximum filename length */
#endif /* not WINDOWSNT */
	/* NOTE:  MAXNAMLEN must be one less than a multiple of 4 */

struct direct				/* data from readdir() */
	{
	long		d_ino;		/* inode number of entry */
	unsigned short	d_reclen;	/* length of this record */
	unsigned short	d_namlen;	/* length of string in d_name */
	char		d_name[MAXNAMLEN+1];	/* name of file */
	};

typedef struct
	{
	int	dd_fd;			/* file descriptor */
	int	dd_loc;			/* offset in block */
	int	dd_size;		/* amount of valid data */
	char	dd_buf[DIRBLKSIZ];	/* directory block */
	}	DIR;			/* stream data from opendir() */

extern DIR		*opendir();
extern struct direct	*readdir();
extern long		telldir();
extern void		seekdir();
extern void		closedir();

#define rewinddir( dirp )	seekdir( dirp, 0L )

/* arch-tag: aea50570-ffb7-43fd-b423-7743b10fbe6e
   (do not change this comment) */
