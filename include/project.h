#ifndef AUTOFEEDBACK_PROJECT_H_
#define AUTOFEEDBACK_PROJECT_H_

#include <stdio.h>

#define DESCR_LEN 80
struct project
{
	unsigned n;
	char descr[DESCR_LEN];
	_Bool (*check_sanity)(DIR *dir, FILE *outf, void *arg);
	void *check_sanity_arg;
	_Bool (*write_feedback)(DIR *dir, FILE *auditf, FILE *outf, int tarfd, void *arg);
	void *write_feedback_arg;
	_Bool (*finalise_submission)(DIR *dir, FILE *auditf, FILE *outf, int tarfd, void *arg);
	void *finalise_submission_arg;
};

/* Magic for making it possible to drop in projects at link time.
 * We use a printable section name _data_projectptrs so that we
 * can get the linker-defined symbols __{start,stop}__data_projectptrs. */
#define REGISTER_PROJECT(obj) \
__asm__(".pushsection _data_projectptrs, \"aw\", @progbits\n" \
        ".quad " #obj "\n"\
        ".popsection\n");

_Bool write_feedback_from_helper(const char *helper_filename, const char *helper_argv1,
	DIR *dir, FILE *auditf, FILE *outf, int tarfd);


#endif
