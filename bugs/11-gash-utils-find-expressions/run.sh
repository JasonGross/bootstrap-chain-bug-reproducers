#!/usr/bin/env bash
# gash-utils-find-expressions: gash-utils' find(1) implements NO POSIX
# expression predicates -- its getopt-long option-spec is just ((help)
# (version)), so `-name` is parsed as a cluster of short options (-n -a -m -e)
# and rejected.  find then writes its diagnostic to stderr, exits 1, and
# writes NOTHING to stdout -- and the overwhelmingly common caller idiom is
# command substitution, which reads stdout and ignores the status.
# GREEN == `find d -name '*.o'` yields empty stdout + rc=1 + "no such option:
# -n", the exact libtool gather yields an EMPTY object list and therefore a
# 0-member archive, while GNU find (control) finds the objects and the same
# gather produces a correctly populated archive.
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

command -v guile >/dev/null || die "need guile 3.x (apt: guile-3.0)"
command -v ar >/dev/null || die "need binutils ar"

GASH_URL=https://download.savannah.gnu.org/releases/gash/gash-0.2.0.tar.gz
GASH_SHA=ee4158040800fd3cf5e02c32ee9a659a067c592f999b5c01e943da04cbf7a08e
GASHU_URL=https://download.savannah.gnu.org/releases/gash/gash-utils-0.2.0.tar.gz
GASHU_SHA=e6aae5a6f40fdf8c5f8730f66c3f8c3047bde00f8cd97595f5aad2444959d4a3

mkdir -p work
fetch "$GASH_URL"  "$GASH_SHA"  work/gash-0.2.0.tar.gz
fetch "$GASHU_URL" "$GASHU_SHA" work/gash-utils-0.2.0.tar.gz
[ -d work/gash-0.2.0 ]       || tar -xzf work/gash-0.2.0.tar.gz -C work
[ -d work/gash-utils-0.2.0 ] || tar -xzf work/gash-utils-0.2.0.tar.gz -C work
GASH=$PWD/work/gash-0.2.0
GASHU=$PWD/work/gash-utils-0.2.0
# Both release tarballs ship their generated config.scm, so the modules run
# straight from the unpacked trees -- no autotools build, nothing patched.
export GUILE_LOAD_PATH="$GASHU:$GASH"

gash_find () { guile --no-auto-compile -e main -s "$BUGDIR/gash-find.scm" "$@"; }

banner "THE ACCUSED SOURCE: gash-utils-0.2.0 gash/commands/find.scm"
sha256sum "$GASHU/gash/commands/find.scm"
sed -n '/^(define (find/,/^    ;; and options/p' "$GASHU/gash/commands/find.scm"
grep -q "'((help)" "$GASHU/gash/commands/find.scm" \
  || die "expected the ((help) (version)) option-spec"
loud "the option-spec is ((help) (version)) -- no -name/-print/-type/-o/-a;"
loud "the file's own TODO records that expressions are unimplemented."

banner "FIXTURE: a directory holding one .o, one .lo and one unrelated file"
rm -rf work/d && mkdir -p work/d
: > work/d/a.o
: > work/d/b.lo
: > work/d/c.txt
find work/d -type f | sort | sed 's/^/    /'

banner "REPRODUCE 1/3: the minimal case, gash-utils find vs GNU find"
set +e
gash_out=$(gash_find work/d -name '*.o' 2>work/err1.txt); gash_rc=$?
set -e
gnu_out=$(find work/d -name '*.o')
echo "  gash-utils find work/d -name '*.o'"
echo "    stdout : [${gash_out}]"
echo "    stderr : $(cat work/err1.txt)"
echo "    status : $gash_rc"
echo "  GNU find work/d -name '*.o'   (control)"
echo "    stdout : [${gnu_out}]"
[ -z "$gash_out" ] || die "bug did NOT reproduce: gash find printed '$gash_out'"
[ "$gash_rc" = 1 ] || die "expected rc=1 from gash find, got $gash_rc"
grep -q 'no such option: -n' work/err1.txt \
  || die "expected 'no such option: -n' -- got: $(cat work/err1.txt)"
[ "$gnu_out" = "work/d/a.o" ] || die "control failed: GNU find printed '$gnu_out'"
loud "BUG: '-name' is read as the short-option cluster -n -a -m -e; empty stdout, rc=1."

banner "REPRODUCE 2/3: -print alone fails the same way (on '-p')"
set +e
gash_find work/d -print >work/out2.txt 2>work/err2.txt; rc2=$?
set -e
echo "    stderr : $(cat work/err2.txt)   status: $rc2"
grep -q 'no such option: -p' work/err2.txt || die "expected 'no such option: -p'"
loud "so EVERY POSIX find expression is rejected, not just -name."

banner "CONTEXT: bare 'find DIR' works -- which is why nothing complains early"
gash_find work/d | sort | sed 's/^/    /'
gash_find work/d | grep -q 'work/d/a.o' || die "bare find should list the tree"
loud "a bootstrap can run a long way on this before anything looks wrong."

banner "REPRODUCE 3/3: the real damage -- GNU libtool's func_extract_archives gather"
loud "gcc-4.7.4 ltmain.sh line 2935 (func_extract_archives) runs, verbatim:"
loud '    my_oldobjs="$my_oldobjs "`find $my_xdir -name \*.$objext -print -o -name \*.lo -print | $NL2SP`'
loud "i.e. command substitution: stdout is the object list, status is IGNORED."
set +e
objs_gash=$(gash_find work/d -name '*.o' -print -o -name '*.lo' -print 2>work/err3.txt)
set -e
objs_gnu=$(find work/d -name '*.o' -print -o -name '*.lo' -print)
echo "  object list gathered with gash-utils find : [${objs_gash}]"
echo "  object list gathered with GNU find        : [$(echo $objs_gnu)]"
rm -f work/lib-gash.a work/lib-gnu.a
# Exactly what libtool does next -- note it does not check the gather at all.
ar rc work/lib-gash.a $objs_gash 2>/dev/null || true
ar rc work/lib-gnu.a  $objs_gnu
n_gash=$(ar t work/lib-gash.a 2>/dev/null | grep -c . || true)
n_gnu=$(ar t work/lib-gnu.a | grep -c .)
echo "  ar rc <gash gather>  -> $n_gash member(s), $(stat -c%s work/lib-gash.a) bytes"
echo "  ar rc <GNU gather>   -> $n_gnu member(s), $(stat -c%s work/lib-gnu.a) bytes"
[ -z "$objs_gash" ] || die "expected an EMPTY gather from gash find"
[ "$n_gash" = 0 ] || die "expected a 0-member archive from the empty gather"
[ "$n_gnu" = 2 ]  || die "control failed: expected 2 members, got $n_gnu"
loud "the ar command SUCCEEDS and produces a valid but empty archive."

banner "VERDICT"
loud "BUG REPRODUCED: gash-utils 0.2.0 find supports no expression predicates;"
loud "'-name'/'-print' are parsed as short-option clusters and rejected, stdout"
loud "is empty, and the status-ignoring command-substitution idiom that every"
loud "libtool uses turns that into a silently truncated archive."
loud "In the nix-bootstrapping arm ladder this produced a libstdc++.a with 8"
loud "members (~67 KB) instead of 124 -- and nothing failed until the first C++"
loud "link much later, far from the cause.  Same silent-degradation class as"
loud "the gash EXIT_SUCCESS gate (bug 6 in this repo)."
echo "PASS: gash-utils-find-expressions reproduced"
