# include the autofeedback includes
CFLAGS += -I../include

THIS_MAKEFILE := $(lastword $(MAKEFILE_LIST))
dir := $(dir $(realpath $(THIS_MAKEFILE)))
module ?= $(shell echo "$(dir)" | sed -rn '/lib([A-Za-z][A-Za-z][0-9]{3})/ {s//\L\1\E/;p}' )

-include $(dir)/../config.mk

ifeq ($(module),)
$(error Could not infer module from directory name '$(dir)' nor read from ../config.mk)
endif
$(info module is $(module))

CFLAGS += -DMODULE=$(module)

lib$(module).a: projects.o
	$(AR) r $@  $+
