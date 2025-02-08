# interface to write-feedback scripts:
# submission file on stdin (tar, git, ...)
# feedback goes to stdout
# stderr is stderr
# fds 3 and 4 are NOT to be used -- bash will use them itself
# fd 7: the dirfd
# fd 8; the audit log

# set COLUMNS
if [[ -z "$COLUMNS" ]]; then
    # assume stderr is connected to tty -- we know stdin isn't, and
    # stdout won't be when we're inside a $( .. ) or `...` subshell
    COLUMNS="$( stty size <`readlink -f /proc/self/fd/2` | tr -s '[:blank:]' '\t' | cut -f2 )"
fi
if [[ -z "$COLUMNS" ]]; then
    echo "WARNING: guessing that your window is 80 columns wide."
    echo "To avoid this guesswork, do 'export COLUMNS' from your shell."
    COLUMNS=80
fi

# use some VT100/ANSI escape magic to do red+bold writing on the given line
lines_with_highlight_at () {
   (cat ; echo "(end of file)") | cat -n | \
    sed "$1 s/.*/\x1b[31m\x1b[1m&\x1b[0m/"
}

line_n () {
    tail -n+$1 | head -n1 | tr -d '\n'; echo
}

audit_log_date_prefix () {
    date --utc '+%F %T ' | tr -d '\n'
}

audit_log_message () {
    local msg="$1"
    local line_num="$2" # might be empty
    # the file, whose line number it is, should be on stdin
    (audit_log_date_prefix; echo "$msg" ) >&8
}
