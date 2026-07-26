#!/usr/bin/env bash
# bootar-xz-multiblock: the R6RS `compression` library that Bootar ships
# (git.ngyro.com/r6rs-compression, pinned by bootar's make-ses.scm) crashes
# decoding any XZ stream containing MORE THAN ONE BLOCK.  xz.scm stores the
# eof-object that lzma2-decode-chunk returns at end-of-block back into
# lzma2-state and never resets it; the eof-object is truthy, so the next
# block's (or state (empty-state)) keeps it and vector-ref fails on #<eof>.
# Size is a red herring -- large inputs merely tend to be multi-block.
# GREEN == a 62-block .xz crashes with vector-ref on #<eof>, the SAME BYTES
# as a 1-block .xz decode fine (control), and the two-line state reset makes
# the multi-block file decode byte-identically (fix control).
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

command -v guile >/dev/null || die "need guile 3.x (apt: guile-3.0)"
command -v xz >/dev/null || die "need xz-utils"

# The three repos and commits bootar's make-ses.scm pins (bootar v1b).
COMPRESSION_URL=https://git.ngyro.com/r6rs-compression
COMPRESSION_COMMIT=a2d01f24d5ad703ed2742b97053d19dcd42f89b1
STRUCT_PACK_URL=https://gitlab.com/weinholt/struct-pack.git
STRUCT_PACK_COMMIT=11b71963793ed4a3bf761efdd83cf2fe123239ee
HASHING_URL=https://gitlab.com/weinholt/hashing.git
HASHING_COMMIT=eb28080180b5fdfb6ffc74f8cdf2c1a7823ef0cb

mkdir -p work

clone_at () { # clone_at <url> <commit> <dir>
  local url="$1" commit="$2" dir="$3"
  if [ ! -d "$dir/.git" ]; then
    loud "fetching $url @ ${commit:0:12}"
    git init -q "$dir"
    if ! git -C "$dir" fetch -q --depth 1 "$url" "$commit" 2>/dev/null; then
      loud "  (shallow by-sha fetch refused; full clone)"
      git -C "$dir" fetch -q "$url"
    fi
    git -C "$dir" checkout -q "$commit"
  fi
  [ "$(git -C "$dir" rev-parse HEAD)" = "$commit" ] || die "wrong commit in $dir"
}

banner "FETCH: the exact library commits bootar v1b pins in make-ses.scm"
clone_at "$COMPRESSION_URL"  "$COMPRESSION_COMMIT"  work/compression
clone_at "$STRUCT_PACK_URL"  "$STRUCT_PACK_COMMIT"  work/struct-pack
clone_at "$HASHING_URL"      "$HASHING_COMMIT"      work/hashing
git -C work/compression log -1 --format='compression: %H %s'

banner "THE ACCUSED CODE: xz.scm's block loop never resets the LZMA2 state"
grep -n -A2 'set! lzma2-state (lzma2-decode-chunk' work/compression/xz.scm
loud "lzma2-decode-chunk RETURNS the eof-object to signal end-of-block:"
grep -n '((#x00) (eof-object))' work/compression/lzma2.scm
loud "and it destructures its state argument with vector-ref:"
grep -n -A1 '(let ((state (or state (empty-state))))' work/compression/lzma2.scm
loud "the eof-object is TRUTHY, so (or state (empty-state)) keeps it and the"
loud "next block's vector-ref gets #<eof>.  A 1-block stream never re-enters."

banner "BUILD: lay the R6RS sources out for Guile (rename only, no edits)"
rm -rf work/lib && mkdir -p work/lib
python3 build-libtree.py work/lib \
  work/compression:compression \
  work/hashing:hashing \
  work/struct-pack:struct
export GUILE_LOAD_PATH="$PWD/work/lib"

banner "FIXTURE: one payload, compressed two ways (this is the whole point)"
python3 - work/payload.bin <<'PY'
import random, sys
# deterministic, and compressible enough to be realistic without being trivial
random.seed(20260726)
words = [bytes(random.randrange(32, 127) for _ in range(random.randrange(3, 12)))
         for _ in range(512)]
out = bytearray()
while len(out) < 4_000_000:
    out += random.choice(words) + b" "
    if random.randrange(12) == 0:
        out += b"\n"
open(sys.argv[1], "wb").write(bytes(out))
PY
xz -k -c --block-size=65536 work/payload.bin > work/multi.xz
xz -k -c                    work/payload.bin > work/single.xz
payload_sha=$(sha256sum work/payload.bin | cut -d' ' -f1)
n_multi=$(xz --list work/multi.xz | awk 'NR==2 {print $2}')
n_single=$(xz --list work/single.xz | awk 'NR==2 {print $2}')
echo "  payload      : $(stat -c%s work/payload.bin) bytes  sha256 ${payload_sha:0:16}…"
echo "  multi.xz     : $n_multi blocks"
echo "  single.xz    : $n_single blocks"
[ "$n_single" = 1 ] || die "expected single.xz to have exactly 1 block"
[ "$n_multi" -gt 1 ] || die "expected multi.xz to have >1 block"

banner "CONTROL 1: the SINGLE-block stream decodes correctly"
guile --no-auto-compile -s decode.scm work/single.xz work/out-single.bin
cmp work/out-single.bin work/payload.bin || die "single-block decode was not byte-identical"
loud "CONTROL OK: 1-block .xz decodes byte-identically -- the library works."

banner "REPRODUCE: the SAME BYTES as a MULTI-block stream crash the decoder"
set +e
guile --no-auto-compile -s decode.scm work/multi.xz work/out-multi.bin > work/multi.log 2>&1
rc=$?
set -e
sed 's/^/    /' work/multi.log | tail -12
[ "$rc" != 0 ] || die "bug did NOT reproduce: the multi-block decode succeeded"
grep -q 'vector-ref' work/multi.log \
  || die "expected a vector-ref failure -- got the above instead"
grep -q '#<eof>' work/multi.log \
  || die "expected #<eof> as the offending argument"
loud "BUG REPRODUCED: vector-ref got #<eof> -- the stale end-of-block state."
loud "This is the same failure, at the same source line, that a 78 MB"
loud "gcc-10.5.0.tar.xz produced through bootar after ~54 minutes:"
loud "  compression/lzma2.scm:51:2 lzma2-decode-chunk"
loud "    -> In procedure vector-ref: Wrong type argument (expecting vector): #<eof>"

banner "CONTROL 2: the two-line state reset fixes it (and does not regress)"
python3 - work/lib/compression/xz.scm <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text()
old = """              (let ((want (get-bytevector-n in check-length))
                    (have (check-finish! checksum)))
                (trace "LZMA2 block checksum: " want " <-> " have)
                (when (and have (not (equal? want have)))
                  (error who "There has been an LZMA2 block checksum mismatch."
                         want have))))))"""
new = """              (let ((want (get-bytevector-n in check-length))
                    (have (check-finish! checksum)))
                (trace "LZMA2 block checksum: " want " <-> " have)
                (when (and have (not (equal? want have)))
                  (error who "There has been an LZMA2 block checksum mismatch."
                         want have)))
              ;; Reset the per-block decoder state so that a following
              ;; block starts clean (XZ streams may hold many blocks).
              (set! lzma2-state #f)
              (set! checksum (check-init)))))"""
assert old in s, "patch anchor not found -- upstream changed?"
p.write_text(s.replace(old, new, 1))
print("    applied: (set! lzma2-state #f) + (set! checksum (check-init)) at end of block")
PY
guile --no-auto-compile -s decode.scm work/multi.xz work/out-multi-fixed.bin
cmp work/out-multi-fixed.bin work/payload.bin \
  || die "patched multi-block decode was not byte-identical"
loud "FIX OK: the 62-block stream now decodes byte-identically to the payload."
guile --no-auto-compile -s decode.scm work/single.xz work/out-single2.bin
cmp work/out-single2.bin work/payload.bin || die "patch regressed the single-block case"
loud "NO REGRESSION: the 1-block case still decodes byte-identically."
loud "(Resetting lzma2-state ALONE is not enough -- the next block then fails"
loud " its checksum, because the per-block check state is not reinitialized"
loud " either.  Both resets are needed; that second defect is why we say the"
loud " multi-block path was never exercised.)"

banner "VERDICT"
loud "BUG REPRODUCED: r6rs-compression @ ${COMPRESSION_COMMIT:0:12} (the commit"
loud "bootar v1b pins) cannot decode a multi-block XZ stream; the identical"
loud "payload as a single block decodes fine, and a two-line per-block state"
loud "reset makes the multi-block case decode byte-identically."
echo "PASS: bootar-xz-multiblock reproduced"
