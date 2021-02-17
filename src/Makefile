srcroot := $(realpath $(dir $(lastword $(MAKEFILE_LIST)))/..)
-include $(srcroot)/config.mk

default: submit feedback

MODULE ?= CO557
module ?= co557
LECTURER ?= srk21

CFLAGS += -DMODULE=$(module) -DLECTURER=$(LECTURER) -I../include -Wall

submit: LDFLAGS += -static
submit: LDFLAGS += -L$(srcroot)/lib$(module)
submit: LDFLAGS += -Wl,--whole-archive -l$(module) -Wl,--no-whole-archive
submit: LDLIBS += -ltar

CFLAGS += -g

# the final chmod is to stop students from copying the program then
# wondering why it doesn't work... sigh
submit: submit.c $(srcroot)/lib$(module)/lib$(module).a
	$(CC) -o $@ $< $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $(LDLIBS)
	chmod ug+s $@
	chmod o-r $@

feedback: submit
	ln -sf $< $@
