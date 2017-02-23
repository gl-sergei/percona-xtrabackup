/******************************************************
Copyright (c) 2011-2013 Percona LLC and/or its affiliates.

The xbstream utility: serialize/deserialize files in the XBSTREAM format.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; version 2 of the License.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA

*******************************************************/

#include <mysql_version.h>
#include <my_base.h>
#include <my_getopt.h>
#include <hash.h>
#include <pthread.h>
#include "common.h"
#include "xbstream.h"
#include "ds_local.h"
#include "ds_stdout.h"

#define XBSTREAM_VERSION "1.0"
#define XBSTREAM_BUFFER_SIZE (10 * 1024 * 1024UL)

#define START_FILE_HASH_SIZE 16

typedef enum {
	RUN_MODE_NONE,
	RUN_MODE_CREATE,
	RUN_MODE_EXTRACT
} run_mode_t;

/* Need the following definitions to avoid linking with ds_*.o and their link
dependencies */
datasink_t datasink_archive;
datasink_t datasink_xbstream;
datasink_t datasink_compress;
datasink_t datasink_tmpfile;
datasink_t datasink_encrypt;
datasink_t datasink_buffer;

static run_mode_t 	opt_mode;
static char *		opt_directory = NULL;
static my_bool		opt_verbose = 0;
static int		opt_parallel;

static struct my_option my_long_options[] =
{
	{"help", '?', "Display this help and exit.",
	 0, 0, 0, GET_NO_ARG, NO_ARG, 0, 0, 0, 0, 0, 0},
	{"create", 'c', "Stream the specified files to the standard output.",
	 0, 0, 0, GET_NO_ARG, NO_ARG, 0, 0, 0, 0, 0, 0},
	{"extract", 'x', "Extract to disk files from the stream on the "
	 "standard input.",
	 0, 0, 0, GET_NO_ARG, NO_ARG, 0, 0, 0, 0, 0, 0},
	{"directory", 'C', "Change the current directory to the specified one "
	 "before streaming or extracting.", &opt_directory, &opt_directory, 0,
	 GET_STR_ALLOC, REQUIRED_ARG, 0, 0, 0, 0, 0, 0},
	{"verbose", 'v', "Print verbose output.", &opt_verbose, &opt_verbose,
	 0, GET_BOOL, NO_ARG, 0, 0, 0, 0, 0, 0},
	{"parallel", 'p', "Number of worker threads for reading / writing.",
	 &opt_parallel, &opt_parallel, 0, GET_INT, REQUIRED_ARG,
	 1, 1, INT_MAX, 0, 0, 0},

	{0, 0, 0, 0, 0, 0, GET_NO_ARG, NO_ARG, 0, 0, 0, 0, 0, 0}
};

typedef struct {
	char 		*path;
	uint		pathlen;
	my_off_t	offset;
	ds_ctxt_t	*ds_ctxt;
	ds_file_t	*file;
	pthread_mutex_t mutex;
} file_entry_t;

static int get_options(int *argc, char ***argv);
static int mode_create(int argc, char **argv);
static int mode_extract(int n_threads, int argc, char **argv);
static my_bool get_one_option(int optid, const struct my_option *opt,
			      char *argument);

void
ut_crc32_init();

int
main(int argc, char **argv)
{
	MY_INIT(argv[0]);

	ut_crc32_init();

	if (get_options(&argc, &argv)) {
		goto err;
	}

	if (opt_mode == RUN_MODE_NONE) {
		msg("%s: either -c or -x must be specified.\n", my_progname);
		goto err;
	}

	/* Change the current directory if -C is specified */
	if (opt_directory && my_setwd(opt_directory, MYF(MY_WME))) {
		goto err;
	}

	if (opt_mode == RUN_MODE_CREATE && mode_create(argc, argv)) {
		goto err;
	} else if (opt_mode == RUN_MODE_EXTRACT &&
		   mode_extract(opt_parallel, argc, argv)) {
		goto err;
	}

	my_cleanup_options(my_long_options);

	my_end(0);

	return EXIT_SUCCESS;
err:
	my_cleanup_options(my_long_options);

	my_end(0);

	exit(EXIT_FAILURE);
}

static
int
get_options(int *argc, char ***argv)
{
	int ho_error;

	if ((ho_error= handle_options(argc, argv, my_long_options,
				      get_one_option))) {
		exit(EXIT_FAILURE);
	}

	return 0;
}

static
void
print_version(void)
{
	printf("%s  Ver %s for %s (%s)\n", my_progname, XBSTREAM_VERSION,
	       SYSTEM_TYPE, MACHINE_TYPE);
}

static
void
usage(void)
{
	print_version();
	puts("Copyright (C) 2011-2013 Percona LLC and/or its affiliates.");
	puts("This software comes with ABSOLUTELY NO WARRANTY. "
	     "This is free software,\nand you are welcome to modify and "
	     "redistribute it under the GPL license.\n");

	puts("Serialize/deserialize files in the XBSTREAM format.\n");

	puts("Usage: ");
	printf("  %s -c [OPTIONS...] FILES...	# stream specified files to "
	       "standard output.\n", my_progname);
	printf("  %s -x [OPTIONS...]		# extract files from the stream"
	       "on the standard input.\n", my_progname);

	puts("\nOptions:");
	my_print_help(my_long_options);
}

static
int
set_run_mode(run_mode_t mode)
{
	if (opt_mode != RUN_MODE_NONE) {
		msg("%s: can't set specify both -c and -x.\n", my_progname);
		return 1;
	}

	opt_mode = mode;

	return 0;
}

static
my_bool
get_one_option(int optid, const struct my_option *opt __attribute__((unused)),
	       char *argument __attribute__((unused)))
{
	switch (optid) {
	case 'c':
		if (set_run_mode(RUN_MODE_CREATE)) {
			return TRUE;
		}
		break;
	case 'x':
		if (set_run_mode(RUN_MODE_EXTRACT)) {
			return TRUE;
		}
		break;
	case '?':
		usage();
		exit(0);
	}

	return FALSE;
}

static
int
stream_one_file(File file, xb_wstream_file_t *xbfile)
{
	uchar	*buf;
	size_t	bytes;
	size_t	offset;

	posix_fadvise(file, 0, 0, POSIX_FADV_SEQUENTIAL);
	offset = my_tell(file, MYF(MY_WME));

	buf = (uchar*)(my_malloc(PSI_NOT_INSTRUMENTED, XBSTREAM_BUFFER_SIZE,
				 MYF(MY_FAE)));

	while ((bytes = my_read(file, buf, XBSTREAM_BUFFER_SIZE,
				MYF(MY_WME))) > 0) {
		if (xb_stream_write_data(xbfile, buf, bytes)) {
			msg("%s: xb_stream_write_data() failed.\n",
			    my_progname);
			my_free(buf);
			return 1;
		}
		posix_fadvise(file, offset, XBSTREAM_BUFFER_SIZE,
			      POSIX_FADV_DONTNEED);
		offset += XBSTREAM_BUFFER_SIZE;

	}

	my_free(buf);

	if (bytes == (size_t) -1) {
		return 1;
	}

	return 0;
}

static
int
mode_create(int argc, char **argv)
{
	int		i;
	MY_STAT		mystat;
	xb_wstream_t	*stream;

	if (argc < 1) {
		msg("%s: no files are specified.\n", my_progname);
		return 1;
	}

	stream = xb_stream_write_new();
	if (stream == NULL) {
		msg("%s: xb_stream_write_new() failed.\n", my_progname);
		return 1;
	}

	for (i = 0; i < argc; i++) {
		char			*filepath = argv[i];
		File			src_file;
		xb_wstream_file_t	*file;

		if (my_stat(filepath, &mystat, MYF(MY_WME)) == NULL) {
			goto err;
		}
		if (!MY_S_ISREG(mystat.st_mode)) {
			msg("%s: %s is not a regular file, exiting.\n",
			    my_progname, filepath);
			goto err;
		}

		if ((src_file = my_open(filepath, O_RDONLY, MYF(MY_WME))) < 0) {
			msg("%s: failed to open %s.\n", my_progname, filepath);
			goto err;
		}

		file = xb_stream_write_open(stream, filepath, &mystat, NULL, NULL);
		if (file == NULL) {
			goto err;
		}

		if (opt_verbose) {
			msg("%s\n", filepath);
		}

		if (stream_one_file(src_file, file) ||
		    xb_stream_write_close(file) ||
		    my_close(src_file, MYF(MY_WME))) {
			goto err;
		}
	}

	xb_stream_write_done(stream);

	return 0;
err:
	xb_stream_write_done(stream);

	return 1;
}

static
file_entry_t *
file_entry_new(ds_ctxt_t *ds_ctxt, const char *path, uint pathlen)
{
	file_entry_t	*entry;
	ds_file_t	*file;

	entry = (file_entry_t *) my_malloc(PSI_NOT_INSTRUMENTED,
					   sizeof(file_entry_t),
					   MYF(MY_WME | MY_ZEROFILL));
	if (entry == NULL) {
		return NULL;
	}

	entry->path = my_strndup(PSI_NOT_INSTRUMENTED,
				 path, pathlen, MYF(MY_WME));
	if (entry->path == NULL) {
		goto err;
	}
	entry->pathlen = pathlen;

	file = ds_open(ds_ctxt, path, NULL);
	if (file == NULL) {
		msg("%s: failed to create file.\n", my_progname);
		goto err;
	}

	if (opt_verbose) {
		msg("%s\n", entry->path);
	}

	entry->file = file;
	entry->ds_ctxt = ds_ctxt;

	pthread_mutex_init(&entry->mutex, NULL);

	return entry;

err:
	if (entry->path != NULL) {
		my_free(entry->path);
	}
	my_free(entry);

	return NULL;
}

static
uchar *
get_file_entry_key(file_entry_t *entry, size_t *length,
		   my_bool not_used __attribute__((unused)))
{
	*length = entry->pathlen;
	return (uchar *) entry->path;
}

static
void
file_entry_free(file_entry_t *entry)
{
	pthread_mutex_destroy(&entry->mutex);
	ds_close(entry->file);
	my_free(entry->path);
	my_free(entry);
}


typedef struct {
	HASH			*filehash;
	xb_rstream_t		*stream;
	ds_ctxt_t		*ds_ctxt;
	pthread_mutex_t		*mutex;
} extract_ctxt_t;

static
void *
extract_worker_thread_func(void *arg)
{
	xb_rstream_chunk_t	chunk;
	file_entry_t		*entry;
	xb_rstream_result_t	res;

	extract_ctxt_t *ctxt = (extract_ctxt_t *) arg;

	while (1) {

		pthread_mutex_lock(ctxt->mutex);
		res = xb_stream_read_chunk(ctxt->stream, &chunk);

		if (res != XB_STREAM_READ_CHUNK) {
			pthread_mutex_unlock(ctxt->mutex);
			break;
		}

		/* If unknown type and ignorable flag is set, skip this chunk */
		if (chunk.type == XB_CHUNK_TYPE_UNKNOWN && \
		    !(chunk.flags & XB_STREAM_FLAG_IGNORABLE)) {
			pthread_mutex_unlock(ctxt->mutex);
			continue;
		}

		/* See if we already have this file open */
		entry = (file_entry_t *) my_hash_search(ctxt->filehash,
							(uchar *) chunk.path,
							chunk.pathlen);

		if (entry == NULL) {
			entry = file_entry_new(ctxt->ds_ctxt, chunk.path,
					       chunk.pathlen);
			if (entry == NULL) {
				pthread_mutex_unlock(ctxt->mutex);
				break;
			}
			if (my_hash_insert(ctxt->filehash, (uchar *) entry)) {
				msg("%s: my_hash_insert() failed.\n",
				    my_progname);
				pthread_mutex_unlock(ctxt->mutex);
				break;
			}
		}

		pthread_mutex_lock(&entry->mutex);

		pthread_mutex_unlock(ctxt->mutex);

		if (chunk.type == XB_CHUNK_TYPE_EOF) {
			my_hash_delete(ctxt->filehash, (uchar *) entry);
			pthread_mutex_unlock(&entry->mutex);
			continue;
		}

		if (entry->offset != chunk.offset) {
			msg("%s: out-of-order chunk: real offset = 0x%llx, "
			    "expected offset = 0x%llx\n", my_progname,
			    chunk.offset, entry->offset);
			pthread_mutex_unlock(&entry->mutex);
			break;
		}

		if (ds_write(entry->file, chunk.data, chunk.length)) {
			msg("%s: my_write() failed.\n", my_progname);
			pthread_mutex_unlock(&entry->mutex);
			break;
		}

		entry->offset += chunk.length;

		pthread_mutex_unlock(&entry->mutex);
	}

	return (void *)(res);
}


static
int
mode_extract(int n_threads, int argc __attribute__((unused)),
	     char **argv __attribute__((unused)))
{
	xb_rstream_t		*stream;
	HASH			filehash;
	ds_ctxt_t		*ds_ctxt;

	extract_ctxt_t		ctxt;
	int			i;

	pthread_t		*tids;
	int			*retvals;
	pthread_mutex_t		mutex;

	tids = malloc(sizeof(pthread_t) * n_threads);
	retvals = malloc(sizeof(int) * n_threads);

	pthread_mutex_init(&mutex, NULL);

	stream = xb_stream_read_new();
	if (stream == NULL) {
		msg("%s: xb_stream_read_new() failed.\n", my_progname);
		return 1;
	}

	/* If --directory is specified, it is already set as CWD by now. */
	ds_ctxt = ds_create(".", DS_TYPE_LOCAL);

	if (my_hash_init(&filehash, &my_charset_bin, START_FILE_HASH_SIZE,
			  0, 0, (my_hash_get_key) get_file_entry_key,
			  (my_hash_free_key) file_entry_free, MYF(0),
			  PSI_NOT_INSTRUMENTED)) {
		msg("%s: failed to initialize file hash.\n", my_progname);
		goto err;
	}

	ctxt.stream = stream;
	ctxt.filehash = &filehash;
	ctxt.ds_ctxt = ds_ctxt;
	ctxt.mutex = &mutex;

	for (i = 0; i < n_threads; i++)
		pthread_create(tids + i, NULL, extract_worker_thread_func, &ctxt);

	for (i = 0; i < n_threads; i++)
		pthread_join(tids[i], (void **)(retvals + i));

	for (i = 0; i < n_threads; i++) {
		if (retvals[i] == XB_STREAM_READ_ERROR) {
			goto err;
		}
	}

	pthread_mutex_destroy(&mutex);
	my_hash_free(&filehash);
	ds_destroy(ds_ctxt);
	xb_stream_read_done(stream);

	return 0;
err:
	pthread_mutex_destroy(&mutex);
	my_hash_free(&filehash);
	ds_destroy(ds_ctxt);
	xb_stream_read_done(stream);

	return 1;
}
