THIS_MAKEFILE := $(lastword $(MAKEFILE_LIST))
scriptdir := $(dir $(realpath $(THIS_MAKEFILE)))
$(info scriptdir is $(scriptdir))

# we use bashisms
export SHELL := /bin/bash

# we need some helper functions
funcs := $(scriptdir)/funcs.sh
users := $(shell . $(funcs) && users)
$(info users is $(users))

SUBMISSIONS := /courses/co557/submissions

# keep intermediates
.SECONDARY:

# which projects are we marking?
projnums ?= 1 2 3

gates_1 := $(shell . $(funcs) && echo "$$proj1_gates")
gates_2 := $(shell . $(funcs) && echo "$$proj2_gates")
gates_3 := $(shell . $(funcs) && echo "$$proj3_gates")
gates_4 := $(shell . $(funcs) && echo "$$proj4_gates")
gates_5 := $(shell . $(funcs) && echo "$$proj5_gates")
gates := $(foreach p,$(projnums),$(gates_$(p)))

.PHONY: default
default: all-submissions all-automarks all-quiz all-reports all-eyeballs marks-plot.txt

# For each student we generate a report, summarising what we think they submitted
# and what marks they got for each gate etc.
%/report.txt: $(foreach p,$(projnums),%/path-to-submission-$(p)) \
 $(foreach p,$(projnums),%/automarks-$(p).tsv) \
 sanity-partial.tsv \
 $(wildcard quiz*+marks.tsv) # FIXME: don't use wildcards
	. $(funcs) && report $* $@ $(projnums) || (rm -f $@; false)

# This is our mechanism for adjusting students' marks.
# It records a delta to the automark.
# It's called "sanity-partial" because the brief says there
# is one mark for 'sanity' e.g. for not using a totally insane solution
# that is nevertheless functionally correct. In practice this is marked
# negatively; we eyeball all solutions and deduct the sanity mark if needed,
# otherwise it is deemed to be awarded. (I THINK. CHECK this.)
# The 'apply-adj' function in funcs.sh takes care of this, called when
# the report is being generated (by report()).
sanity-partial.tsv:
	touch $@

report-%.txt: %/report.txt
	ln -sf $< $@

.PHONY: all-reports
all-reports: $(foreach u,$(users),report-$(u).txt $(u)/report.txt)

marks.tsv: all-reports
	for f in */report.txt; do \
            u="$$( dirname "$$f" | sed 's^/$$^^' )"; \
            mark="$$( sed -nr '/Grand total.*: ([0-9]+)/ {s//\1/;p}' "$$f" )"; \
            read surname initials_reversed <<<"$$( finger "$$u" | \
                  sed -r 's/[A-Z][a-z]+:/\n&/g' | sed -nr '/^Name: / {s///;p}' | \
                  tr '.' '\n' | tac | tr '\n' '\t' )"; \
            initials="$$( echo "$$initials_reversed" | tr '\t' '\n' | tac | tr -d '\n' )"; \
            echo "$$surname"$$'\t'"$$initials"$$'\t'"$$u"$$'\t'$$mark; \
        done > $@ || (rm -f $@; false)

# Preparing the marks for SDS... we calculate percentages using 'total',
# so make sure (below) that this is passed as the correct total# marks for the project.
# FIXME: funcs.sh also hard-codes per-project totals, in report()
define sds-rules
	total=$(1); (echo $$'surname,initials,login,rawmark/'"$$total"',%unrounded,%rounded'; \
        cat $< | while IFS=$$'\t' read surname initials login mark; do \
             echo -n "$$surname","$$initials","$$login","$$mark",; \
             echo "$$mark" | awk "{ print (100 * \$$0 / $$total) }" | tr -d '\n'; \
             echo -n ','; \
             echo "$$mark" | awk "{ printf(\"%3.0f\\n\" , (100 * \$$0 / $$total)) }" | tr -cd '0-9'; \
             echo; \
        done | sort) > $@ || (rm -f $@; false)
endef

a1-marks-for-sds.csv: marks.tsv
ifneq ($(projnums),1 2 3)
	false # This isn't project 1!
endif	
	$(call sds-rules,130)
	
a2-marks-for-sds.csv: marks.tsv
ifneq ($(projnums),4 5)
	false # This isn't project 2!
endif	
	$(call sds-rules,70)

# It's useful to see the distribution of mark frequency.
marks-plot.txt: marks.tsv
	declare -a mark_freq; \
        max_mark=0; \
        while read surname initials u mark; do \
            current_freq=$${mark_freq[$$mark]} \
            mark_freq[$$mark]=$$(( $${current_freq:-0} + 1 )); \
            if [[ $$mark -gt $$max_mark ]]; then max_mark=$$mark; fi \
        done < $<; \
        for n in `seq 0 $$max_mark`; do \
             awk "BEGIN{ printf(\"% 4d \", $$n); exit(0) }"; \
             if [[ $${mark_freq[$$n]} -gt 0 ]]; then \
                 for i in `seq 1 $${mark_freq[$$n]}`; do /bin/echo -n '@'; done; \
             fi; \
             echo; \
        done > $@
# if the user hasn't submitted, we should get an empty file but success
define path-to-submission-commands
mkdir -p $* && chmod 0700 $* && setfacl -m u:$*:x $* && setfacl -m m:x $* && setfacl -m g:csstaff:rx $*
	. $(funcs) && submission_for_user $* $(1) | cut -f3 > $@ || (rm -f $@; false)
endef
%/path-to-submission-1:
	$(call path-to-submission-commands,1)
%/path-to-submission-2:
	$(call path-to-submission-commands,2)
%/path-to-submission-3:
	$(call path-to-submission-commands,3)
%/path-to-submission-4:
	$(call path-to-submission-commands,4)
%/path-to-submission-5:
	$(call path-to-submission-commands,5)

# To speed things up,
# we cache the results of running the automated tests on each submission.
# If the submission is changed, this will be regenerated.

# NOTE: feedback is done on a doctored version of the submission,
# to correct common non-errors for which the feedback program is too
# conservative: wrong-cased gates/filenames and absence of the
# a/ + b/ directory split in project 3.
# See funcs.sh mention of 'fixup'.
# FIXME: submission 4 is different, but it shouldn't be.
# For the others, the feedback file is made by calling the feedback
# program, and then the automarker reads that feedback file.
# For project 4, the automarker needs to actively probe the submission.
# Similarly for project 5, the automarker actively probes but
# the feedback program's output is nevertheless sufficient.
# FIXME: if possible, clean this up so that 'feedback' always
# means simply "automarking without output".
# Though HMM, I'm not so sure this is a great idea... it may give
# away too much.
define testcache-commands
f="$$(cat "$<")" && . $(funcs) && test_submission_dir $(1) $*/submission-$(1) > $@ 2>&1 || (rm -f $@; false)
endef
%/submission-1-testcache: %/submission-1.stamp
	$(call testcache-commands,1)
%/submission-2-testcache: %/submission-2.stamp
	$(call testcache-commands,2)
%/submission-3-testcache: %/submission-3.stamp
	$(call testcache-commands,3)
%/submission-4-testcache: %/submission-4.stamp
	$(call testcache-commands,4)
%/submission-5-testcache: %/submission-5.stamp
	$(call testcache-commands,5)

define submission-commands
! test -s $< || (mkdir -p $*/submission-$(1) && f="$$(cat "$<")" && \
	  cd $*/submission-$(1) && rm -rf * && tar -xf "$(SUBMISSIONS)/$$f" && \
	  . $(funcs) && fixup_extracted $(1) `pwd` )
	touch $@
endef
%/submission-1.stamp: %/path-to-submission-1
	$(call submission-commands,1)
%/submission-2.stamp: %/path-to-submission-2
	$(call submission-commands,2)
%/submission-3.stamp: %/path-to-submission-3
	$(call submission-commands,3)
%/submission-4.stamp: %/path-to-submission-4
	$(call submission-commands,4)
%/submission-5.stamp: %/path-to-submission-5
	$(call submission-commands,5)

.PHONY: all-submissions
all-submissions: $(foreach n,$(projnums),$(foreach u,$(users),$(u)/submission-$(n).stamp))

.PHONY: all-feedback
all-feedback: $(foreach n,$(projnums),$(foreach u,$(users),$(u)/submission-$(n)-feedback))

# We use 'setfacl' to give students access to the detailed feedback
# on their submission, i.e. the autoamted test results as seen by
# the automarking system.
define automark-funcs
. $(funcs) && \
	automark "$*" $(1) "$$(cat $*/path-to-submission-$(1) || \
	    echo NO_SUBMISSION)" 2>$*/submission-$(1)-feedback | \
            cut -f2-  > $@  || (rm -f $@; false)
	setfacl -m u:$*:r $*/submission-$(1)-feedback
	setfacl -m g:csstaff:r $*/submission-$(1)-feedback
endef
%/automarks-1.tsv: %/submission-1.stamp
	$(call automark-funcs,1)
%/automarks-2.tsv: %/submission-2.stamp
	$(call automark-funcs,2)
%/automarks-3.tsv: %/submission-3.stamp
	$(call automark-funcs,3)
%/automarks-5.tsv: %/submission-5.stamp
	$(call automark-funcs,5)
#%/submission-4-feedback: %/path-to-submission-4  # HACK: unify this with the other approach
#	f="$$(cat "$<")" && . $(funcs) && automark_proj4 $* `readlink -f ../"$$f"` $(1) > $@ 2>&1 || (rm -f $@; false)
%/automarks-4.tsv: %/submission-4.stamp
	. $(funcs) && \
             automark "$*" 4 "$$(cat $*/path-to-submission-4 || \
                echo NO_SUBMISSION)" 2>$*/submission-4-feedback | \
             cut -f2-  > $@  || (rm -f $@; false)
	setfacl -m u:$*:r $*/submission-4-feedback
	setfacl -m g:csstaff:r $*/submission-4-feedback

define automarks-summary-commands
   for f in $+; do \
     dir="$$( dirname "$$f" | sed 's^/$$^^' )"; \
     echo -n "$$dir"$$'\t'; \
     cat "$$f"; \
   done > $@ || (rm -f $@; false)
endef
automarks-1.tsv: $(foreach u,$(users),$(u)/automarks-1.tsv)
	$(automarks-summary-commands)
automarks-2.tsv: $(foreach u,$(users),$(u)/automarks-2.tsv)
	$(automarks-summary-commands)
automarks-3.tsv: $(foreach u,$(users),$(u)/automarks-3.tsv)
	$(automarks-summary-commands)
#$(info submission 4 automarks we need: $(foreach u,$(users),$(u)/automarks-4.tsv))
automarks-4.tsv: $(foreach u,$(users),$(u)/automarks-4.tsv)
	$(automarks-summary-commands)
automarks-5.tsv: $(foreach u,$(users),$(u)/automarks-5.tsv)
	$(automarks-summary-commands)

.PHONY: all-automarks
all-automarks: $(foreach n,$(projnums),automarks-$(n).tsv) \
   $(foreach n,$(projnums),$(foreach u,$(users),$(u)/automarks-$(n).tsv))

# We build an 'eyeball' file designed for scrolling through
# all submissions of the same gate/sub-project quickly,
# to detect any fishy solutions e.g. plagiarism, cribbed-from-online
# things. The files embed vt100 escape codes (use 'less -R')
# to preserve the red highlighting that the feedback/automarker generates.
define eyeball-commands
for sub in $+; do \
   u=$$(dirname $$sub); \
   gate=$*; \
   read $(gates_$(1)) <<< "$$( cat "$$u"/automarks-$(1).tsv | cut -f3- )"; \
   echo -n ">>>>>>>>>>"; \
   echo -n " " $* "$$u" `cat "$$u"/path-to-submission-$(1)`; \
   automark=$${$*}; \
   echo " (automark: $$automark) <<<<<<<<<<"; \
   (cd $$u/submission-$(1) 2>&3 && find -iname "$*.hdl" -print0 | xargs -r -0 grep -H '^' ) 3>&1; \
   if [[ $$automark -eq 0 ]]; then cat $$u/submission-$(1)-feedback | sed -rn \
      "/^=== TESTING: $${gate} /,/^===/ p" | head -n-1; fi; \
done > "$@" || (rm -f $@; false)
endef
$(foreach g,$(gates_1),eyeball-$(g)): eyeball-%: $(foreach u,$(users),$(u)/automarks-1.tsv) | all-submissions
	$(call eyeball-commands,1)
$(foreach g,$(gates_2),eyeball-$(g)): eyeball-%: $(foreach u,$(users),$(u)/automarks-2.tsv) | all-submissions
	$(call eyeball-commands,2)
$(foreach g,$(gates_3),eyeball-$(g)): eyeball-%: $(foreach u,$(users),$(u)/automarks-3.tsv) | all-submissions
	$(call eyeball-commands,3)
$(foreach g,$(gates_5),eyeball-$(g)): eyeball-%: $(foreach u,$(users),$(u)/automarks-4.tsv) | all-submissions
	$(call eyeball-commands,5)

define eyeball-proj4-commands
for sub in $+; do \
   u=$$(dirname $$sub); \
   prog=$*; \
   read div toggle <<< "$$( cat "$$u"/automarks-4.tsv | cut -f3- )"; \
   echo -n ">>>>>>>>>>"; \
   echo -n " " $* "$$u" `cat "$$u"/path-to-submission-4`; \
   automark=$${$*}; \
   echo " (automark: $$automark) <<<<<<<<<<"; \
   (cd $$u/submission-4 2>&3 && find -iname "$*.asm" -print0 | xargs -r -0 grep -H '^' ) 3>&1; \
   if [[ $$automark -eq 0 ]]; then cat $$u/submission-4-feedback | sed -rn \
      "/^=== TESTING: $${gate} /,/^===/ p" | head -n-1; fi; \
done > "$@" || (rm -f $@; false)
endef
eyeball-div eyeball-toggle: eyeball-%: $(foreach u,$(users),$(u)/automarks-4.tsv) | all-submissions
	$(eyeball-proj4-commands)

.PHONY: maybe-proj4-eyeballs
maybe-proj4-eyeballs: $(if $(filter 4,$(projnums)),eyeball-div eyeball-toggle,)
	true

.PHONY: all-eyeballs
all-eyeballs: $(foreach p,$(projnums),$(foreach g,$(gates_$(p)),eyeball-$(g))) maybe-proj4-eyeballs

#            echo -n "$${u}"$$'\t'"$${n}"$$'\t'"$$( basename "$${f}" )"$$'\t'"$${hint}"$$'\t\t' \
#                >> "$$start_d"/quiz-$${n}-$${q}.tsv

# Quiz questions are supposed to be answered in files with names like 'q1.txt'.
# Many students get this wrong so there was some manual fixing up I think.
# We collect the answers into per-question spreadsheets for rapid manual marking.
# If it says MULTIPLE it means they submitted more than one file with the relevant name,
# in different directories of their submission, so I had to dig into these by hand.
define quiz-autoextract-commands
n=$(1); q=$(2); u="$$( dirname "$@" | sed 's^/$$^^' )"; d="$$u"/submission-$${n}; \
    found="$$( find "$$d" -iname "q*$${q}.txt" 2>/dev/null )"; \
    if [[ -z "$$found" ]]; then \
        echo "NS"; \
    else case "$$( echo "$$found" | wc -l )" in \
        ('') \
            echo "Some problem" 1>&2 \
        ;; \
        (1) \
            (cat "$$found" | tr '\n' '\f' | tr -d '\r' | sed 's/\f/\\n/g'; echo) \
        ;; \
        (*) echo "MULTIPLE" \
        ;; \
    esac; fi > "$@" || (rm -f "$@"; false)
endef
#%/quiz-1-1-autoextracted.tsv: %/path-to-submission-1 %/submission-1.stamp

$(foreach q,1 2 3,%/quiz-1-$(q)-autoextracted.tsv): %/path-to-submission-1 %/submission-1.stamp
	$(call quiz-autoextract-commands,1,$(patsubst $*/quiz-1-%-autoextracted.tsv,%,$@))
$(foreach q,1 2 3,%/quiz-2-$(q)-autoextracted.tsv): %/path-to-submission-2 %/submission-2.stamp
	$(call quiz-autoextract-commands,2,$(patsubst $*/quiz-2-%-autoextracted.tsv,%,$@))
$(foreach q,1 2 3,%/quiz-3-$(q)-autoextracted.tsv): %/path-to-submission-3 %/submission-3.stamp
	$(call quiz-autoextract-commands,3,$(patsubst $*/quiz-3-%-autoextracted.tsv,%,$@))
$(foreach q,1 2 3,%/quiz-4-$(q)-autoextracted.tsv): %/path-to-submission-4 %/submission-4.stamp
	$(call quiz-autoextract-commands,4,$(patsubst $*/quiz-4-%-autoextracted.tsv,%,$@))
$(foreach q,1 2 3,%/quiz-5-$(q)-autoextracted.tsv): %/path-to-submission-5 %/submission-5.stamp
	$(call quiz-autoextract-commands,5,$(patsubst $*/quiz-5-%-autoextracted.tsv,%,$@))

# For project 3 question 3, we precalculate the 'correct answer' which is
# particular to the student's submission. This becomes
# the 'hint' field in the summary sheet. Very few people got this right.
define quiz-summary-commands
n=$(1); q=$(2); \
(echo $$'user\tproj\tfile\thint\tmark\tanswer'; \
for f in $+; do \
u="$$( dirname "$$f" | sed 's^/$$^^' )"; d="$$u"/submission-$${n}; \
case "$$n"-"$$q" in \
(3-3) \
    hint="$$( find "$$d" -iname '*.hdl' -print0 | xargs -r -0 stat -c'%s' | \
       awk 'BEGIN { count=0; } { count += $$0 } END { print (100 * count / 16384) }' )" \
;; \
(*) \
    hint="" \
;; \
esac; \
echo -n "$${u}"$$'\t'"$${n}"$$'\t'"$$( basename "$$( cat "$$( dirname "$${f}" )/path-to-submission-$${n}" )" )"$$'\t'"$${hint}"$$'\t\t'; \
cat $$f; \
done) > $@ || (rm -f $@; false) #)
endef

quiz-1-%.tsv: $(foreach u,$(users),$(u)/quiz-1-%-autoextracted.tsv)
	$(call quiz-summary-commands,1,$*)
quiz-2-%.tsv: $(foreach u,$(users),$(u)/quiz-2-%-autoextracted.tsv)
	$(call quiz-summary-commands,2,$*)
quiz-3-%.tsv: $(foreach u,$(users),$(u)/quiz-3-%-autoextracted.tsv)
	$(call quiz-summary-commands,3,$*)
quiz-4-%.tsv: $(foreach u,$(users),$(u)/quiz-4-%-autoextracted.tsv)
	$(call quiz-summary-commands,4,$*)
quiz-5-%.tsv: $(foreach u,$(users),$(u)/quiz-5-%-autoextracted.tsv)
	$(call quiz-summary-commands,5,$*)

.PHONY: all-quiz
all-quiz: $(foreach n,$(projnums),$(foreach q,1 2 3,quiz-$(n)-$(q).tsv))

# I record quiz marks in a file whose name ends with +marks.tsv,
# to avoid danger of clobbering the manual marking effort if I regenerate
# the collated-per-question tsv files.
# If I needed to regenerate them, e.g. after fixing a student's submission
# that had been pointing at the wrong version of their work or whatever,
# the following diff was useful to copy across any newly discovered attempts
# from the generated file to the actual 'live' manually-edited +marks.tsv file.
.PHONY: quiz-check-new-autoextracted
quiz-check-new-autoextracted:
	@echo "Check the following 'auto' vs 'marked' diffs for answers"
	@echo "that appear in the (-)auto version but not the (+)marked."
	@for n in `seq $(projnums)`; do for q in `seq 1 3`; do \
            echo "Project $$n Q$$q"; \
            diff -u <( cat quiz-$$n-$$q.tsv | cut -f1-3,6 | tr -d '"' ) \
                    <( cat quiz-$$n-$$q+marks.tsv | cut -f1-3,6 | tr -d '"' )| cut -c1-90; \
        done; done
