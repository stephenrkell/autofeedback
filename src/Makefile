srcroot := $(realpath $(dir $(lastword $(MAKEFILE_LIST)))/..)

default: submit feedback

MODULE ?= co557
LECTURER ?= srk21

CFLAGS += -DMODULE=$(MODULE) -DLECTURER=$(LECTURER) -I../include

submit: LDFLAGS += -static
submit: LDFLAGS += -L$(srcroot)/lib$(MODULE)
submit: LDFLAGS += -Wl,--whole-archive -l$(MODULE) -Wl,--no-whole-archive
submit: LDLIBS += -ltar

CFLAGS += -g

submit: submit.c
	$(CC) -o $@ $< $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $(LDLIBS)
	chmod ug+s $@

feedback: submit
	ln -sf $< $@
