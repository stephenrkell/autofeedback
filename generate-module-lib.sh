#!/bin/bash

repo="$( readlink -f "$( dirname "$0" )" )"

# arguments:
# the module code
case "$1" in
	([cC][oO][0-9][0-9][0-9])
		true # OK
	;;
	(*)
		echo "'$1' doesn't look like a module code; should be COnnn" 1>&2
        echo "Or for non-Computing modules, please hack the $0 script" 1>&2
		exit 1
	;;
esac
# 'code' means lowercase
code="$( echo "$1" | tr 'A-Z' 'a-z' )"

# We generate a per-module lib$code/ tree in $repo.
# After this, it can be customised to the module (or not!)
mkdir -p "$repo"/lib$code
cp -rp "$repo"/libSKELETON/* "$repo"/lib$code/
git branch local-$code
git checkout local-$code
git add lib${code}/* lib${code}/scripts/*
git branch -v
git status
echo "Created the module library in lib$code on the 'local-$code' git branch" 1>&2
echo "Please edit the new files as necessary, then commit them." 1>&2
echo "Suggest merging this into a common local branch named after your institution" 1>&2
echo "Please push any generic 'autofeedback' changes to the main branch." 1>&2
