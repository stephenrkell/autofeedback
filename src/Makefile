# snarf the source directory
THIS_MAKEFILE := $(lastword $(MAKEFILE_LIST))
srcroot := $(realpath $(dir $(THIS_MAKEFILE))/..)

-include config.mk

default: submit feedback

# try to guess the module name from the build directory name
MODULE ?= $(shell echo $(notdir $(realpath .)) | tr a-z A-Z)
module ?= $(shell echo '$(MODULE)' | tr A-Z a-z)
LECTURER ?= $(shell whoami)

CFLAGS += -DMODULE=$(module) -DLECTURER=$(LECTURER) -I$(srcroot)/include -Wall

submit: LDFLAGS += -static
submit: LDFLAGS += -L$(srcroot)/lib$(module)
submit: LDFLAGS += -Wl,--whole-archive -l$(module) -Wl,--no-whole-archive
submit: LDLIBS += -ltar

CFLAGS += -g

vpath %.c $(srcroot)/src

# the final chmod is to stop students from copying the program then
# wondering why it doesn't work... sigh
submit: submit.c $(srcroot)/lib$(module)/lib$(module).a
	$(srcroot)/scripts/check-suidable.sh .
	$(CC) -o $@ $< $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $(LDLIBS)
	chmod ug+s $@
	chmod o-r $@

feedback: submit
	ln -sf $< $@
