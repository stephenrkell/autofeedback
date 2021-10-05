#!/bin/bash

# source the generic autofeedback scripts first, which
# we assume are in ../../scripts

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" )" )"/../../scripts/funcs.sh

# The submission dir is where tarballs are placed.
# Students should not have read permissions on it, because the tarball is written
# by our setuid 'submit' binary (built from autofeedback sources).
# However, we give then a confirmation string that is the filename of their
# submission, so they *should* have traversal permission (x) -- this lets them
# check that their submission is recorded, but not to see/probe other students'
# submissions. Also we store the generated feedback/report files under submissions/
# and again the students should be able to traverse to reach those.
#
# The directory should also include a 'deadline-$n' file for each project number n.
# The deadline is the modification timestamp of the file (use 'touch -d').
# A specific student can be given a personalised deadline by also creating
# a file 'deadline-$n-$login'.
dir=/courses/co557/submissions

# We change our cwd during the course of some functions in this script, but
# we remember where we started.
start_d="$(pwd)"
echo "Start dir is $start_d" 1>&2

# Mostly we use the 8for16 version... proj5 will override this (see below)
SW=/courses/co557/nand2tetris-2.6-8for16
# FIXME: to use the 2.5.7-derived version on stephenrkell's GitHub, need to check out
# the srk8for16 branch, build it, and instead point SW at the InstallDir within.
# At the time of writing this, there has been only a binary release of 2.6 but not
# a source release, hence why the source is on 2.5.7. I think I made the nand2tetris-2.6-8for16
# by copying the .class files built with 2.5.7, but I'm not aware of any reason not to
# stick with just using 2.5.7 (but can't be sure...)
# FIXME: see also automark_proj5_partial_credit. We set TOOLS to the 'srktools' branch
# and use that. Can't remember why we call that TOOLS not SW.
# FIXME: we also have 'hacktools' which is a separate dir, hard-coded below... sigh.
# It contains Stephen's freestanding tools (currently just a parser) for the .hdl
# language.

# I use both my staff login and a test student-like login (from IS) to test this thing,
# but don't want to mark/record submissions by those users.
ignore_users_regexp='^(srk21|sk831)$'
users () {
    cd "$dir" && ls | tr '-' '\t' | cut -f2 | egrep -v "$ignore_users_regexp" | \
   sort | uniq | egrep -v '^audit\.log|^[0-9]'
}

# One of the first targets built by the makefile is $user/path-to-submission-* which
# writes to a small text file the pathname of the user's submission tarball that is
# to be marked. This function is how we make those files. It looks for the most recent
# non-empty submission that is not newer than the relevant deadline file.
#
# Note that in practice, some students will screw things up and their most recent
# submission won't be the best one to mark. In that case, manually overwrite the
# path-to-submission-* file (and re-run make).
initial_submission_for_user () {
    cd "$dir"
    local u="$1"
    local n="$2"
    test -n "$n" || return 1
    local latest_f=""
    local files=""
    deadline_file=deadline-$n-$u
    if ! [[ -e "$deadline_file" ]]; then
        deadline_file=deadline-$n
    fi
    files="$( find -name "0${n}-${u}-*.tar" -type f ! -size 0 2>/dev/null | xargs -r ls -t )"
    if [[ -z "$files" ]]; then
       echo "$u has not submitted anything for project $n" 1>&2
       return 1
    fi
    while read f; do
        if ! [[ "$( readlink -f "$f" )" -nt "$deadline_file" ]] && \
             [[ "$( stat -c"%s" "$f" )"0 -gt 0 ]] && \
             [[ -z "$latest_f" ]]; then
           latest_f="$f"
        fi
    done<<<"$files"
    if [[ -z "$latest_f" ]]; then
        echo "$u submitted something for project $n but only after [their] deadline" 1>&2
        return 1
    fi
    echo -e "$u\t$n\t$latest_f"
}

# This just reads the path-to-submission-* file.
submission_for_user () {
    cd "$dir"
    local u="$1"
    local n="$2"
    test -n "$n" || return 1
    if ! [[ -s "$start_d"/"$u"/path-to-submission-"$n" ]]; then
       echo "$u has not submitted anything for project $n" 1>&2
       return 1
    fi
    echo -e "$u\t$n\t$(cat "$start_d"/"$u"/path-to-submission-"$n")"
}

# It's good to get a summary of which submission files have been manually overridden.
submissions_differing_from_initial_submissions () {
    diff -u <( for n in $@; do for u in `users`; do initial_submission_for_user "$u" "$n"; done; done ) \
            <( for n in $@; do for u in `users`; do submission_for_user "$u" "$n"; done; done )
}

# It's handy to get a list of all submissions.
list_submissions () {

for n in $@; do
for u in `users`; do
    submission_for_user "$u" "$n"
done
done

}

# When printing feedback, we
# use some VT100/ANSI escape magic to do red+bold writing on the given line
lines_with_highlight_at () {
   (cat ; echo "(end of file)") | cat -n | \
    sed "$1 s/.*/\x1b[31m\x1b[1m&\x1b[0m/"
}

# Nasty function to print just the Nth line of a given file
line_n () {
    tail -n+$1 | head -n1 | tr -d '\n'; echo
}

#declare -A subs_by_user
#while read u n f; do
#    subs_by_user["$n$u"]="$f"
#done<<<"$(list_submissions)"

# Mostly we automark/feedback gate submissions using this function, which by default
# just uses the corresponding .tst file.
# A submission of a gate might depend on other gates. Some of these will be
# 'standard' gates but the stduent might have created their own helper gates.
# These can be given as additional arguments. The proj_test_gate function, below,
# takes care of copying all the files across but then deleting the ones that are
# builtins, so that the student isn't led astray if they got one gate right but
# it depends on a gate that they haven't got right yet.
test_gate_generic () {
    local gate="$1"
    local tstfile="${2:-${gate}.tst}"
    shift 2
    # Remaining args are any extra files that should be copied from the filesdir
    echo "=== TESTING: $gate ($tstfile)" 1>&2
    # Be case-sensitive? YES because the simulator is when it loads gates.
    # from test scripts (at least on *nix platforms)
    #found="$( find -iname "$gate".hdl 2>/dev/null | head -n1 )"
    #test -n "$found" || \
    test -e "$gate".hdl || \
      (echo "I didn't find a file I expected: ${gate}.hdl" 1>&2; ls 1>&1; false) || \
      return 1
    output="$( "$SW"/tools/HardwareSimulator.sh "$tstfile" 2>&1 )"
	#echo "output is $output" 1>&2
    while read line; do
		case "$line" in
			('Comparison failure at line '*)
				echo "Simulator said: $line"
				echo "Elaboration: "
				line_num="$( echo "$line" | sed 's/Comparison failure at line //' )"
                # subtract 8 from COLUMNS because we're going to prepend 8 chars with cat -n
				formatted="$( pr -w$(( ${COLUMNS:-132} - 8 )) -s$'\t' -T -m \
                  <(echo "your gate's behaviour:"; cat "${tstfile/tst/out}" | tr -d '\r') \
                  <(echo "correct behaviour:"; cat "${tstfile/tst/cmp}" | tr -d '\r') \
                  | tr -d '\r' )" #"'
                if [[ $(( "$( head -n1 "${tstfile/tst/cmp}" | wc -c )" - 1 )) -gt $(( ($COLUMNS - 8)/2 )) ]]; then
                    echo "WARNING: your window may be too narrow to display what follows."
                    echo "If so, try resizing the window and/or reconfiguring your terminal."
                fi
                echo -n '        '; echo "$formatted" | head -n1
                echo "$formatted" | tail -n+2 \
                   | lines_with_highlight_at $line_num
                  #| '^[[:blank:]]+${line_num}[[:blank:]]+'
				line_count_correct="$( wc -l < "${tstfile/tst/cmp}" )"
				line_count_attempt="$( wc -l < "${tstfile/tst/out}" )"
				if ! [[ $line_count_correct -eq $line_count_attempt ]]; then
                    true
# HM.  Actually the line count is not very revealing after all.
#                    echo "I notice your output table does not have the right number of lines"
#                    echo "Maybe you didn't get the gate's interface correct? Check the book."
#                    echo "Maybe you didn't assign all your $gate gate's inputs and outputs?"
#					echo " (e.g. try adding 'out=<...something...>')"
				fi
			;;
			('End of script - Comparison ended successfully')
				echo "Simulator said: $line"
				echo "=== SUCCESS: $gate ($tstfile)"
			;;
			('In HDL file '*)
				echo "Simulator said: $line"
				line_num="$( echo "$line" | sed 's/.*, Line \([0-9]\+\),.*/\1/' )"
				filename="$( echo "$line" | sed 's/In HDL file \([^,]*\),.*/\1/' )"
                lines_with_highlight_at $line_num < "$filename"
                audit_log_simulator_message "$line" "$line_num" <"$filename"
			;;
			(*'A GateClass name is expected: '*)
				echo "Simulator said: $line"
				echo "Check your syntax carefully. Are all '/* */'-style comments terminated properly?"
				line_num="$( echo "$line" | sed 's/.*, Line \([0-9]\+\),.*/\1/' )"
				filename="$( echo "$line" | sed 's/In HDL file \([^,]*\),.*/\1/' )"
                lines_with_highlight_at $line_num < "$filename"
			;;
			(*)
				echo "Simulator said: $line"
                audit_log_simulator_message "$line"
			;;
		esac
	done<<<"$output"
}


# to test a gate, we:
# 1. instantiate it [and its helpers], but *not* any builtins
#      -- do this by copying the submission and then deleting all builtins
# 2. get the test script and .cmp right
# 2. run the software
proj_test_gate () {
    gate="$1"
    local n="$2"
    filesdir="$3"
    tstfile="${4:-${gate}.tst}"
    # make a new temporary directory to copy the files to
    testdir="$( mktemp -d )"
	#echo "testdir is $testdir" 1>&2
    test -d "$testdir" || return 1
	cp -rp * "$testdir"/
	cd "$testdir"
    # copy the whole submission, then delete any builtin gates that aren't the one being tested
	find ! -iname "$gate".hdl \( \
      `for g in $builtins; do echo -iname "$g".hdl -o ; done; echo '-false'` \) \
      -print0 | xargs -0 rm -f
    # also copy all the .tst and .cmp files from the filesdir, i.e. from the
    # 'starter kit' that we provide... this ensures we get the 'good' tst/cmp files,
    # i.e. no risk of using student-munged ones.
    cp "${filesdir}"/${tstfile} ./
    cp "${filesdir}"/${tstfile/tst/cmp} ./
    # also copy any *.hack files in the filesdir (only relevant to Computer in proj 5)
    if [[ -n "$( ls "${filesdir}"/*.hack 2>/dev/null )" ]]; then
        cp "${filesdir}"/*.hack ./
    fi
    test_gate_generic "$gate" "$tstfile"
    cd "$extracted"
	rm -rf "$testdir"
}

# Where do we get the tst/cmp files from? From the same starter kit
# that we give the students.
PROJ1FILES=/courses/co557/proj01starter
PROJ2FILES=/courses/co557/proj02starter
# see below
#PROJ3FILES=/courses/co557/proj03starter/a
PROJ5FILES=/courses/co557/proj05starter

# Most projects are tested using the same generic logic, as follows.
proj_n_tests () {
    local n="$1"
    gates_var=proj${n}_gates && \
    for gate in ${!gates_var}; do
        filesdir_var=PROJ${n}FILES
	    proj_test_gate "$gate" "$n" "${!filesdir_var}"
    done
    echo "=== end of testing" 1>&2
}
# SPECIAL CASE for project 3, which builds the memory. It has
# two parts, 'a' and 'b', which need to be tested separately in two different runs.

# NOTE: this script runs as the user, so for security we *never*
# work from HDL source code 'solutions'. Rather, we rely on the fact
# that the built-in (.class file) Java implementations of the built-in
# gates are available, and we can test against those.

# Stephen's 8for16 branch of the software includes Java implementations of
# Add8, Inc8, Mux4Way8, Mux8Way8, so we can rely on them just like other
# builtins.

# PROBLEM: it doesn't seem wise to do same for RAMnnn. Because the names
# of the RAM chips don't include their bit-width, we can't easily add
# 8-bit variants because we'd be replacing the 16-bit built-ins. That will
# probably cause problems later. Instead we hack around it: the
# students are told to use the built-in RAMs *as if* they're
# only 8 bits wide, using the sub-bus notation. This is only
# needed in RAM512, i.e. the bridge between parts a and b of
# project 3.
#
# It's possible they'll express each of their solutions as using
# the built-in RAM. Or as their own 8-bit RAM. Somehow we need
# to be tolerant of this at marking time, most likely.

proj_3_tests () {
    local n=3
    # We explicitly don't include ALU as a builtin. If the user supplies ALU,
    # it will be used during testing. This is because it's not fully possible
    # to fake up an 8-bit ALU from the built-in 16-bit one... the 'zr' flag
    # is different because it will be w.r.t. the full 16 bits.
    builtins="$proj1_gates HalfAdder FullAdder Add8 Inc8 DFF Bit Register RAM8 RAM64 RAM512 RAM4K RAM16K PC"
    test -d 'a' || test -d "$( readlink 'a' )" || (echo "I was expecting a subdirectory called 'a'."; false) || return 1
    PROJ3FILES=/courses/co557/proj03starter/a
    gates="Bit Register PC RAM8 RAM64"
    for gate in ${gates}; do
        cd "$extracted"/a
        filesdir_var=PROJ${n}FILES
	    proj_test_gate "$gate" "3" "${PROJ3FILES}"
    done
    echo "=== Moving to part b..." 1>&2
    test -d 'b' || test -d "$( readlink 'b' )" || (echo "I was expecting a subdirectory called 'b'."; false) || return 1
    PROJ3FILES=/courses/co557/proj03starter/b
    gates="RAM512 RAM4K RAM16K"
    for gate in ${gates}; do
        cd "$extracted"/b
        filesdir_var=PROJ${n}FILES
	    proj_test_gate "$gate" "3" "${PROJ3FILES}"
    done
    echo "=== end of testing" 1>&2
}

# SPECIAL CASE for project 5, which builds the computer. There are multiple
# test files to run in some cases. Also,
# we use the *original*, NOT the 8for16 version, as per the project brief.
# That also affects the builtins: all the 16-way builtins are now included.
# Remember, builtins are gates which, if present in the student's submission,
# we *delete* from their submission when testing, i.e. forcing fallback to the
# built-in Java-compiled version. In this way each gate is tested independently and
# they can get credit even if one of their depended-on gates isn't working.
proj_5_tests () {
    local SW=/courses/co557/nand2tetris-2.6-orig
    builtins="Nand Not And Or Xor Mux DMux DMux4Way DMux8Way Or8Way"
    builtins="${builtins} Not16 And16 Or16 Mux16"
    builtins="${builtins} Mux4Way16 Mux8Way8"
    builtins="${builtins} FullAdder HalfAdder Add16 Inc16 ALU"
    builtins="${builtins} DFF Bit Register PC RAM8 RAM64 RAM512 RAM4K RAM16K"
    builtins="${builtins} ARegister DRegister ROM32K"
    builtins="${builtins} Screen Keyboard"
    n=5
    gates_var=proj${n}_gates && \
    for gate in ${!gates_var}; do
        filesdir_var=PROJ${n}FILES
        case "$gate" in
        (CPU)
            proj_test_gate "$gate" "$n" "${!filesdir_var}" CPU-external.tst
            proj_test_gate "$gate" "$n" "${!filesdir_var}" CPU.tst
        ;;
        # We only do the memory batch test
        (Memory)
            proj_test_gate "$gate" "$n" "${!filesdir_var}" Memory-batch.tst
        ;;
        # FIXME: also copy the *.hack files from the filesdir, i.e. treat these as builtins
        # rather than taking them from the submission
        (Computer)
            proj_test_gate "$gate" "$n" "${!filesdir_var}" ComputerAdd-external.tst
            proj_test_gate "$gate" "$n" "${!filesdir_var}" ComputerAdd.tst
            proj_test_gate "$gate" "$n" "${!filesdir_var}" ComputerMax-external.tst
            proj_test_gate "$gate" "$n" "${!filesdir_var}" ComputerMax.tst
            #proj_test_gate "$gate" "$n" "${!filesdir_var}" ComputerRect-external.tst
            #proj_test_gate "$gate" "$n" "${!filesdir_var}" ComputerRect.tst
        ;;
        (*)
            proj_test_gate "$gate" "$n" "${!filesdir_var}"
            ;;
        esac
    done
}

proj_4_tests () {
    SW=/courses/co557/nand2tetris-2.6-orig
    # Below is my initial feedback offering for project 4, which
    # was available to the students while working on the project. For
    # auto-marking I improved on it, and that version is in the automark_proj4 function below.
#echo "Project 4 feedback is a work in progress... beware!" 1>&2
#    dividend=$(( $RANDOM % 1200 + 100 ))
#    divisor=$(( $RANDOM % 400 + 1 ))
#    # our dividend may be as big as 1300 and our divisor as
#    # small as 1. So if the program takes six instructions per
#    # loop iteration (unlikely!) it would take a little over
#    #  6*1300 instructions to terminate. So run for 8000 cycles.
#    n=4
#    infile="$( find "${extracted}" -iname div.asm -type f -print0 | xargs -0 ls | head -n1 )"
#    test_proj4_division "$infile" "$dividend" "$divisor"
#    outfile="$( dirname "$infile" )"/srk-random.out
#    quot=$(( $dividend / $divisor ))
#    rem=$(( $dividend % $divisor ))
##   | RAM[3] | RAM[4] |
##   |      4 |    201 |
#    expected=$'| RAM[3] | RAM[4] |\n| '"`printf '% 6d' $quot`"' | '"`printf '% 6d' $rem`"' |'
#    diff -u "$outfile" <( echo "$expected" )
#    status=$?
#    if ! [[ $status -eq 0 ]]; then
#       echo "Looks dodgy -- was expecting R3 (quotient) to be $quot and R4 (remainder) to be $rem"
#    else
#       echo "Looks good -- I think your R3 (quotient) is $quot and your R4 (remainder) is $rem"
#    fi
#    rm -f "$tmptst"
    local extracted="$2" # HACK / FIXME
    automark_proj4 `id -urn` "$the_tar" "$extracted" >/dev/null
}

run_tests () {
    local n="$1"
    local extracted="$2"
    case "$n" in
        (1|2)
            proj_n_tests $n 2>&1
        ;;
        (3) # This has the a/ vs b/ split. Do we want this in submissions?
            # Probably, yes. So we hand-craft the feedback function.
            proj_3_tests $n 2>&1
        ;;
        (4)
            proj_4_tests $n "$extracted" 2>&1 # HACK / FIXME: get rid of this irregularity
        ;;
        (5)
            proj_5_tests $n 2>&1
        ;;
        (*)
           echo "Eep! I haven't got as far as helping with project $1 yet" 1>&2
        ;;
    esac
}

# This is overridden in write-feedback, i.e.
# we actually want to print useful stuff out when the student asks
# for feedback, but not during automarking.
audit_log_simulator_message () {
    return 0
}


# 'Fixups'. More below.
# Calling the feedback program will tar the student's work,
# fix it up (doctor it) to work around various problems.
# then run the relevant test functions on the fixed-up version.
# But sometimes we want to test before the fixups are applied.
test_submission_dir_prefixup () {
    local n="$1"
    local d="$2"
    echo "Working with not-fixed-up dir $d" 1>&2
    echo "(It will remain not-fixed-up, but a temporary tar" 1>&2
    echo "will be created, extracted and fixed up)" 1>&2
    # The test output will go to stdout... right? GAH. Somehow it is
    # going to stderr. WHY WHY WHY?
    /courses/co557/feedback "$n" "$d"
}

# Fixups include
#  - canonicalizing the casing of filenames *and* of
#      HDL code's references to filenames
#       (because we are Unix hence case-sensitive,
#        but the student may be using a Window machine that is not)
#  - traversing subdirectory structure. Some students 
#       put their work under/many/layers/of/directories.
#      The feedback program will *not* accept such.
#      But many students don't bother running it.
#      When marking, I didn't want to be *so* harsh as to give no credit,
#      so we make a "best automated effort" to traverse directories and find work.
#  - fiddling with sub-bus notation e.g. in case the screwed up the RAM chips
#      by not following the instruction to use the built-in 16-way versions.

test_submission_dir_postfixup () {
    local n="$1"
    local d="$2"
    # The test output will go to stdout
    if [[ -n "$SUBMISSION_DIR_IS_NOT_FIXED_UP" ]]; then
        (test_submission_dir_prefixup "$n" "$d")
    else
        # This is just what the feedback program does
        (cd "$d" && run_tests "$n" "$d")
    fi
}

test_submission_tar () {
    local f="$1"
    local real_f="$( cd "$dir" && readlink -f "$f" )"
    local n="$2"
    #local tmpd="$( mktemp -d )"
    #local f_real="$( cd "$dir"; readlink -f "$f" )"
    #(cd "$tmpd" && (tar -xf "$f_real" && COLUMNS=200 "$dir"/../feedback $n . ))
    local d="$( mktemp -d )"
    (cd "$d" && tar -xf "$real_f" )
    test_submission_dir_prefixup "$n" "$d" 2>&1
    rm -rf "$d"
}
    proj1_files='And.hdl
And8.hdl
DMux.hdl
DMux4Way.hdl
DMux8Way.hdl
Mux.hdl
Mux4Way8.hdl
Mux8.hdl
Mux8Way8.hdl
Not.hdl
Not8.hdl
Or.hdl
Or8.hdl
Or8Way.hdl
Xor.hdl'
    proj1_gates='And
And8
DMux
DMux4Way
DMux8Way
Mux
Mux4Way8
Mux8
Mux8Way8
Not
Not8
Or
Or8
Or8Way
Xor'
    proj2_files='ALU.hdl
Add8.hdl
FullAdder.hdl
HalfAdder.hdl
Inc8.hdl'
    proj2_gates='ALU
Add8
FullAdder
HalfAdder
Inc8'
    proj3_files='a/Bit.hdl
a/PC.hdl
a/RAM64.hdl
a/RAM8.hdl
a/Register.hdl
b/RAM16K.hdl
b/RAM4K.hdl
b/RAM512.hdl'
    proj3_gates='Bit
PC
RAM64
RAM8
Register
RAM16K
RAM4K
RAM512'
    proj4_gates=''
    proj4_files='div.asm
toggle.asm'
    proj5_gates='Memory
CPU
Computer'
    proj5_files='Memory.hdl
CPU.hdl
Computer.hdl'

# builtins are deleted from the submission tree when each
# gate is tested, so that the real builtin version is used.
builtins="Nand Not And Or Xor Mux DMux DMux4Way DMux8Way DFF Not8 And8 Or8 Mux8 Mux4Way8 Mux8Way8 Or8Way HalfAdder FullAdder Add8 Inc8"
# But what about the converse: there *is* a builtin that
# they're not allowed to use *unless* they've defined it themselves?
# This is true for Add16, Inc16, And16, Or16, Not16, Mux4Way16, Mux8Way16.
# In that case we should *not* delete their version, but also not provide
# the builtin (in our hacked version of the software).
# Not16 And16 Or16 Or8Way Mux4Way16 Mux8Way16


# How sane does this submission look as a project $1 submission?
# Basically we check whether it contains the expected files.
sanity_of_dir_as_project () {
    local proj="$1"
    local dir="$2"
    varname=proj${proj}_files
    #echo "varname is $varname" 1>&2
    local score=0
    local ctr=0
    for f in ${!varname}; do    
        if [[ -e "$dir"/"$f" ]]; then
            #echo "Found $f" 1>&2
            score=$(( $score + 1 ))
        else
            #echo "Found no $f" 1>&2
            true
        fi
        ctr=$(( $ctr + 1 ))
    done
    echo $(( 100 * $score / $ctr ))
}
sanity_of_tar_as_project () {
    local proj="$1"
    local tar="$2"
    varname=proj${proj}_files
    #echo "varname is $varname" 1>&2
    local score=0
    local ctr=0
    tar_listing="$( tar --list -vf "$tar" )"
    for f in ${!varname}; do    
        if grep -i " $f"'$' <<<"${tar_listing}" >/dev/null; then
            #echo "Found $f" 1>&2
            score=$(( $score + 1 ))
        else
            #echo "Found no $f" 1>&2
            true
        fi
        ctr=$(( $ctr + 1 ))
    done
    echo $(( 100 * $score / $ctr ))
}

detect_mislabelled () {
    cd "$dir"
    for f in "$@"; do
        declared_n="$( basename "$f" | sed -r 's/^0([123456]).*/\1/' )"
        if [[ -z "$declared_n" ]]; then echo "Did not understand filename (n): $f" 1>&2; continue; fi
        local u="$( basename "$f" | sed -r 's/^0[12345]-([a-z]+[0-9]+)-.*/\1/' )"
        if [[ -z "$u" ]]; then echo "Did not understand filename (u): $f" 1>&2; continue; fi
        sz="$( stat -c "%s" "$f" )"
        if [[ $sz -eq 0 ]]; then
            echo "Skipping zero-length submission: $f" 1>&2
            continue
        fi
        d="$(mktemp -d)"
        (cd "$d" && tar -xf "$f")
        status=$?
        if ! [[ $status -eq 0 ]]; then
            echo "Skipping un-untar'able submission: $f" 1>&2
            rm -rf "$d"
            continue
        fi
        sanity="$( sanity_of_dir_as_project $declared_n "$d" )"
        if [[ -z "$sanity" ]]; then sanity=0; fi
        echo "Sanity $sanity as project ${declared_n}: $f" 1>&2
        if [[ $sanity -lt 100 ]]; then
            greatest_sanity=$sanity
            most_sane_as="$declared_n"
            for n in 1 2 3; do
                if [[ $n -eq $declared_n ]]; then continue; fi
                other_sanity="$( sanity_of_dir_as_project $n "$d" )"
                if [[ $other_sanity -gt 0 ]]; then
                    echo "Sanity greater than 0 ($other_sanity) as project ${n}: $f" 1>&2
                    if [[ $other_sanity -gt $greatest_sanity ]]; then
                        greatest_sanity="$other_sanity"
                        most_sane_as="$n"
                    fi
                fi
            done
            # we only reassign if it's more sane as that project
            # than as the one it's named as
            if ! [[ $most_sane_as -eq $declared_n ]] && \
                [[ 0 -eq "$( ls "$dir"/0${most_sane_as}-${u}* 2>/dev/null | wc -l )" ]]; then
                echo "Reclassifying $f as a submission for project $most_sane_as (sanity $greatest_sanity vs $sanity, and no $most_sane_as submission found)"
                new_basename="$( basename "$f" | sed "s/^0${declared_n}/0${most_sane_as}/" )"
                mv -i "$f" "$( dirname "$f" )/$new_basename"
                echo "Symlinking under old name"
                ln -s "$new_basename" "$f"
            fi
        fi
        rm -rf "$d"
    done
}


case_canonicalising_sed_program () {
    local pre="$1"
    local post="$2"
    ctr=0
    for g in $proj1_gates $proj2_gates $proj3_gates $proj5_gates; do
        if ! [[ $ctr -eq 0 ]]; then echo -n "; "; fi
        echo -n "s/\\($pre\\)"; echo -n "$g" | sed -r 's/([a-zA-Z])/\[\L\1\E\U\1\E]/g'; \
            echo -n "\\($post\\)/\1$g\2/"
        ctr=$(( $ctr + 1 ))
    done
}

# TRY TO make fixup idempotent
fixup_extracted () {
    local n="$1"
    local d="$2"
    if [[ $n -eq 3 ]] && \
     ! [[ -e "$d"/a ]]; then
        echo "Symlinking the a and b" 1>&2
        (cd "$d" && (ln -s . a; ln -s . b))
    fi
    # Another hack: case-canonicalize the filenames and also
    # the references to those filenames.
    (cd "$d";
        find -name '*.hdl' | while read fname; do
            sed_expr="$(case_canonicalising_sed_program '[^A-Za-z0-9_]' '[[:blank:]]*(')"
            #echo sed -i "$sed_expr" "$fname" 1>&2
            sedded="$( sed "$sed_expr" "$fname" )"
            diff="$( diff -u "$fname" <(echo "$sedded") )"
            ! test $? -eq 0 && \
            (echo "To avoid case-sensitivity problems, I patched your code as follows."
             echo "$diff"
             echo "$sedded" > "$fname")
        done
        unset sedded
        find -name '*.hdl' | while read fname; do
            sedded="$( echo "$fname" | sed 's@^\./@@' | sed "$(case_canonicalising_sed_program '^' '\.')" )"
            if [[ "$sedded" != "$fname" ]]; then
                echo "To avoid case-sensitivity problems, renaming ${fname} as ${sedded}" 1>&2
                mv "$fname" "$sedded"
            fi
        done
    )
    # Another HACK: if there's no HDL in the root directory,
    # find a directory containing some and symlink its contents into the root.
    # We prefer a directory whose name contains the zero-padded project
    # number, e.g. '01'
    (cd "$d" && if [[ "$( ls *.[hH][Dd][lL] 2>/dev/null | wc -l )" -eq 0 ]]; then
         dirs="$( find -iname '*.hdl' | sed 's^/[^/]*$^^' | sort | uniq )"
         numstr="$( printf %02d "$n" )"
         tentative_dir="$( (echo "$dirs" | grep "$numstr"; echo "$dirs" | grep -v "$numstr") | head -n1 )"
         if [[ -n "$tentative_dir" ]]; then
            echo "Using tentative dir $tentative_dir" 1>&2
            ln -s "$tentative_dir"/* .
         fi
    fi)
    if [[ $n -eq 3 ]]; then
        # It never hurts to add explicit sub-buses, and it allows us to
        # use the 16-bit RAM chips for testing.
        # EXCEPT: it does hurt in the case of RAM64, because the instruction
        # was to use the full 16-bit version and explicitly do the sub-busing.
        # At least one student came up with a baroque design that consumes
        # the full 16-bit bus and then narrows it in a helper gate.
        # So we simply say that you shouldn't need the hacky patching
        # in your RAM512... you should have followed the instructions and
        # used the 16-bit RAM512. Note that for students who get this wrong,
        # this doesn't cause cascading breakage to the other RAMs.
        # Another quirk is those who've used their own 8-bit ALU as part of
        # PC, rather than Inc8. So we also do the rewrite for uses of ALU, on 'x' and 'y'.
        # However, we also *don't* include ALU in builtins for project 3. This is
        # because if the user supplies their own, we can't easily fake it up out of
        # the 16-bit one, because the 'zr' signal is semantically different.
        echo "Hack-patching RAM chips" 1>&2
        (cd "$d" && find -iname '*.hdl' | grep -vi '/RAM512\.hdl$' | while read f; do
          sedded="$( sed '/\(Register\|ALU\|RAM\(8\|64\|512\|4K\)\)[[:blank:]]*(/ s/\([^a-zA-Z0-9_]\)\(in\|out\|x\|y\)[[:blank:]]*=/\1\2[0..7]=/g' "$f" )"
          diff="$( diff -u "$f" <(echo "$sedded") )"
          ! test $? -eq 0 && \
            (echo "To test against the 16-bit built-in RAM chips, I patched your code as follows."
             echo "$diff"
             echo "$sedded" > "$f")
        done)

#         '/RAM8[[:blank:]]*(/ s/\([[:blank:]]\|\|,\)\(in\|out\)\([[:blank:]]*\)\([^[a-zA-Z0-9_]\)/\1\2[0..7]\3\4/g' \
#          s/\([a-zA-Z_][a-zA-Z0-9_]*[[:blank:]]*=[[:blank:]]*out[[:blank:]]*\)\([^[a-zA-Z0-9_]\)/\1\2[0..7]\3/' RAM64.hdl)
    fi
	return 0
}


# REMEMBER the mark weights for
# proj 1: all gates are out of 3, of which 1 is for sanity
# proj 2: HalfAdder 3, FullAdder 3, Add8 5, Inc8 5, ALU 12 (partial credit available),
#               of which 1 is sanity
# proj 3: Bit 3, Register 5, PC 12, RAM8 5, RAM64 3, RAM512 3, RAM4k 3, RAM16K 5
#               (partial credit available for PC; )

test_proj4_division () {
    local submission_asm_file="$1"
    local dividend="$2"
    local divisor="$3"
    shift; shift; shift
    SW=/courses/co557/nand2tetris-2.6-orig
    tmptst="$( dirname "${submission_asm_file}" )"/srk-random.tst
    outfile="$( dirname "${submission_asm_file}" )"/srk-random.out
    echo "Will try to divide $dividend by $divisor using your code" 1>&2 && \
    cat >"$( dirname "${submission_asm_file}" )"/srk-random.tst <<EOF
load div.asm,
output-file srk-random.out,
output-list RAM[3]%D1.6.1 RAM[4]%D1.6.1;

set RAM[0] ${dividend},
set RAM[1] ${divisor},

repeat 16000 {
  ticktock;
}

// Outputs the stack base and some values
// from the tested memory segments
output;
EOF
    $SW/tools/CPUEmulator.sh "$tmptst" 1>&2
    cat "$outfile" #"
}

create_random_toggle_test () {
    npresses="$1"
    random_hex_string="$2"
    # A randomized test case for toggle looks something like this:
    # pick a small number of keypresses (may be odd or even), say in the range 2..9
    # for each keypress, choose an adequate duration
    # followed by a comfortably long duration of releasedness.
    # Then a comfortably long length of key-released time.
    # Sample the screen at some random points.
    # The parity of the number of key releases should determine the colour
    echo -n 'load toggle.asm,
output-file srk-toggleit.out,
output-list RAM[16384]%B1.16.1 RAM[24575]%B1.16.1'
    for n in `seq 1 3`; do
        random_digits="$( head -c4 <<<"$random_hex_string" )"
        random_hex_string="$( echo "$random_hex_string" | tail -c+5 )"
        random_offset=$(( 0x$random_digits % 8191 ))
        echo -n " RAM[$(( 16384 + $random_offset ))]%B1.16.1"
    done
    echo ';'
    for n in `seq 1 $npresses`; do
        echo '
        set RAM[24576] 65,

        repeat 800000 {
          ticktock;
        }
        
        set RAM[24576] 0,
        repeat 3200000 {
          ticktock;
        }'
    done
    echo '
        repeat 1600000 {
              ticktock;
            }
        output;'    
 
}

automark_proj4 () {
    local u="$1"
    local f="$2"
    local d="$3"
    shift; shift; shift
    #echo "blah" 1>&2
    hexdigits="$( md5sum "$f" )"
    asmfile="$( find "$d" -iname div.asm \( -type f -o -type l \) -print0 | xargs -r -0 ls | head -n1 )"
    if [[ -z "$asmfile" ]]; then div_marks=0; else
    total=0
    # We automark project 4 div.asm by
    # - a sequence of divisions that are pseudo-random but seeded
    #   on the submission (so they are deterministic)
    #     -- we generate 3 of these
    # - a sequence of divisions that are hand-crafted to test boundaries
    # - one mark for each of these
    # - ELSEWHERE we also generate a hint about the division-by-0 behaviour
    while read dividend divisor ; do
        echo "Trying to divide $dividend by $divisor" 1>&2
        output="$( test_proj4_division "$asmfile" "$dividend" "$divisor" )"
        echo "output is $output" 1>&2
        read quotient remainder<<<"$( echo "$output" | tail -n+2 | tr -d '|' )" 
        expected_quotient=$(( $dividend / $divisor ))
        expected_remainder=$(( $dividend % $divisor ))
        # use string comparison so that empty strings don't cause errors but compare non-equal
        if [[ $(( $quotient )) == "$expected_quotient" ]] && \
           [[ $(( $remainder )) == "$expected_remainder" ]]; then
           # We have fifteen marks to give, of which one is for sanity,
           # four for having the basics,
           # and the remaining *ten* for functional correctness.
           total=$(( $total + 2 ))
           echo "Success ($quotient, $remainder)" 1>&2
        else
           echo "Not correct ($quotient, $remainder vs $expected_quotient, $expected_remainder)" 1>&2
           if [[ -n "$quotient" ]] && [[ $(( $quotient )) == "$expected_remainder" ]] && \
           [[ -n "$remainder" ]] && [[ $(( $remainder )) == "$expected_quotient" ]]; then
              echo "Your quotient and remainder are reversed, but allowing it as" 1>&2
              echo "I'm feeling generous" 1>&2
              total=$(( $total + 2 ))
           elif [[ -n "$quotient" ]] && [[ $(( $quotient )) == "$expected_quotient" ]]; then
              echo "Have one mark for the quotient" 1>&2
              total=$(( $total + 1 ))
           elif [[ -n "$remainder" ]] && [[ $(( $remainder )) == "$expected_remainder" ]]; then
              echo "Have one mark for the remainder" 1>&2
              total=$(( $total + 1 ))
           fi
        fi
    done<<<"$(
echo $(( 0x"$( echo "$hexdigits" | head -c4             )" % 1200 + 100 )) $(( 0x"$( echo "$hexdigits" | head -c8  | tail -c4 )" % 400 + 1 )); \
echo $(( 0x"$( echo "$hexdigits" | head -c12 | tail -c4 )" % 1200 + 100 )) $(( 0x"$( echo "$hexdigits" | head -c16 | tail -c4 )" % 400 + 1 )); \
echo $(( 0x"$( echo "$hexdigits" | head -c20 | tail -c4 )" % 1200 + 100 )) $(( 0x"$( echo "$hexdigits" | head -c24 | tail -c4 )" % 400 + 1 )); \
echo 32767  32766;
echo 32766  32767;
echo 101 1;
echo 1 1)"
#echo 32767  32;
#echo 0 42;
#echo $(( 0x"$( echo "$hexdigits" | head -c28 | tail -c4 )" % 1200 + 100 )) $(( 0x"$( echo "$hexdigits" | head -c32 | tail -c4 )" % 400 + 1 )); \
    if [[ $total -eq 14 ]]; then total=15; fi
    if [[ $total -lt 5 ]]; then
        echo "Looking for partial credit from valid/sane assembly" 1>&2
        # time for partial credit -- run the ASMValidator
        submission_realpath="$( readlink -f "$asmfile" )"
        local TOOLS=/courses/co557/nand2tetris-open-source-2.5.7+srk/InstallDir
        outfile="$( mktemp )"
        errfile="$( mktemp )"
        echo "submission_realpath: $submission_realpath" 1>&2
        echo "Running $TOOLS/ASMValidator.sh $submission_realpath" 1>&2
        (cd "$( dirname "$submission_file" )" && \
         "$TOOLS"/ASMValidator.sh "$submission_realpath") >"$outfile" 2>"$errfile"
        cat "$errfile" 1>&2
        # Partial credit is: 4 if you have written 8 distinct instructions,
        # (late-breaking change: ACTUALLY MAKE IT EIGHT not ten; the brief may still say 10? FIXME)
        # +1 if you also access the right memory locations
        distinct_n="$( cat "$errfile" | grep "^Counted" | wc -l )"
        if [[ $distinct_n -ge 8 ]]; then
            total=4
        fi
        # +1 if the solution contained @3 and @4,
        #i.e. if we assemble it we should get 0000000000000011 and 0000000000000100 
        if grep 0000000000000011 "$outfile" >/dev/null && \
           grep 0000000000000100 "$outfile" >/dev/null; then
           total=$(( $total + 1 ))
        fi
        rm -f "$outfile"
        rm -f "$errfile"
    fi
    div_marks="$total"
    fi
    # Now for toggle.
    asmfile="$( find "$d" -iname toggle.asm \( -type f -o -type l \) -print0 | xargs -r -0 ls | head -n1 )"
    submission_asm_file="$( readlink -f "$asmfile" )"
    if [[ -n "$submission_asm_file" ]]; then
    submission_realpath="$( readlink -f "$submission_asm_file" )"
    tmptst="$( dirname "${submission_asm_file}" )"/srk-toggleit.tst
    outfile="$( dirname "${submission_asm_file}" )"/srk-toggleit.out
    # We test toggling five times: three odd, two even.
    # (Even a no-op solution will get the evens right... 6 marks is pretty generous,
    # but it's only one more than the 'syntactically correct + right-idea' partial credit.)
    toggles_tried=""
    for n in `seq 1 5`; do
        ntoggles=$(( 2 + 0x"$( head -c1 <<<"$hexdigits" )" % 8 ))
        if [[ $n -eq 4 ]] || [[ $n -eq 5 ]]; then
            # force it to be even
            if [[ $(( $ntoggles % 2 )) -eq 1 ]]; then
                ntoggles=$(( $ntoggles + 1 ))
            fi
        else
            # force it to be odd
            if [[ $(( $ntoggles % 2 )) -eq 0 ]]; then
                ntoggles=$(( $ntoggles + 1 ))
            fi
        fi
        # force it to be different from what we've tried before
        regexp="^$( echo "$toggles_tried" | tr -d '\n' | tr -s '[:blank:]' '|' )\$"
        while egrep "$regexp" <<<$ntoggles >/dev/null; do
            ntoggles=$(( $ntoggles + 2 ))
        done
        toggles_tried="${toggles_tried:+${toggles_tried} }$ntoggles"
        echo "Will try some toggling ($ntoggles times) using your code" 1>&2 && \
        create_random_toggle_test $ntoggles "$( echo "$hexdigits" | tail -c+2 )" \
           >"$( dirname "${submission_realpath}" )"/srk-toggleit.tst
        # don't use those hexdigits again
        hexdigits="$( echo "$hexdigits" | tail -c+4 )"
        SW=/courses/co557/nand2tetris-2.6-orig
        (cd "$( dirname "$submission_realpath" )" && \
            $SW/tools/CPUEmulator.sh "$tmptst" ) 1>&2
        # output should be 5x all 0s if ntoggles has even parity, all 1s if ntoggles has odd parity
        ntoggles_parity=$(( $ntoggles % 2 ))
        cat "$outfile" 1>&2
        if egrep "(${ntoggles_parity}{16}[[:blank:]]+){5}" <<<"$( head -n+2 "$outfile" | tr -d '|' )" >/dev/null; then
            toggle_total=$(( $toggle_total + 2 ))
        else
            # Since it's harsh to fully penalise an off-by-one termination error,
            # e.g. the student whose loop stops at @24574 rather than @24575,
            # we allow half pre-credit here. This is separate from how pre-credit
            # is scaled non-linearly to credit.
            lines="$( head -n+2 "$outfile" | tail -n1 | tr '|' '\n' | tr -d '[:blank:]' | grep -v '^$' )"
            correct_lines="$( for i in `seq 1 5`; do for j in `seq 1 16`; do echo -n "$ntoggles_parity"; done; echo; done )"
            diff="$( diff -u <( echo "$lines" ) <( echo "$correct_lines" ) )"
            nlineswrong="$( echo "$diff" | tail -n+4 | grep '^-' | wc -l )"
            if [[ $nlineswrong -eq 1 ]]; then
                echo "Have one point of pre-credit for only a single value wrong" 1>&2
                toggle_total=$(( $toggle_total + 1 ))
            fi
        fi
    done
    # "toggle total" is the number of correct test cases (allowing half marks)
    # We use a nonlinear mapping to get to the functionality marks.
    # CARE: there is potential for perverse outcomes here if we're not careful.
    # The brief says that five marks are for valid right-idea code and the rest
    # for functionality. So we make a judgement call about how many marks is a
    # clear signifier of valid right-idea code. We only look for partial credit
    # when 
    case "$toggle_total" in
        (0|1|2) toggle_marks=0 ;;
        (3|4) toggle_marks=1 ;;  # You could still get up to 6 marks from partial credit here
        (5|6) toggle_marks=6 ;;  # No more partial credit available if you get to here on functionality.
        (7|8) toggle_marks=9 ;;
        (9) toggle_marks=11 ;;
        (10) toggle_marks=15 ;; # full credit
    esac
    # mapping to marks 
    if [[ $toggle_marks -lt 6 ]]; then
        # time for partial credit -- run the ASMValidator
        echo "Looking for partial credit from valid/sane assembly" 1>&2
        local TOOLS=/courses/co557/nand2tetris-open-source-2.5.7+srk/InstallDir
        outfile="$( mktemp )"
        errfile="$( mktemp )"
        echo "Running $TOOLS/ASMValidator.sh $submission_asm_file" 1>&2
        (cd "$( dirname "$submission_asm_file" )" && \
         "$TOOLS"/ASMValidator.sh "$submission_asm_file") >"$outfile" 2>"$errfile"
        cat "$errfile" 1>&2
        # Partial credit is: 4 if you make 8 distinct instructions,
        # ACTUALLY MAKE IT EIGHT not ten
        # +1 if you also access the right memory locations
        distinct_n="$( cat "$errfile" | grep "^Counted" | wc -l )"
        if [[ $distinct_n -ge 8 ]]; then
            # A solution that gets here might have up to 6 pre-credit marks from the toggle test,
            # i.e. 
            echo "Gained partial credit for # distinct instructions" 1>&2
            toggle_marks=$(( $toggle_marks + 4 ))
        fi
        # +1 if the solution contained @SCREEN (16384) and @KBD (24576),
        if grep 0100000000000000 "$outfile" >/dev/null && \
           grep 0110000000000000 "$outfile" >/dev/null; then
           echo "Gained partial credit for appropriate instructions" 1>&2
           toggle_marks=$(( $toggle_marks + 1 ))
        fi
        rm -f "$outfile"
        rm -f "$errfile"
    
    fi
    
    fi # end toggle case
    echo "$div_marks"$'\t'"${toggle_marks:-0}"
}

# If submissions are functionally correct, we don't use this function.
# But if they fail, we use this to calculate partial credit.
automark_proj5_partial_credit () {
    local u="$1"
    local submission_file="$2"
    local gate="$3"
    shift; shift; shift
    # Stephen's hacked/extended version of the software lives here...
    local TOOLS=/courses/co557/nand2tetris-open-source-2.5.7+srk/InstallDir
    
    # FIXME: clean up the contorted esequence of checking that follows.
    #
    # If there's a semantic error, the official tools will bail.
    # There's no clean way to get them to distinguish a semantic
    # from a syntactic error, even though our mark scheme (foolishly)
    # did so. (The two kinds of checking are interleaved in the source.)
    # So...
    # We try to classify the error message as syntactic versus semantic,
    # but LATER we run our own 'hacktools' freestanding parser,
    # to compensate for cases where there's been a semantic error
    # that caused the stock software to bail *before* it tried parsing
    # the rest of the file.
    # i.e. we don't want to assume assume that if it hits a semantic
    # error, the syntax of later parts of the code are correct. That is too
    # generous if the syntax later on is screwed. Yes, I really wrote a
    # separate parser.
    
    semantic_error=""
    syntax_error=""
    outfile="$( mktemp )"
    errfile="$( mktemp )"
    submission_realpath="$( readlink -f "$submission_file" )"
    # PROBLEM with case sensitivity:
    # if a student submits 'memory.hdl' but writes 'CHIP Memory',
    # on Unix platforms this will trigger a "Chip name doesn't match the HDL name"
    # error. To work around, the feedback program will automatically doctor the submission
    # by symlinking it under the case-correct name. But we have still been given the
    # case-incorrect name. We should really repeat the doctoring here. In other
    # words, the doctoring should be common to all all feedback and automarking.
    # FIXME: rather than that, here we are going back to the undoctored tar file. WHY?
    echo "submission_realpath: $submission_realpath" 1>&2
    (cd "$( dirname "$submission_file" )" && \
     "$TOOLS"/HDLValidator.sh "$submission_realpath") >"$outfile" 2>"$errfile"
    cat "$errfile" 1>&2
    while read line; do
        case "$line" in
            (*'Missing java class name'*)
                syntax_error=1
            ;;
            (*"Can't find "*) # + classFileName + " java class"
                syntax_error=1
            ;;
            (*' is not a subclass of BuiltInGate')
                syntax_error=1
            ;;
            (*'issing'*|*'Unexpected end of file'*|*'Unexpected keyword'*)
                #Missing ';'"
                #Unexpected keyword
                #Missing '}'"
                #Unexpected end of file
                #Missing 'CHIP' keyword"
                #Missing chip name
                #Missing '{'");
                #Missing '('");
                #Missing ';'");
                #Missing '}'");
                syntax_error=1
            ;;
            (*"Chip name doesn't match the HDL name"*)
                syntax_error=1
            ;;
            (*'Keyword expected'*)
                syntax_error=1
            ;;
            (*'Pin name expected'*)
                syntax_error=1
            ;;
            (*"',' or ';' expected"*)
                syntax_error=1
            ;;
            (*' has an invalid bus width'*)
                syntax_error=1
            ;;
            (*'A GateClass name is expected'*)
                syntax_error=1
            ;;
            (*'Expected end-of-file after'*)
                syntax_error=1
            ;;
            (*" has no source pin"*)
                semantic_error=1
            ;;
            (*"A pin name is expected")
                syntax_error=1
            ;;
            (*"Missing '='")
                syntax_error=1
            ;;
            (*"',' or ')' are expected")
                syntax_error=1
            ;;
            (*" has an invalid sub bus specification"*)
                semantic_error=1
            ;;
            (*"negative bit numbers are illegal"*)
                semantic_error=1
            ;;
            (*"left bit number should be lower than the right one"*)
                semantic_error=1
            ;;
            (*"the specified sub bus is not in the bus range"*)
                semantic_error=1
            ;;
            (*" is not a pin in "*)
                semantic_error=1
            ;;
            (*": sub bus of an internal node may not be used"*)
                semantic_error=1
            ;;
            (*"may not be subscripted"*)
                semantic_error=1
            ;;
            (*" have different bus widths"*)
                semantic_error=1
            ;;
            (*"An internal pin may only be fed once by a part's output pin"*)
                semantic_error=1
            ;;
            (*"An output pin may only be fed once by a part's output pin"*)
                semantic_error=1
            ;;
            (*"Can't connect gate's output pin to part"*)
                semantic_error=1
            ;;
            ("Can't connect part's output pin to gate's input pin"*)
                semantic_error=1
            ;;
            (*)
                echo "Did not understand output line, so treating as semantic error: $line" 1>&2
                semantic_error=1
            ;;
        esac
    done<"$errfile"
    if [[ -n "$syntax_error" ]]; then
        echo 0
    else
        # no syntax errors, but functionally wrong and possibly a semantic error.
        # does it instantiate all the right parts?
        # PROBLEM: If we got a semantic error but no syntax error, it doesn't
        # mean the syntax was OK. It might mean the validator gave up
        # before it found the syntax error, because the stock code interleaves
        # syntactic and semantic analysis. Equally, it *might* mean we have
        # correct syntax and all the necessary parts, but a semantic error.
        # SO we need another tool.
        /courses/co557/hacktools/hdl_test_parser "$submission_realpath" >/dev/null
        syntax_status=$?
        if ! [[ $syntax_status -eq 0 ]]; then
            # there is a lurking syntax error, masked by an earlier semantic error
            echo 0
        else
            # really no syntax error, but possibly a semantic error
            if [[ -n "$semantic_error" ]]; then
                # to get our parts list, we must scrape the syntax.
                # This pipeline deletes comments and then looks for '<IDENT> ('
                # to scrape the instantiated chip parts.
                parts="$( cat "$submission_realpath" | \
                sed 's@//.*@@' | sed 's@/\*@\x01@g' | sed 's@\*/@\x02@' | \
                tr '\n' '\f' | sed 's/\x01[^\x02]*\x02//g' | tr '\f' '\n' | \
                sed -rn '/(.*([[:blank:]]|^))([_a-zA-Z][_a-zA-Z0-9]*)[[:blank:]]*\(.*/ {s//\3/;p}' | \
                sort | uniq )"
            else
                parts="$(cat "$outfile")"
            fi
            case "$gate" in
                (Memory)
                    parts="RAM16K Screen Keyboard"
                ;;
                (Computer)
                    parts="ROM32K CPU Memory"
                ;;
                (CPU)
                    parts="ALU PC (A|D|)Register"
                ;;
            esac
            failed=""
            for p in $expected_parts; do
                egrep "^${p}\$" <<<"$parts" >/dev/null || { failed=1; break; }
            done
            if [[ ${failed:-0} -eq 1 ]]; then
                # we were missing some part, so no marks
                echo 0
            # now we get at least 4 marks... is it semantically valid?
            else
                if [[ -n "$semantic_error" ]]; then
                    # no
                    echo 4
                else
                    # yes, semantic error. BUT 
                    echo 5
                fi
            fi
        fi
    fi
    #echo "Outfile said: $( cat $outfile )" 1>&2
    #echo "Errfile said: $( cat $errfile )" 1>&2
    
    echo "Syntax error: ${syntax_error:-no}" 1>&2
    echo "Missing some necessary parts: ${failed:-no}" 1>&2
    echo "Semantic error: ${semantic_error:-no}" 1>&2
    rm -f "$outfile"
    rm -f "$errfile"
}

# NOTE: currently, automark calls test_submission, which calls the
# feedback program on an extracted tarball.
# Instead, I think 
# - the feedback program should call automark on a directory
# - the submission-$n-feedback file should contain exactly what the feedback program writes
# - the automarker should run the tests, and then scavenge for partial credit
#    ... or should it assume tests have already run? We wanted to cache the output.

# This function writes tab-separated marks to stdout
# and student-meaningful feedback on stderr.
automark () {
    local u="$1"
    local n="$2"
    local f="${3:+${dir}/$3}"
    shift; shift; shift
    echo "Automarking ${u}'s project $n submission ($f)" 1>&2
    echo -n "${u}"$'\t'"${n}"$'\t'"${f}"$'\t'
    if [[ "$n" -eq 4 ]]; then
        automark_proj4 "$u" "$f" "$start_d"/"$u"/submission-4
        return $?
    else
    declare -A mark_for_gate
    declare -A feedback_for_gate
    # We want an extracted, fixed-up version of the submission.
    # That is "$start_d"/"$u"/submission-${n}
    # HACK: we used to store a *pre*-fixup extracted tarball in the submission dir.
    # If we re-run this logic, we never fix it up, and it gets lower marks.
    # But I don't want to nuke and re-fixup all the dirs because that would
    # undo manual interventions. So we support an environment override
    # SUBMISSION_DIR_IS_NOT_FIXED_UP
    # that re-runs the fixup function. It's in test_submission_dir_postfixup.
    # The test functions always output to stdout, but we echo it to stderr.
    feedback="$( cat "$start_d"/"$u"/submission-${n}-testcache 2>/dev/null || \
        ( test_submission_dir_postfixup "$n" "$start_d"/"$u"/submission-${n} | \
        tee "$start_d"/"$u"/submission-${n}-testcache ) )"
    echo "Automarker's 'feedback' var follows." 1>&2
    echo "$feedback" 1>&2
    while read gate; do
        #echo "gate: $gate" 1>&2
        if [[ -n "$gate" ]]; then
            feedback_for_gate[$gate]="$( echo "$feedback" | sed -rn \
              "/^=== TESTING: ${gate} /,/^===/ p" )"
        fi
        case "$gate" in
            ('') continue ;;
            (Add8|Inc8|RAM8|RAM16K|Register) mark_for_gate[$gate]=5;;
            (PC|ALU) mark_for_gate[$gate]=12;;
            (Memory|CPU|Computer) mark_for_gate[$gate]=10;;
            (*) mark_for_gate[$gate]=3;;
        esac
    done<<< "$( echo "$feedback" | awk '
        /^=== SUCCESS: .*/ { print $3 }
    ' )"
    var=proj${n}_gates
    for gate in ${!var}; do
        #echo "gate: $gate"
        if [[ "$n" -eq 5 ]] && [[ ${mark_for_gate[$gate]} -eq 0 ]]; then
            submission_file="$( find "$start_d"/"$u"/submission-${n} -iname "$gate".hdl 2>/dev/null | head -n1 )"
            if [[ -n "$submission_file" ]]; then
                echo "Will try for partial credit on file $submission_file" 1>&2
                mark_for_gate[$gate]="$( automark_proj5_partial_credit \
                   "$u" "$submission_file" "$gate" )"
            else
                echo "Did not find a viable HDL file for gate ${gate}, so not trying partial credit" 1>&2
            fi
        fi
        mark="${mark_for_gate[$gate]}"
        echo -n "${mark:-0}"$'\t'
    done
    echo
    fi
}

quiz () {
    cd "$dir"
    local n="$1"
    shift
    for q in 1 2 3; do echo $'user\tproj\tfile\thint\tmark\tanswer' > \
     "$start_d"/quiz-${n}-${q}.tsv
    done
    for u in `users`; do
        read dummy_u dummy_n f <<<"$( submission_for_user "$u" "$n" )"
        if [[ -z "$f" ]]; then
            echo "No submission for user $u project $n" 1>&2
            continue
        fi
        echo "Extracting quiz answers from ${u}'s project $n submission ($f)" 1>&2
        local d="$( mktemp -d )"
        (cd "$d" && tar -xf "$dir"/"$f" )
        for q in 1 2 3; do
            case "$n"-"$q" in
                (3-3)
                    hint="$( find "$d" -iname '*.hdl' -print0 | xargs -r -0 stat -c'%s' | \
                       awk 'BEGIN { count=0; }
                       { count += $0 }
                       END { print (100 * count / 16384) }' )"
                ;;
                (*)
                    hint=""
                ;;
            esac
            echo -n "${u}"$'\t'"${n}"$'\t'"$( basename "${f}" )"$'\t'"${hint}"$'\t\t' \
                >> "$start_d"/quiz-${n}-${q}.tsv
            found="$( find "$d" -iname "q*${q}.txt" 2>/dev/null )"
            if [[ -z "$found" ]]; then
                echo "NS" >> "$start_d"/quiz-${n}-${q}.tsv
                continue
            fi
            case "$( echo "$found" | wc -l )" in
                ('')
                    echo "Some problem" 1>&2
                ;;
                (1)
                    (cat "$found" | tr '\n' '\f' | tr -d '\r' | sed 's/\f/\\n/g'; echo) \
                       >> "$start_d"/quiz-${n}-${q}.tsv
                ;;
                (0)
                    # this line isn't hit because 'find' will always print one newline
                    echo "No answer for question ${q} found in $f" 1>&2
                ;;
                (*) echo "MULTIPLE" >> "$start_d"/quiz-${n}-${q}.tsv
                    #ore than one potential answer found for question ${q} in ${f}: $found" 1>&2
                ;;
            esac
            
        done
        rm -rf "$d"
    done
}
# for project 3 question 3 we also want to compute the
# size in bytes of all HDL files in the submission

extract_user_proj () {
    local u="$1"
    local n="$2"
    read dummy_u dummy_n f <<<"$( submission_for_user "$u" "$n" )"
    d="$( mktemp -d )"
    cd "$d" && tar -xf "$dir"/"$f"
    echo "$d"
}

eyeball () {
    local n="$1"
    shift
    for u in `users`; do
        read dummy_u dummy_n f <<<"$( submission_for_user "$u" "$n" )"
        test -n "$f" || (echo "No submission for $n from $u" 1>&2; false) || continue
        d="$( extract_user_proj "$u" "$n" )"
        (cd "$d"
        # just make a big scrollable concatenation gate-by-gate,
        # labelled with user, fname and mark for that gate
        var=proj${n}_gates
        # we also read the automarks for this user
        read ${!var} <<< "$( cat "$start_d"/automarks-${n}.tsv | grep "^${u}"$'\t' | cut -f4- )"
        for gate in ${!var}; do
            echo "${u}'s automark for $gate is ${!gate}" >> "$start_d"/eyeball-"$gate"
            echo "${u}'s automark for $gate is ${!gate}" 1>&2
            automark="${!gate}"
            echo ">>>>>>>>>> $gate $u $f (automark: ${automark}) <<<<<<<<<<" >> "$start_d"/eyeball-"$gate"
            find -iname "${gate}.hdl" -print0 | xargs -r -0 cat >> \
                "$start_d"/eyeball-"$gate"
        done
        )
        rm -rf "$d"
    done
}

apply_adj () {
    local u=$1
    local label=$2
    local varname=$3
    shift; shift; shift
    adj="$( cat "$start_d"/sanity-partial.tsv | tr -d '"' | grep "^${u}"$'\t'"$label"$'\t' | cut -f3- )" #'
    if [[ -z "$adj" ]]; then
        echo "(none)"
    else
        echo
        echo "$adj"
    fi
    while read kind adj; do
        #echo "Applying adj $adj of kind $kind to $u, varname $varname" 1>&2
        if [[ -z "$adj" ]]; then continue; fi
        # workaround: adj may be negative, and bash arithmetic syntax is too stupid for unary -
        case "$adj" in
            (-*)
                eval ${varname}=$(( ${!varname} + 0 $adj ))
                ;;
            (*)
                eval ${varname}=$(( ${!varname} + $adj ))
                ;;
        esac
        #echo "$varname is now ${!varname}" 1>&2
    done<<<"$adj"
}

# Generate the student's report for all projects in projnums (i.e. the assessment overall).
# FIXME: we go to some length to work around the fact that many students subimtted
# work with the wrong project number, e.g. they did
# /courses/co557/submit 1 /path/to/my/project2
# and so on.
# This was a one-time somewhat-manual effort yielding the file
# "$start_d"/reclassify-actual-take2.log, used below.
# The right thing to do is for the feedback program to refuse to accept insane submissions,
# using the 'check_sanity' hook. FIXME: implement this.
report () {
    local u="$1"
    local report="$2"
    shift; shift
    # projnums are now in $@
    # per-user report: create/truncate the file and ensure [only]
    # user has access
    if [[ -z "$report" ]]; then report="$start_d"/report-$u.txt; fi
    touch "$report" 
    truncate -s0 "$report"
    chmod 0600 "$report"
    setfacl -m m:r "$report"
    setfacl -m u:${u}:r "$report"
    setfacl -m g:csstaff:r "$report"
    (
    echo "Submissions received (chronologically) and deadlines: "
    (cd "$dir" &&  (
    for n in $@; do
        for f in $( cd "$dir" && ls 0${n}-${u}-*.tar 2>/dev/null ); do
           sanity="$( sanity_of_tar_as_project $n "$dir"/"$f" )"
           if [[ $sanity -eq 0 ]]; then
              max_other_sanity=0
              max_other_sanity_as=$n
              for other_n in $@; do
                if [[ $n -eq $other_n ]]; then continue; fi
                echo "Trying other_n $other_n" 1>&2
                other_sanity="$( sanity_of_tar_as_project $other_n "$dir"/"$f" )"
                if [[ $other_sanity -gt $max_other_sanity ]]; then
                   max_other_sanity=$other_sanity
                   max_other_sanity_as=$other_n
                fi
              done
              if [[ $max_other_sanity -gt 0 ]]; then
                  sanity="0, but most sane as proj $max_other_sanity_as [$max_other_sanity]"
              else
                  sanity="0, and no better as any other project in $@"
              fi
           fi
           stat -c"%y %n %s"$'\t'"(sanity as project $n: $sanity)" "$f"
        done
        user_deadline="$( cd "$dir" && ls deadline-${n}-${u} 2>/dev/null )"
        if [[ -n "$user_deadline" ]]; then
            (cd "$dir" && stat -c"%y ------------------------- %n" $user_deadline)
        else
            (cd "$dir" && stat -c"%y ------------------------- %n" deadline-${n})
        fi
    done) | sort)
    echo
    
    echo "Submissions reclassified as a different project: "
    reclass="$( cat "$start_d"/reclassify-actual-take2.log | \
      sed -nr "/^Reclassifying.*(0[0-9]-${u}-[0-9a-z]{6}\.tar.*)/ {s//\1/;p}" )"
    if [[ -n "$reclass" ]]; then echo "$reclass"; else echo "(none)"; fi
    echo
    for n in $@; do
        declare sub${n}="$(submission_for_user "$u" ${n} | cut -f3- ; test "${PIPESTATUS[0]}" -eq 0 || echo "(none)")"
        declare initial_sub${n}="$(initial_submission_for_user "$u" ${n} | cut -f3- ; test "${PIPESTATUS[0]}" -eq 0 || echo "(none)")"
        varname=sub${n}
        initial_varname=initial_sub${n}
        echo -n "Project ${n}: submission marked: "; echo -n "${!varname}"; if [[ "${!varname}" != "${!initial_varname}" ]]; then echo " (MANUALLY OVERIDDEN)" ; else echo; fi
    done
    echo
    echo
    
    # mark totals for each project
    # array indexed from zero, so 0 is for 'project 0' which we just set to 0
    declare -a totals
    totals=(0 51 34 45 36 34)
    maxmark=0
    for n in $@; do
        maxmark=$(( $maxmark + ${totals[$n]} ))
    done
    
    grand_total=0
    for n in $@; do
        echo "=========="
        echo "Project $n"
        echo "=========="
        proj_mark=0
        read dummy_u dummy_n f <<<"$( submission_for_user "$u" "$n" )"
        test -n "$f" || (echo "No submission for $n from $u" 1>&2;
            echo "(no markable submission)"; false) || continue
        #d="$( extract_user_proj "$u" "$n" )"
        #pushd "$d" >/dev/null
        
        if [[ $n -eq 4 ]]; then
            # Automarks result from running the assembly validator on 
            read div toggle <<< "$( cat "$start_d"/"$u"/automarks-4.tsv | cut -f3- )"
            proj_mark=0
            for prog in div toggle; do
                if [[ -z "${!prog}" ]]; then declare ${prog}=0; fi
                echo "Program '$prog' automark:    " ${!prog}
                echo -n "Program '$prog' manual adjustments: "
                apply_adj "$u" "$prog" $prog
                #echo "$prog is now ${!prog}" 1>&2
                echo '--------------'
                echo "Program total: ${!prog}"
                echo
                proj_mark=$(( $proj_mark + ${!prog} ))
            done
        else
        # just make a big scrollable concatenation gate-by-gate,
        # labelled with user, fname and mark for that gate
        var=proj${n}_gates
        # we also read the automarks for this user
        read ${!var} <<< "$( cat "$start_d"/"$u"/automarks-${n}.tsv | cut -f3- )"
        for gate in ${!var}; do
            echo "Gate $gate automark: ${!gate}"
            gate_mark="${!gate}"
            gate_mark="${gate_mark:-0}"
            #echo -n "Gate $gate default adjustment: "
            #if [[ ${!gate} -gt 0 ]]; then
            #    echo 1
            #    gate_mark=$(( $gate_mark + 1 ))
            #else
            #    echo 0
            #fi
            echo -n "Gate $gate manual adjustments: "
            apply_adj "$u" "$gate" gate_mark
            echo '--------------'
            echo "Gate total: $gate_mark"
            echo
            proj_mark=$(( $proj_mark + $gate_mark ))
        done
        fi
        echo
        for q in 1 2 3; do
            echo -n "Quiz question $q mark (out of 2): "
            q_hint="$( cat "$start_d"/quiz-${n}-${q}+marks.tsv | tr -d '"' | grep "^${u}"$'\t' | cut -f4 )" #'
            q_mark="$( cat "$start_d"/quiz-${n}-${q}+marks.tsv | tr -d '"' | grep "^${u}"$'\t' | cut -f5 )" #'
            q_answer="$( cat "$start_d"/quiz-${n}-${q}+marks.tsv | tr -d '"' | grep "^${u}"$'\t' | cut -f6- | sed 's/\t*$//' | sed 's/\t/\\t/g'  )" #'
            if [[ -n "$q_mark" ]]; then
                echo -n "$q_mark    (answer seen: $q_answer)"
                if [[ -n "$q_hint" ]]; then
                    echo "      (hint was: $q_hint)"
                else
                    echo
                fi
            else
                echo "(no mark assigned -- this may be a bug in the reporting system)"
                q_mark=0
            fi
            proj_mark=$(( $proj_mark + $q_mark ))
        done
        echo
        echo '=============='
        echo "Project total (out of ${totals[$n]}): $proj_mark"
        echo
        grand_total=$(( $grand_total + $proj_mark ))
        #popd >/dev/null
        #rm -rf "$d"
    done
    echo
    echo "Grand total (out of $maxmark)": $grand_total
    ) >> "$report"
}
