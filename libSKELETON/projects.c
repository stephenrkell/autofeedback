#define _GNU_SOURCE /* for asprintf */
#include <sys/types.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <dirent.h>
#include <errno.h>
#include <assert.h>
#include <string.h>
#include <err.h>

#include "project.h"

#ifndef MODULE
#error "MODULE must be defined"
#endif

static _Bool check_sanity_test(DIR *dir, FILE *auditf, FILE *outf, int tarfd, void *arg)
{
	/* We are run with the invoking user's privileges, not the lecturer's.
	 * We simply sanity-check the submission, i.e. whether our feedback
	 * etc could possibly work. It's allowed to do nothing. Unlike the
	 * others, it runs before a tar file has been created, so it can
	 * do something like check whether the tar file would be too big. */

	return 1;
}
static _Bool write_feedback_test(DIR *dir, FILE *auditf, FILE *outf, int tarfd, void *arg)
{
#define __helper_filename(m) \
		"/shared/" #m "/autofeedback/lib" #m "/scripts/write-feedback"
#define _helper_filename(m) __helper_filename(m)
	static const char helper_filename[] = _helper_filename(MODULE);
	return run_helper(helper_filename, (char*) arg,
		dir, auditf, outf, tarfd);
}

static _Bool finalise_submission_test(DIR *dir, FILE *auditf, FILE *outf, int tarfd, void *arg)
{
	/* By default, this does nothing. */
	return 1;
}

struct project test_project_one = {
	1,
	"test project 1",
	check_sanity_test,
	(void*) "abcdef1234567890abcdef1234567890abcdef12", /* FIXME: commit string */
	write_feedback_test,
	(void*) "1",
	finalise_submission_test,
	NULL
};
REGISTER_PROJECT(test_project_one);
