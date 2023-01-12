#include <stdio.h>
#include <sys/types.h>
#include <grp.h>
#include <pwd.h>
#include <assert.h>
#include <errno.h>
#include <string.h>

/* This minimalist fake implementation of get{gr,pw}{nam,[ug]id}
 *
 * We define two fake group and passwd entries -- one for the
 * owner, one for the caller (we are a setuid program).
 *
 * We need to fill in the caller's values when we start up.
 */

struct passwd owner_pw;
struct passwd caller_pw;
struct group owner_gr;
struct group caller_gr;
extern char *submitting_user;
char *owner_gr_members[] = { LECTURER, NULL };
char *caller_gr_members[2] = { NULL, NULL };
extern gid_t rgid;
extern uid_t ruid;

_Bool done_init;
static void init(void)
{
	owner_pw = (struct passwd) {
		.pw_name = LECTURER,
		.pw_passwd = "XXXXXX",
		.pw_uid = LECTURER_UID,
		.pw_gid = LECTURER_GID,
		.pw_gecos = NULL, // hope these are not needed
		.pw_dir = NULL,
		.pw_shell = NULL
	};
	caller_pw = (struct passwd) {
		.pw_name = submitting_user,
		.pw_passwd = "XXXXXX",
		.pw_uid = ruid,
		.pw_gid = rgid,
		.pw_gecos = NULL, // hope these are not needed
		.pw_dir = NULL,
		.pw_shell = NULL
	};
	owner_gr = (struct group) {
		.gr_name = LECTURER,        /* group name -- assume it's same as lecturer name */
		.gr_passwd = "XXXXXX",
		.gr_gid = LECTURER_GID,
		.gr_mem = owner_gr_members
	};
	caller_gr_members[0] = submitting_user;
	caller_gr = (struct group) {
		.gr_name = submitting_user,        /* group name -- assume it's same as user name */
		.gr_passwd = "XXXXXX",
		.gr_gid = rgid,
		.gr_mem = caller_gr_members
	};
	done_init = 1;
	assert(caller_gr.gr_name);
	assert(caller_gr.gr_gid);
	assert(caller_pw.pw_uid);
}

struct group *getgrnam(const char *name)
{
	if (!done_init) init();
	if (0 == strcmp(name, owner_gr_members[0])) return &owner_gr;
	else if (0 == strcmp(name, caller_gr_members[0])) return &caller_gr;
	else { errno = EINVAL; return NULL; }
}
struct passwd *getpwnam(const char *name)
{
	if (!done_init) init();
	if (0 == strcmp(name, LECTURER)) return &owner_pw;
	else if (0 == strcmp(name, submitting_user)) return &caller_pw;
	else { errno = EINVAL; return NULL; }
}
struct group *getgrgid(gid_t gid)
{
	if (!done_init) init();
	if (gid == owner_gr.gr_gid) return &owner_gr;
	else if (gid == caller_gr.gr_gid) return &caller_gr;
	else { errno = EINVAL; return NULL; }
}
struct passwd *getpwuid(uid_t uid)
{
	if (!done_init) init();
	if (uid == owner_pw.pw_uid) return &owner_pw;
	else if (uid == caller_pw.pw_uid) return &caller_pw;
	else { errno = EINVAL; return NULL; }
}
