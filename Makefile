THIS_MAKEFILE := $(lastword $(MAKEFILE_LIST))

.PHONY: default src origin-lib

ifeq ($(dir $(realpath $(THIS_MAKEFILE))),$(realpath $(shell pwd))/)
$(info *** Building per-module libraries only)
$(info *** To build submit/feedback programs, use $(MAKE) -f from a module-specific dir)
default: origin-lib
else
default: src
endif

# we build 'submit' in pwd... CHECK it can handle setuid
src: origin-lib
	$(dir $(THIS_MAKEFILE))/scripts/check-suidable.sh .
	$(MAKE) -f $(dir $(THIS_MAKEFILE))/src/Makefile

# ... but the lib in place
origin-lib:
	for d in $(wildcard $(dir $(THIS_MAKEFILE))lib*[a-z]*[0-9]*); do \
            $(MAKE) -C $$d \
                MODULE="$$( echo "$$d" | sed 's/.*lib//' | tr a-z A-Z )" \
                module="$$( echo "$$d" | sed 's/.*lib//' | tr A-Z a-z )"; \
        done
