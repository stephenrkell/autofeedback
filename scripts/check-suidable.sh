#!/bin/bash

dir="$1"
test -n "$dir" || (echo "Please specify a directory."; false) || exit 1
test -d "$dir" || (echo "Destination's containing directory must exist: $dir" 1>&2; false) || exit 1
# it should not be nosuid
mtpt="$( stat -c %m -- "$dir" )"
if [[ -z "$mtpt" ]]; then
        echo "Couldn't get mount point for $dir" 1>&2
        exit 1
fi
mtflags="$( join -t$'\t' <( cat /proc/mounts | tr -s '[:blank:]' '\t' | cut -f2- | sort ) \
    <( echo "$mtpt" ) | cut -f3 | tr ',' ' ' )"

if grep -q nosuid <<<"$mtflags"; then
        echo "Destination $dir is mounted nosuid, so is not sui[dt]able for use" 1>&2
        echo "Suggest asking cs-syshelp@kent.ac.uk to create /usr/l/courses/$(basename "$(readlink -f "$dir")")" 1>&2
        exit 1
fi
true
