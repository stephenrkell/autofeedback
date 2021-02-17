include config.mk

module := $(shell echo "$(MODULE)" | tr 'A-Z' 'a-z' )

.PHONY: default src lib

default: src lib

src: lib
	$(MAKE) -C src

lib:
	$(MAKE) -C lib$(module)
