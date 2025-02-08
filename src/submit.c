#define _GNU_SOURCE /* for asprintf */
#include <sys/types.h>
#include <sys/file.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <unistd.h>
#include <time.h>
#include <dirent.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <stdarg.h>
#include <assert.h>
#include <string.h>
#include <err.h>
#include <pwd.h>

#if defined(SUBMISSION_FORMAT_TAR)
#include <libtar.h>
#define SUBMISSION_FORMAT_EXT "tar"
#define SUBMISSION_FILE_HANDLE_TYPE TAR
#elif defined(SUBMISSION_FORMAT_GIT_DIFF)
#define SUBMISSION_FORMAT_EXT "patch"
#define SUBMISSION_FILE_HANDLE_TYPE FILE
#else
#error "No submission format defined"
#endif
#include "project.h"

#define stringify_(t) #t
#define stringify(t) stringify_(t)

const char submissions_path_prefix[] = stringify(SUBMISSIONS_PATH_PREFIX);

char *submitting_user; // in environ
uid_t ruid;
gid_t rgid;

#ifndef MAX_SUBMISSION_SIZE
#define MAX_SUBMISSION_SIZE 8192000 /* 800 kB */
#endif
/* HACK: In 2020 we accepted some larger submissions before setting the max size.
 * To allow these to be marked, set a larger limit. Change this. */
#ifndef MAX_FEEDBACK_SIZE
#define MAX_FEEDBACK_SIZE 8192000 /* 8000 kB */
#endif

#define audit_println(fmt, args...) audit_println_helper(fmt "\n", ##args)
static int audit_println_helper(const char *fmt, ...);

char *basename(const char *path);
#ifdef _LIBGEN_H
#error "Do not include libgen.h! We require GNU basename()"
#endif
char *dirname(char *path);

/* Macroise the usage message so that we can easily append extra bits of format string
 * that can provide extra help when reporting usage failures. Note that the first
 * formatted argument should be argv[0]. */
#define USAGE_MSG_FOR_MOD(mod) \
"Usage: %s <n> [directory]\n" \
"    where <n> is a project number in module " stringify(mod) "\n" \
"    and [directory] contains your attempt at that project (omit for lssub)\n"

#define USAGE_MSG USAGE_MSG_FOR_MOD(MODULE)
const char usage[] =
USAGE_MSG
;

size_t name_max = 255; /* max filename length... we get it from pathconf() */
#ifdef SUBMISSION_FORMAT_TAR
_Bool recursively_add_directory(DIR *dir, FILE *auditf, FILE *outf, SUBMISSION_FILE_HANDLE_TYPE *t,
	char *prefix, unsigned *size, size_t max_size)
{
	_Bool success = 1;
	size_t prefixlen = strlen(prefix);
	assert(prefixlen == 0 || prefix[prefixlen - 1] == '/');
	if (prefixlen != 0) warnx("Writing tar file, recursed into directory %s", prefix);
#ifdef USE_READDIR_R
	off_t len = offsetof(struct dirent, d_name) + name_max + 1;
	struct dirent *entryp = (struct dirent *) malloc(len);
#endif
	struct dirent *the_entry = NULL;
	int ret;
#ifdef USE_READDIR_R
	while (0 == (ret = readdir_r(dir, entryp, &the_entry)) && the_entry)
#else
	while (NULL != (the_entry = readdir(dir)))
#endif
	{
#ifndef _DIRENT_HAVE_D_TYPE
#error "Must have d_type in struct dirent"
#endif
		// skip '.' and '..'
		if (0 == strcmp(the_entry->d_name, ".") || 0 == strcmp(the_entry->d_name, "..")) continue;
		// is it a regular file?
		if (the_entry->d_type == DT_REG || the_entry->d_type == DT_DIR
			|| the_entry->d_type == DT_LNK)
		{
			unsigned namebuf_sz = prefixlen + strlen(the_entry->d_name) + 1;
			char namebuf[namebuf_sz + 1]; // to leave room for an extra slash!
			ret = snprintf(namebuf, namebuf_sz, "%s%s", prefix, the_entry->d_name);
			if (ret != namebuf_sz - 1) errx(EXIT_FAILURE, "snprintf of tar entry name");
			if (the_entry->d_type == DT_REG || the_entry->d_type == DT_LNK)
			{
				struct stat s;
				/* Recall: we're chdir'd to the submission dir,
				 * so names should be relative to that, i.e. use the prefix. */
				ret = fstatat(AT_FDCWD, namebuf, &s, AT_EMPTY_PATH|AT_SYMLINK_NOFOLLOW);
				if (ret != 0) err(EXIT_FAILURE, "stating file %s", namebuf);
				if (*size + s.st_size > max_size)
				{
					warnx("Submission exceeded maximum size (%ld bytes)", (long) max_size);
					audit_println("Submission exceeded maximum size (%ld bytes)", (long) max_size);
					success = 0;
					break;
				}
				tar_append_file(t, namebuf, namebuf);
				*size += s.st_size;
			}
			else if (the_entry->d_type == DT_DIR)
			{
				/* Recall: our recursive variable 'dir' is the currently-added dir,
				 * so d_name is our path relative to that. */
				int newdirfd = openat(dirfd(dir), the_entry->d_name, O_RDONLY);
				if (newdirfd == -1) err(EXIT_FAILURE, "openat of directory %s", namebuf);
				DIR *newdir = fdopendir(newdirfd);
				if (!dir) err(EXIT_FAILURE, "opendir");
				// recurse
				namebuf[namebuf_sz - 1] = '/';
				namebuf[namebuf_sz] = '\0'; /* YES this looks wrong but is correct -- see above */
				success &= recursively_add_directory(newdir, auditf, outf, t,
					namebuf, size, max_size);
				close(newdirfd);
				if (!success) break;
			}
			else assert(0);
		}
		else
		{
			//fprintf(outf, "Ignoring non-regular file %s\n", the_entry->d_name);
		}

		the_entry = NULL; // just to be safe
	}
#ifdef USE_READDIR_R
	free(entryp);
#endif
	return success;
}

// we return 1 for success
_Bool write_submission_tar(DIR *dir, FILE *auditf, FILE *outf, SUBMISSION_FILE_HANDLE_TYPE *t, size_t max, void *arg)
{
	/* recursively add the directory tree to the tar file, keeping track of size. */
	unsigned size = 0;
	return recursively_add_directory(dir, auditf, outf, t, "", &size, max);
}
#endif /* SUBMISSION_FORMAT_TAR */

#if defined(SUBMISSION_FORMAT_GIT_DIFF)
// we return 1 for success
_Bool write_submission_git_diff(DIR *dir, FILE *auditf, FILE *outf, SUBMISSION_FILE_HANDLE_TYPE *t, size_t max, void *arg)
{
	/* PROBLEM: can we limit the submission size? YES, we popen and pipe to 'head' */
	/* PROBLEM: we need to know what the relevant ancestor commit is.
	 * This might vary by project, so it needs to be in the project struct. */
	char *cmd;
	int ret = asprintf(&cmd, "git diff '%s' | head -c%lu", (char*) arg, (unsigned long) max);
	if (ret == -1) { warnx("Problem printing git command string"); return 0; }
	FILE *diff = popen(cmd, "r");
	free(cmd);
	unsigned nbytes = 0;
	char buf[1024];
	while (!feof(diff))
	{
		ssize_t nread = fread(buf, 1, sizeof buf, diff);
		if (nread > 0)
		{
			size_t nwritten_total = 0;
			size_t nremaining = nread;
			while (nwritten_total < nread)
			{
				size_t nwritten = fwrite(buf, 1, nremaining, t);
				nwritten_total += nwritten; nremaining -= nwritten;
				if (nwritten < nremaining)
				{
					warnx("Problem writing git diff output (remaining %d, wrote %d)", (int) nremaining, (int) nwritten);
					if (nwritten == 0) goto out;
				}
			}
		}
		else // read nothing starting from non-EOF... that is odd
		{
			warnx("Problem reading git diff output (returned %d) -- have you made any changes?", (int) nread);
			goto out;
		}
		nbytes += nread;
	}
	int status;
out:
	status = pclose(diff);
	/* Did we hit the maximum? If so, output a warning. */
	if (nbytes >= max) warnx("Submission was truncated to %lu bytes", (unsigned long) max);
	/* Did we get a non-zero exit status? */
	if (status != 0)
	{ warnx("git returned an error; did you specify the path of the right git repo?"); goto git_error; }
	/* Did we get a zero-length output? */
	if (nbytes == 0)
	{ warnx("git returned no data; did you specify the path of the right git repo?"); goto git_error; }
	/* Looks like success. */
	return 1;
git_error:
	/* If git returned an error, err() will crash us out but will print a strerror. So
	 * set errno to something that won't confuse the caller. */
	errno = EINVAL;
	return 0;
}

#endif

_Bool run_helper(const char *helper_filename, const char *helper_argv1,
	DIR *dir, FILE *auditf, FILE *outf, int submfd /* may be -1 */)
{
	/* We are run with the invoking user's privileges, not the lecturer's.
	 * It's often useful to call out to a script or helper program at this
	 * point; this is a utility function for doing so. */
	pid_t p = fork();
	if (p == 0)
	{
		/* We are the child. Set up our fds and execve the helper.
		 * 0 (stdin)   -- the tar file
		 * 1 (stdout)  -- the feedback stream
		 * 2 (stderr)  -- stderr (unchanged)
		 * 7           -- the directory (not super-useful, but hey)
		 * 8           -- the audit log
		 */
		int ret = (submfd != -1) ? dup2(submfd, 0) : open("/dev/null", O_RDONLY);
		if (ret == -1) err(EXIT_FAILURE, "dup2 (1)");
		ret = dup2(fileno(outf), 1);
		if (ret == -1) err(EXIT_FAILURE, "dup2 (2)");
		ret = dup2(dirfd(dir), 7);
		if (ret == -1) err(EXIT_FAILURE, "dup2 (3)");
		if (auditf)
		{
			ret = dup2(fileno(auditf), 8);
			if (ret == -1) err(EXIT_FAILURE, "dup2 (4)");
		}
		else
		{
			ret = dup2(fileno(stderr), 8);
			if (ret == -1) err(EXIT_FAILURE, "dup2 (5)");
		}

		/* We also weed the environment, to avoid the user's environment
		 * doing funky things that mess with our logic. We allow
		 * HOME and TERM, but set PATH and SHELL to sane defaults
		 * and LANG to C. We also allow COLUMNS. But if COLUMNS is not
		 * set, we want to expose that to the child. */
		char *homestr = getenv("HOME");
		if (!homestr) errx(EXIT_FAILURE, "no home directory?");
		char *termstr = getenv("TERM");
		char *columnsstr = getenv("COLUMNS");
		char *environ[] = {
			homestr - (sizeof "HOME=" - 1),
			"PATH=/usr/bin:/bin",
			"SHELL=/bin/sh",
			"LANG=C",
			columnsstr ? columnsstr - (sizeof "COLUMNS=" - 1) : "COLUMNS_NOT_SET=1", /* HACK... */
			termstr ? termstr : NULL, /* ... we can only have one optional var */
			NULL
		};
		ret = execle(helper_filename,
			helper_filename, // yes really -- it's argv[0]
			(char*) helper_argv1,
			(char*) NULL, // no more arguments
			environ);
		err(EXIT_FAILURE, "exec of %s (%d)", helper_filename, ret);
	}
	else if (p != (pid_t) -1)
	{
		// we are the parent, and p is the child
		pid_t w;
		int status;
		do
		{
			w = waitpid(p, &status, WUNTRACED | WCONTINUED);
			if (w == -1)
			{
				err(EXIT_FAILURE, "waitpid");
			}
			if (WIFEXITED(status))
			{ /* exited with status WEXITSTATUS(status) */ }
			else if (WIFSIGNALED(status))
			{ /* killed by signal WTERMSIG(status) */ }
			else if (WIFSTOPPED(status))
			{ /* stopped by signal %d\n", WSTOPSIG(status)); */ }
			else if (WIFCONTINUED(status))
			{ /* continued */ }
		} while (!WIFEXITED(status) && !WIFSIGNALED(status));
		int ret = WIFEXITED(status) ? WEXITSTATUS(status) : -WTERMSIG(status);
		return (ret == 0);
	}
	else
	{
		// fork failed
		err(EXIT_FAILURE, "forking write-feedback helper");
	}

	// should be unreachable: we handle parent, child and fork-failed cases above
	assert(0);
}

struct project project_zero = { 0 };
REGISTER_PROJECT(project_zero);

extern struct project *__start__data_projectptrs;
extern struct project *__stop__data_projectptrs;

#define NPROJECTS ((&__stop__data_projectptrs - &__start__data_projectptrs) - 1)

struct project **projects = &__start__data_projectptrs;

static int compar_projptr(const void *projptrptr1, const void *projptrptr2)
{
	if (!*(struct project **)projptrptr1 || !*(struct project **)projptrptr2)
	{
		err(EXIT_FAILURE, "self-check: null project pointer; is the link sane?");
	}
	/* Compare by the project number. */
	return (*(struct project **) projptrptr1)->n - (*(struct project **) projptrptr2)->n;
}
static void (__attribute__((constructor)) init_projects)(void)
{
	/* Qsort the pointers by project number, then sanity-check their numbering. */
	qsort(&__start__data_projectptrs,
		NPROJECTS + 1,
		sizeof (struct project *),
		compar_projptr);
	for (unsigned i = 0; i <= NPROJECTS; ++i)
	{
		assert(&projects[i] < &__stop__data_projectptrs);
		assert(projects[i]->n == i);
	}
}

static FILE *auditf;
static int audit_println_helper(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	char datebuf[256];

	time_t tm = time(NULL);
	if (tm == (time_t) -1) err(EXIT_FAILURE, "getting time of day");
	struct tm the_time;
	struct tm *tm_ret = gmtime_r(&tm, &the_time);
	if (!tm_ret) err(EXIT_FAILURE, "converting time of day");
	size_t sz = strftime(datebuf, sizeof datebuf, "%F %T", tm_ret);
	if (sz <= 0) err(EXIT_FAILURE, "printing time of day");
	int ret = fprintf(auditf, "%s ", datebuf);
	if (ret > 0)
	{
		 int more_ret = vfprintf(auditf, fmt, ap);
		 if (more_ret < 0) ret = more_ret; else ret += more_ret;
	}
	va_end(ap);
	fflush(auditf);
	return ret;
}
/* To ensure we log any abnormal exits, even if done by err() or other
 * libc functions, we install an atexit function. */
_Bool audit_success;
void audit_exit(void)
{
	if (!audit_success && auditf) audit_println("Request failed");
}

static void check_submission_deadline(const char *submission_path_prefix,
	const char *submitting_user, int num)
{
	char *timestamp_path = NULL;
	int ret = asprintf(&timestamp_path, "%s/deadline-%d-%s", submissions_path_prefix, num,
		submitting_user);
	if (ret < 0) errx(EXIT_FAILURE, "printing user deadline file path");
	int nchars = ret; // save for later
	struct timespec effective_deadline;
	struct stat timestamp_file_stat;
	ret = stat(timestamp_path, &timestamp_file_stat);
	if (ret == 0)
	{
		/* This user has an extended deadline */
		memcpy(&effective_deadline, &timestamp_file_stat.st_mtime,
			sizeof effective_deadline);
		time_t deadline = effective_deadline.tv_sec;
		warnx("Your personal deadline is %s", asctime(localtime(&deadline)));
	}
	else
	{
		// chop the path
		timestamp_path[nchars - strlen(submitting_user) - 1] = '\0';
		ret = stat(timestamp_path, &timestamp_file_stat);
		if (ret != 0)
		{
			warnx("No deadline defined at %s", timestamp_path);
			goto out;
		}
		memcpy(&effective_deadline, &timestamp_file_stat.st_mtime,
			sizeof effective_deadline);
	}
	time_t deadline = effective_deadline.tv_sec;
	if (time(NULL) > deadline)
	{
		warnx("Deadline has passed; was %s", asctime(localtime(&deadline)));
	}
out:
	free(timestamp_path);
}

int main(int argc, char **argv)
{
	if (argc <= 0) abort(); // be super-defensive about corrupt args
	enum { INVALID, SUBMIT, LSSUB, FEEDBACK } mode;
	if (0 == strcmp(basename(argv[0]), "submit")) mode = SUBMIT;
	else if (0 == strcmp(basename(argv[0]), "feedback")) mode = FEEDBACK;
	else if (0 == strcmp(basename(argv[0]), "lssub")) mode = LSSUB;
	if (mode == INVALID)
	{
		errx(EXIT_FAILURE, "You must invoke this program as 'submit' or 'feedback' or 'lssub'");
	}
	if (argc < 2) errx(EXIT_FAILURE, usage, argv[0]);
	if (argv[1][0] < '0' || argv[1][0] > '9') errx(EXIT_FAILURE, usage, argv[0]);
	unsigned num = atoi(argv[1]);
	if (num < 1 || num > 12) errx(EXIT_FAILURE, "invalid project number: %d", num);

	/* If we're doing a submission, we need a writable fd onto a tar
 	 * descriptor, and a writable fd only the activity log file. If
	 * we're doing feedback, we need only the latter. */

	/* Beware concurrency! If multiple users have the activity log
	 * file open, strange things could happen if we use non-atomic
	 * writes, or if our descriptor isn't kept pointing at the
	 * last byte. We should use file locking on the activity log file. */

	uid_t euid = geteuid();
	/* global! */ ruid = getuid();
	/* global! */ rgid = getgid();

	if (euid != LECTURER_UID)
	{
		err(EXIT_FAILURE, "internal error: bad lecturer uid (%u; should be %u)",
			(unsigned) euid, (unsigned) LECTURER_UID);
	}
	/* global! */ submitting_user = getenv("USER");
	if (!submitting_user)
	{
		err(EXIT_FAILURE, "error: USER must be set");
	}

	/* We want to open the submission and/or audit files
	 * as appropriate, then drop our privileges. We also
	 * check for submission deadlines, because ordinary
	 * users shouldn't have sight of extensions. FIXME:
	 * currently they can see the extension file because
	 * its name is guessable, and they can stat() it
	 * (execute permission on the directory is enough). */
	char *audit_path;
	int ret = asprintf(&audit_path, "%s/%s", submissions_path_prefix, "audit.log");
	if (ret < 0) errx(EXIT_FAILURE, "printing audit file path");
	auditf = fopen(audit_path, "a");
	if (!auditf) err(EXIT_FAILURE, "opening audit file `%s'", audit_path);
	free(audit_path);
	ret = flock(fileno(auditf), LOCK_EX | LOCK_NB);
	if (ret != 0) err(EXIT_FAILURE, "locking audit file (try again in a minute?)");
	/* Problem: when do we unlock the audit file?
	 * Currently, only when we reach the end of main().
	 * For 'submit' this is fine.
	 * If we do an exec(), e.g. for 'lssub', this is never hit and so
	 * it is never explicitly unlocked, i.e. we rely on process cleanup.
	 * For 'feedback', it is OK but ideally we'd release it sooner.
	 */
	int submfd = -1;
	char *subpath;
	char *namepat;
	SUBMISSION_FILE_HANDLE_TYPE *submission_hdl = NULL;
	switch (mode)
	{
		case SUBMIT:
			ret = asprintf(&subpath, "%s/%02d-%s-XXXXXX." SUBMISSION_FORMAT_EXT,
				submissions_path_prefix, num, submitting_user);
			if (ret < 0) errx(EXIT_FAILURE, "printing submission path");
			check_submission_deadline(submissions_path_prefix, submitting_user, num);
			goto open_it;
		case FEEDBACK:
			// hard-code "/tmp" for security reasons (don't trust TMPDIR)
			ret = asprintf(&subpath, "/tmp/XXXXXX." SUBMISSION_FORMAT_EXT);
			if (ret < 0) errx(EXIT_FAILURE, "printing submission path");
			// fall through
			goto open_it;
		case LSSUB:
			/* This one is different. We list all the submitting user's submissions. */
			unsetenv("PATH");
			// namepat: '[0-9][0-9]-k2144518-*.patch'
			ret = asprintf(&namepat, "%02d-%s-??????." SUBMISSION_FORMAT_EXT,
				num, submitting_user);
			if (ret < 0) errx(EXIT_FAILURE, "printing submission filename pattern");
			execl("/usr/bin/find", "/usr/bin/find", submissions_path_prefix,
 				"-type", "f", "-name", namepat, "-execdir", "/bin/ls",
				"-1d", "{}", ";", NULL);
			//' | sort -k6 -k7 | column -t
			err(EXIT_FAILURE, "internal error: could not execl");
			assert(0);
		default:
			err(EXIT_FAILURE, "internal error: unknown mode %d", mode);
			assert(0);
		open_it:
			/* We drop the egid early, so that the file comes out
			 * with the user's gid. Then they can have read permission
			 * on their own submission. */
			ret = setegid(rgid);
			if (ret != 0) err(EXIT_FAILURE, "setegid(%ld)", (long) rgid);
			submfd = mkstemps(subpath, sizeof "." SUBMISSION_FORMAT_EXT - 1);
			if (ret == -1) err(EXIT_FAILURE, "opening submission "SUBMISSION_FORMAT_EXT" file %s", subpath);
			ret = fchmod(submfd, 0640);
			if (ret == -1) err(EXIT_FAILURE, "chmod'ing submission "SUBMISSION_FORMAT_EXT" file %s", subpath);
#if defined(SUBMISSION_FORMAT_TAR)
			ret = tar_fdopen(&submission_hdl, submfd, subpath, NULL /* tartype */,
				O_WRONLY, 0640, (mode == SUBMIT) ? TAR_VERBOSE : 0 /* for now */);
#else /* others are just a plain file */
			submission_hdl = fdopen(submfd, "w+");
#endif
			if (ret != 0) err(EXIT_FAILURE, "opening submission "SUBMISSION_FORMAT_EXT" file %s", subpath);
			/* if it's just a temporary, unlink it */
			if (mode == FEEDBACK) unlink(subpath);
			break;
	}
	/* We've now opened the audit file and submission file,
	 * and checked the submission deadline,
 	 * so we can drop privileges. */
	ret = seteuid(ruid);
	if (ret != 0) err(EXIT_FAILURE, "seteuid(%ld)", (long) ruid);

	/* Now we're the submitting user, so open their submission (the
	 * lecturer might not have permission). */
	const char *d = argv[2];
	char *real_d = realpath(d, NULL);
	/* We start audit-logging here. The realpath may have failed, so we may bail
	 * soon, but it's good to collect data about failed invocations. */
	audit_println("User %s initiated %s request on project %s, dir %s (really %s)",
		submitting_user,
		(mode == SUBMIT) ? "submission" : "feedback",
		argv[1] /* project number as a string */,
		d,
		real_d);
	atexit(audit_exit);
	if (!real_d) err(EXIT_FAILURE, USAGE_MSG "\nSomething fishy about the directory: %s",
		argv[0], d);

	size_t tmp_name_max = pathconf(d, _PC_NAME_MAX);
	if (tmp_name_max != -1) name_max = tmp_name_max; // else our guess stands

	if (num > NPROJECTS) errx(EXIT_FAILURE, "bad project number %u", num);

	/* We now read the user's submission using the user's privileges,
	 * and write it to the submission file. */
	DIR *the_d = opendir(d);
	if (!the_d) err(EXIT_FAILURE, "opening submission directory %s (really: %s)", d, real_d);

	/* Also chdir to it. */
	ret = chdir(d);
	if (ret != 0) err(EXIT_FAILURE, "couldn't chdir to submission directory %s (really: %s)", d, real_d);

#if defined(SUBMISSION_FORMAT_TAR)
	/* The check_sanity_arg is assumed to be the arg needed to grok the submission. */
	_Bool success = write_submission_tar(the_d, auditf, stderr, submission_hdl,
		(mode == SUBMIT) ? MAX_SUBMISSION_SIZE : MAX_FEEDBACK_SIZE, projects[num]->check_sanity_arg);
	if (!success) err(EXIT_FAILURE, "error writing tar from submission at %s (really: %s)", d, real_d);
#elif defined(SUBMISSION_FORMAT_GIT_DIFF)
	_Bool success = write_submission_git_diff(the_d, auditf, stderr, submission_hdl,
		(mode == SUBMIT) ? MAX_SUBMISSION_SIZE : MAX_FEEDBACK_SIZE, projects[num]->check_sanity_arg);
	if (!success) err(EXIT_FAILURE, "error writing git diff for submission at %s (really: %s)", d, real_d);
#else
#error "Unknown submission format"
#endif

	int subm_rd_fd = dup(submfd);
#ifdef SUBMISSION_FORMAT_TAR
	ret = tar_close(submission_hdl);
#else
	ret = fclose(submission_hdl);
#endif
	if (ret != 0) err(EXIT_FAILURE, "closing submission file");
	submission_hdl = NULL;
	/* Now re-open the submission from the same fd. */
	off_t o = lseek(subm_rd_fd, 0, SEEK_SET);
	if (o != 0) err(EXIT_FAILURE, "seeking back to start of submission file");

	/* Sanity-check the submission from the file. */
	errno = 0;
	success = projects[num]->check_sanity(the_d, auditf, stdout, subm_rd_fd,
		projects[num]->check_sanity_arg);
	if (!success)
	{
		// we don't accept insane submissions
		int saved_errno = errno;
		unlink(subpath);
		audit_println("Request failed for insanity");
		audit_success = 0;
		errno = saved_errno;
		((errno == 0) ? errx : err)(EXIT_FAILURE, "submission at %s (really: %s) found to be insane", d, real_d);
	}

	switch (mode)
	{
		case SUBMIT:
			success = projects[num]->finalise_submission(
				the_d, auditf, stdout, subm_rd_fd,
				projects[num]->finalise_submission_arg);
			if (!success) errx(EXIT_FAILURE, "failed to submit"); // exits
			audit_println("Request succeeded");
			audit_success = 1;
			fprintf(stderr, "Your submission was successful.\nIts identifier is %s\n"
				"To satisfy yourself that it was received, try doing:\n"
				"    ls -l %s\n"
				"To see exactly what was received, try doing:\n"
				"    less %s\n"
				"You should save the identifier somewhere so you can do these again later.\n"
				"Or do:\n"
				"    %s/lssub %d\n"
				"to list the identifiers of your submission(s) for this project.\n",
				basename(subpath), subpath, subpath, dirname(argv[0]), num); // BEWARE: may modify argv[0]!
			break;
		case FEEDBACK:
			/* We close the audit file early, to avoid hanging on to the
			 * lock. */
			audit_println("Delegating to write-feedback handling");
			fflush(auditf);
			flock(fileno(auditf), LOCK_UN);
			fclose(auditf);
			auditf = NULL;
			success = projects[num]->write_feedback(
				the_d, auditf, stdout, subm_rd_fd,
			        projects[num]->write_feedback_arg);
			if (!success)
			{
				errx(EXIT_FAILURE, "failed to write feedback for submission");
				// exits
			}
			//audit_println("Request succeeded");
			audit_success = 1;
			break;
		default: errx(EXIT_FAILURE, "BUG: should not reach here!"); break;
	}

	free(subpath);
	if (auditf)
	{
		fflush(auditf);
		flock(fileno(auditf), LOCK_UN);
		fclose(auditf);
	}
	closedir(the_d);
	if (real_d) free(real_d);
	return 0;
}
