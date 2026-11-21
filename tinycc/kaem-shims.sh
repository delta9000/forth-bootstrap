# tinycc/kaem-shims.sh -- the commands live-bootstrap's kaem scripts call
# that the junction's chroot does not have, as bash functions.
#
# tests/tinycc/junction-check.sh sources this file and then runs lines of
# live-bootstrap's own steps/mes-0.28/pass1.kaem and
# steps/tcc-0.9.26/pass1.kaem in bash.  In live-bootstrap these are kaem
# builtins or stage0-posix mescc-tools-extra programs; here each is the
# host tool with the same effect on the files.  None of them compiles
# anything or touches a file a compiler reads except as stated.
#
#   catm OUT [IN...]      OUT is the concatenation of IN (empty with no IN)
#   match A B             true when A and B are the same string
#   mkdir DIR...          create each DIR; an existing DIR is an error, as
#                         with mescc-tools-extra mkdir without -p
#   ungz --file IN --output OUT        gunzip IN to OUT
#   untar [--non-strict] --file IN     unpack IN into the current directory
#   simple-patch FILE BEFORE AFTER     replace the one occurrence of
#                         BEFORE's bytes in FILE with AFTER's (fails when
#                         BEFORE occurs other than once)
#   checksum-transcriber SOURCES       write SOURCES.SHA256SUM with one
#                         "SHA256  $DISTFILES/NAME" line per "f URL SHA256
#                         [NAME]" line, as steps/checksum-transcriber-1.0 does
#
# TINYCC_SHIMS is the directory holding this file and simple-patch.py.

catm() {
    local out=$1
    shift
    cat "$@" < /dev/null > "$out"
}

match() {
    [ "$1" = "$2" ]
}

mkdir() {
    command mkdir "$@"
}

ungz() {
    local in= out=
    while [ $# -gt 0 ]; do
        case $1 in
            --file) in=$2; shift 2 ;;
            --output) out=$2; shift 2 ;;
            *) echo "ungz: unexpected argument $1" >&2; return 1 ;;
        esac
    done
    gzip -dc < "$in" > "$out"
}

untar() {
    local in=
    while [ $# -gt 0 ]; do
        case $1 in
            --non-strict) shift ;;
            --file) in=$2; shift 2 ;;
            *) echo "untar: unexpected argument $1" >&2; return 1 ;;
        esac
    done
    tar --no-same-owner -xf "$in"
}

simple-patch() {
    "$TINYCC_PYTHON" -I "$TINYCC_SHIMS/simple-patch.py" "$@"
}

checksum-transcriber() {
    local src=$1 kind url sum name
    : > "$src.SHA256SUM"
    while read -r kind url sum name; do
        case $kind in f|file) ;; *) echo "checksum-transcriber: $kind" >&2; return 1 ;; esac
        [ -n "$name" ] || name=${url##*/}
        printf '%s  %s/%s\n' "$sum" "$DISTFILES" "$name" >> "$src.SHA256SUM"
    done < "$src"
}
