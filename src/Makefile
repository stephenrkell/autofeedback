# snarf the source directory
THIS_MAKEFILE := $(lastword $(MAKEFILE_LIST))
srcroot := $(realpath $(dir $(THIS_MAKEFILE))/..)

-include config.mk

default: submit feedback

# try to guess the module name from the build directory name
MODULE ?= $(shell echo $(notdir $(realpath .)) | tr a-z A-Z)
module ?= $(shell echo '$(MODULE)' | tr A-Z a-z)
LECTURER ?= '"$(shell id -un)"'
LECTURER_UID ?= $(shell id -u)
LECTURER_GID ?= $(shell id -g)
# Kent version
# SUBMISSIONS_PATH_PREFIX ?= /courses/$(MODULE)/submissions

SUBMISSIONS_PATH_PREFIX ?= /shared/$(MODULE)/submissions

$(info module is $(module))

CFLAGS += -DMODULE=$(module) -DMODULE_LOWER=$(module) -DMODULE_UPPER=$(MODULE) \
 -DLECTURER=$(LECTURER) -DLECTURER_UID=$(LECTURER_UID) -DLECTURER_GID=$(LECTURER_GID) \
 -DSUBMISSIONS_PATH_PREFIX="$(SUBMISSIONS_PATH_PREFIX)" \
 -I$(srcroot)/include -I$(srcroot)/librunt/include -Wall

submit: LDFLAGS += -static
submit: LDFLAGS += -L$(srcroot)/lib$(module)
submit: LDFLAGS += -Wl,--whole-archive -l$(module) -Wl,--no-whole-archive
submit: LDLIBS += -ltar

# the module lib dir may have a mk.inc
-include $(srcroot)/lib$(module)/mk.inc

CFLAGS += -g

vpath %.c $(srcroot)/src

ifeq ($(shell pwd),$(srcroot)/src)
$(info  *** You must build from a per-module directory using $(MAKE) -f)
$(error Cannot build 'submit' from 'src'; the binary differs for every module)
endif

# the final chmod is to stop students from copying the program then
# wondering why it doesn't work... sigh
submit: submit.c fake-getgrpw.c $(srcroot)/lib$(module)/lib$(module).a
	$(srcroot)/scripts/check-suidable.sh .
	$(CC) -o $@ $+ $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $(LDLIBS)
	chmod ug+s $@
	chmod o-r $@

feedback: submit
	ln -sf $< $@
