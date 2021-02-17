#!/bin/bash

repo="$( readlink -f "$( dirname "$0" )" )"

# arguments:
# the module code
# the clone dest  (must NOT be nosuid; default /usr/l/courses/${code})
code="$1"
dest="$2"

case "$code" in
	([cC][oO][0-9][0-9][0-9])
		true # OK
	;;
	(*)
		echo "'$code' doesn't look like a module code; should be COnnn" 1>&2
        echo "Or for non-Computing modules, please hack the $0 script" 1>&2
		exit 1
	;;
esac

code="$( echo "$code" | tr 'A-Z' 'a-z' )"
# by default clone into /usr/l/courses/coNNN/autofeedback-coNNN
# but also allow non-default clone destination
# and hint about asking syshelp
default_dest=/usr/l/courses/${code}/autofeedback-"$code"
if [[ -z "$dest" ]]; then dest="$default_dest"; fi

! test -e "$dest" || (echo "Destination already exists: $dest" 1>&2; false) || exit 1
dir="$( dirname "$dest" )"
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
	echo "Suggest asking cs-syshelp@kent.ac.uk to create $(dirname "$default_dest")" 1>&2
	exit 1
fi

cd "$dir" || (echo "Couldn't cd to $dir"; false) || exit 1
git clone "$repo" autofeedback-$code || exit 1
cd autofeedback-$code
# create lib${MODULE} as a dummy with one project
git clone "$repo"/libSKELETON lib$code
cat >config.mk <<EOF
MODULE := $(echo $code | tr a-z A-Z)
LECTURER := `whoami` # the cloning user
EOF
