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
#include "co557.h"

static _Bool check_sanity_test(DIR *dir, FILE *auditf, FILE *outf, int tarfd, void *arg)
{
	return 1;
}
static _Bool write_feedback_test(DIR *dir, FILE *auditf, FILE *outf, int tarfd, void *arg)
{
	static const char helper_filename[] = _helper_filename(write-feedback);
	return run_helper(helper_filename, (char*) arg,
		dir, auditf, outf, tarfd);
}

static _Bool finalise_submission_test(DIR *dir, FILE *auditf, FILE *outf, int tarfd, void *arg)
{
	/* By default, this does nothing. */
	return 1;
}

struct project test_project_four = {
	4,
	"test project 4",
	check_sanity_test,
	NULL,
	write_feedback_test,
	(void*) "4",
	finalise_submission_test,
	NULL
};
REGISTER_PROJECT(test_project_four);
