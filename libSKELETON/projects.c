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
		"/usr/l/courses/" #m "/autofeedback/lib" #m "/scripts/write-feedback"
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
	(void*) "6c72e548801c2512435a34bb1f2e03f8a7b10a17" /* InfOS commit string */,
	write_feedback_test,
	(void*) "1",
	finalise_submission_test,
	NULL
};
REGISTER_PROJECT(test_project_one);
struct project test_project_two = {
	2,
	"test project 2",
	check_sanity_test,
	(void*) "23a5901a3a1d115f996669f94781c8f97b5cf2e0" /* InfOS commit string */,
	write_feedback_test,
	(void*) "2",
	finalise_submission_test,
	NULL
};
REGISTER_PROJECT(test_project_two);
struct project test_project_three = {
	3,
	"test project 3",
	check_sanity_test,
	(void*)  "23a5901a3a1d115f996669f94781c8f97b5cf2e0" /* InfOS commit string */,
	write_feedback_test,
	(void*) "3",
	finalise_submission_test,
	NULL
};
REGISTER_PROJECT(test_project_three);
struct project test_project_four = {
	4,
	"test project 4",
	check_sanity_test,
	(void*)  "23a5901a3a1d115f996669f94781c8f97b5cf2e0" /* InfOS commit string */,
	write_feedback_test,
	(void*) "4",
	finalise_submission_test,
	NULL
};
REGISTER_PROJECT(test_project_four);
struct project test_project_five = {
	5,
	"test project 5",
	check_sanity_test,
	(void*)  "23a5901a3a1d115f996669f94781c8f97b5cf2e0" /* InfOS commit string */,
	write_feedback_test,
	(void*) "5",
	finalise_submission_test,
	NULL
};
REGISTER_PROJECT(test_project_five);
struct project test_project_six = {
	6,
	"test project 6",
	check_sanity_test,
	(void*)  "23a5901a3a1d115f996669f94781c8f97b5cf2e0" /* InfOS commit string */,
	write_feedback_test,
	(void*) "6",
	finalise_submission_test,
	NULL
};
REGISTER_PROJECT(test_project_six);
