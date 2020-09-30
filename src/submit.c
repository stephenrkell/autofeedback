#define _GNU_SOURCE /* for asprintf */
#include <sys/types.h>
#include <sys/file.h>
#include <sys/time.h>
#include <sys/wait.h>
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

#include <libtar.h>

#define stringify_(t) #t
#define stringify(t) stringify_(t)

const char submissions_path_prefix[] = "/courses/" stringify(MODULE) "/submissions/";
const char lecturer[] = stringify(LECTURER);

char *basename(const char *path);
#ifdef _LIBGEN_H
#error "Do not include libgen.h! We require GNU basename()"
#endif

const char usage[] =
"Usage: %s <n> <directory>\n"
"    where <n> is a project number in module" stringify(MODULE) "\n"
"    and <directory> contains your attempt at that project\n"
;

size_t name_max = 255; /* max filename length... we get it from pathconf() */

#define DESCR_LEN 80
struct project
{
	unsigned n;
	char descr[DESCR_LEN];
	_Bool (*check_sanity)(DIR *dir, FILE *outf);
	_Bool (*write_feedback)(DIR *dir, FILE *auditf, FILE *outf, int tarfd);
	_Bool (*finalise_submission)(DIR *dir, FILE *auditf, FILE *outf, int tarfd);
};
/* Ideally we would sanity-check these by qsorting them.
 * and making indices line up with 'n'. Can't see a
 * good way to do this, though. Unless... simply require
 * it to be done already in the sanity check? i.e. qsort
 * them, then check sanity, then bail if invariant broken. */

_Bool write_submission_tar(DIR *dir, FILE *auditf, FILE *outf, TAR *t)
{
	/* tar-append every top-level regular file, keeping count of size. */
	unsigned size = 0;
	off_t len = offsetof(struct dirent, d_name) + name_max + 1;
#ifdef USE_READDIR_R
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
		// is it a regular file?
		if (the_entry->d_type == DT_REG)
		{
			/* Recall: we're chdir'd to the submission dir, so rel paths are fine */
			tar_append_file(t, the_entry->d_name, the_entry->d_name);
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
	return 1;
}

static _Bool check_sanity_test(DIR *dir, FILE *outf)
{
	/* We are run with the invoking user's privileges, not the lecturer's.
	 * We simply sanity-check the submission, i.e. whether our feedback
	 * etc could possibly work. It's allowed to do nothing. Unlike the
	 * others, it runs before a tar file has been created, so it can
	 * do something like check whether the tar file would be too big. */

	return 1;
}
_Bool write_feedback_from_helper(const char *helper_filename, const char *helper_argv1,
	DIR *dir, FILE *auditf, FILE *outf, int tarfd)
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
		 * 3 (auxin)   -- the directory (not super-useful, but hey)
		 * 4 (auxout)  -- the audit log
		 */
		int ret = dup2(tarfd, 0);
		if (ret == -1) err(EXIT_FAILURE, "dup2 (1)");
		ret = dup2(fileno(outf), 1);
		if (ret == -1) err(EXIT_FAILURE, "dup2 (2)");
		ret = dup2(dirfd(dir), 3);
		if (ret == -1) err(EXIT_FAILURE, "dup2 (3)");
		ret = dup2(fileno(auditf), 4);
		if (ret == -1) err(EXIT_FAILURE, "dup2 (4)");

		/* We also weed the environment, to avoid the user's environment
		 * doing funky things that mess with our logic. We allow
		 * HOME and TERM, but set PATH and SHELL to sane defaults
		 * and LANG to C. */
		char *homestr = getenv("HOME");
		if (!homestr) errx(EXIT_FAILURE, "no home directory?");
		char *termstr = getenv("TERM");
		char *environ[] = {
			homestr - (sizeof "HOME=" - 1),
			"PATH=/usr/bin:/bin",
			"SHELL=/bin/sh",
			"LANG=C",
			termstr ? termstr : NULL,
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

	// should be unreachable
	assert(0);
}
static _Bool write_feedback_test(DIR *dir, FILE *auditf, FILE *outf, int tarfd)
{
	const char *helper_filename = "/courses/" stringify(MODULE) "/helpers/write-feedback";
	return write_feedback_from_helper(helper_filename, "1" /* we are project 1 */,
		dir, auditf, outf, tarfd);
}

static _Bool finalise_submission_test(DIR *dir, FILE *auditf, FILE *outf, int tarfd)
{
	/* By default, this does nothing. */
	return 1;
}

struct project projects[] = {
	[0] = {},
	[1] =  {
		1,
		"test project 1",
		check_sanity_test,
		write_feedback_test,
		finalise_submission_test
	}
};
#define NPROJECTS ((sizeof projects / sizeof projects[0]) - 1)

static void (__attribute__((constructor)) init_projects)(void)
{

}

/* Each project in our lib will define a 'struct project'.
 * These will be collated into an array at link time.
 * For now, use a dummy. */
extern struct project projects[];

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
	return ret;
}
#define audit_println(fmt, args...) audit_println_helper(fmt "\n", ##args)
/* To ensure we log any abnormal exits, even if done by err() or other
 * libc functions, we install an atexit function. */
_Bool audit_success;
void audit_exit(void)
{
	if (!audit_success) audit_println("Request failed");
}

int main(int argc, char **argv)
{
	enum { INVALID, SUBMIT, FEEDBACK } mode;
	if (0 == strcmp(basename(argv[0]), "submit")) mode = SUBMIT;
	else if (0 == strcmp(basename(argv[0]), "feedback")) mode = FEEDBACK;
	if (mode == INVALID)
	{
		errx(EXIT_FAILURE, "You must invoke this program as 'submit' or 'feedback'");
	}
	if (argc < 2) errx(EXIT_FAILURE, usage, argv[0]);
	unsigned num = atoi(argv[1]);
	if (num < 1 || num > 12) errx(EXIT_FAILURE, "invalid project number: %d", num);
	const char *d = argv[2];
	char *real_d = realpath(d, NULL);

	/* If we're doing a submission, we need a writable fd onto a tar
 	 * descriptor, and a writable fd only the activity log file. If
	 * we're doing feedback, we need only the latter. */

	/* Beware concurrency! If multiple users have the activity log
	 * file open, strange things could happen if we use non-atomic
	 * writes, or if our descriptor isn't kept pointing at the
	 * last byte. We should use file locking on the activity log file. */

	uid_t euid = geteuid();
	uid_t ruid = getuid();
	gid_t rgid = getgid();
	struct passwd pwbuf;
	struct passwd *pwret;

	size_t bufsize = sysconf(_SC_GETPW_R_SIZE_MAX);
	if (bufsize == -1) /* Value was indeterminate */
	{
		bufsize = 16384; /* Should be more than enough */
	}
	char buf[bufsize];
	pwret = NULL;
	errno = 0; // protocol for getpwuid_r
	int ret = getpwuid_r(euid, &pwbuf, buf, bufsize, &pwret);
	if (ret != 0) err(EXIT_FAILURE, "getpwuid_r");
	// fprintf(stderr, "Effective user is %s\n", pwret->pw_name);
	if (0 != strcmp(pwret->pw_name, lecturer))
	{
		err(EXIT_FAILURE, "internal error: bad lecturer name (%s, %s)",
			pwret->pw_name, lecturer);
	}
	pwret = NULL;
	errno = 0; // protocol for getpwuid_r
	ret = getpwuid_r(ruid, &pwbuf, buf, bufsize, &pwret);
	if (ret != 0) err(EXIT_FAILURE, "getpwuid_r");
	// fprintf(stderr, "Real user is %s\n", pwret->pw_name);
	size_t rname_len = strlen(pwret->pw_name);
	char submitting_user[1 + rname_len];
	memcpy(submitting_user, pwret->pw_name, 1 + rname_len);

	/* We want to open the submission and/or audit files
	 * as appropriate, then drop our privileges. */
	char *audit_path;
	ret = asprintf(&audit_path, "%s/%s", submissions_path_prefix, "audit.log");
	if (ret < 0) errx(EXIT_FAILURE, "printing audit file path");
	auditf = fopen(audit_path, "a");
	free(audit_path);
	if (!auditf) err(EXIT_FAILURE, "opening audit file");
	audit_println("User %s initiated %s request on %s", submitting_user,
		(mode == SUBMIT) ? "submission" : "feedback", real_d);
	atexit(audit_exit);
	ret = flock(fileno(auditf), LOCK_EX);
	if (ret != 0) err(EXIT_FAILURE, "locking audit file");
	int tarfd = -1;
	char *subpath;
	TAR *submission_t = NULL;
	switch (mode)
	{
		case SUBMIT:
			ret = asprintf(&subpath, "%s/%02d-%s-XXXXXX.tar",
				submissions_path_prefix, num, submitting_user);
			if (ret < 0) errx(EXIT_FAILURE, "printing submission path");
			goto open_it;
		case FEEDBACK:
			// hard-code "/tmp" for security reasons (don't trust TMPDIR)
			ret = asprintf(&subpath, "/tmp/XXXXXX.tar");
			if (ret < 0) errx(EXIT_FAILURE, "printing submission path");
			// fall through
			goto open_it;
		default:
			err(EXIT_FAILURE, "internal error: unknown mode %d", mode);
			assert(0);
		open_it:
			tarfd = mkstemps(subpath, sizeof ".tar" - 1);
			if (ret == -1) err(EXIT_FAILURE, "opening submission tar file %s", subpath);
			ret = tar_fdopen(&submission_t, tarfd, subpath, NULL /* tartype */,
				O_WRONLY, 0600, (mode == SUBMIT) ? TAR_VERBOSE : 0 /* for now */);
			if (ret != 0) err(EXIT_FAILURE, "tar-opening submission tar file %s", subpath);
			/* if it's just a temporary, unlink it */
			if (mode == FEEDBACK) unlink(subpath);
			free(subpath);
			break;
	}
	/* We've now opened the audit file and submission file,
 	 * so we can drop privileges. */
	ret = seteuid(ruid);
	if (ret != 0) err(EXIT_FAILURE, "seteuid(%ld)", (long) ruid);
	ret = setegid(rgid);
	if (ret != 0) err(EXIT_FAILURE, "setegid(%ld)", (long) rgid);

	size_t tmp_name_max = pathconf(d, _PC_NAME_MAX);
	if (tmp_name_max != -1) name_max = tmp_name_max; // else our guess stands

	if (num > NPROJECTS) errx(EXIT_FAILURE, "bad project number %u", num);

	/* We now read the user's submission using the user's privileges,
	 * and write it to the tar file. */
	DIR *the_d = opendir(d);
	if (!the_d) err(EXIT_FAILURE, "opening submission directory %s (really: %s)", d, real_d);

	/* Also chdir to it. */
	ret = chdir(d);
	if (ret != 0) err(EXIT_FAILURE, "couldn't chdir to submission directory %s (really: %s)", d, real_d);

	/* Sanity-check the submission. */
	_Bool success = projects[num].check_sanity(the_d, stderr);
	if (!success) err(EXIT_FAILURE, "submission at %s (really: %s) found to be insane", d, real_d);

	success = write_submission_tar(the_d, auditf, stderr, submission_t);
	if (!success) err(EXIT_FAILURE, "writing tar from submission at %s (really: %s)", d, real_d);

	int tar_rd_fd = dup(tarfd);
	ret = tar_close(submission_t);
	if (ret != 0) err(EXIT_FAILURE, "closing submission tar file");
	submission_t = NULL;

	/* Now re-open the tar from the same fd. */
	off_t o = lseek(tar_rd_fd, 0, SEEK_SET);
	if (o != 0) err(EXIT_FAILURE, "seeking back to start of submission tar file");

	success = ((mode == SUBMIT) ? projects[num].finalise_submission
		 : projects[num].write_feedback)(the_d, auditf, stderr, tar_rd_fd);

	if (!success) errx(EXIT_FAILURE, "failed to %s submission",
		(mode == SUBMIT) ? "submit" : "write feedback for");

	audit_println("Request succeeded");
	audit_success = 1;

	fflush(auditf);
	flock(fileno(auditf), LOCK_UN);
	fclose(auditf);
	closedir(the_d);
	if (real_d) free(real_d);
	return 0;
}
