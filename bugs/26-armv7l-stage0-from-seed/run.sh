#!/usr/bin/env bash
# armv7l-stage0-from-seed -- a DEMONSTRATION, not a bug reproducer.
#
# Claim being demonstrated: a native armv7l stage0 ladder exists and works
# FROM THE SEED.  Starting from ONE 460-byte hex0 machine-code image -- which
# this job RECONSTRUCTS from its commented listing rather than shipping as a
# blob -- the full kaem ladder builds hex1, hex2, catm, M0, a C compiler
# (cc_armv7l), M2-Planet, blood-elf, M1, hex2, kaem and the mescc-tools-extra
# utilities, and the resulting 20 binaries reproduce a checked-in
# `armv7l.answers` exactly.
#
# Why this is worth demonstrating: upstream stage0-posix has no armv7l ladder.
# The armv7l port is GAS-reference-only -- no hex0 seed, no kaem scripts, and
# no stage0-cc support layer -- so an armv7l stage0 has never been runnable
# from a seed anywhere.  This job is the evidence that one now is.
#
# Inverted convention vs the bug reproducers: here GREEN means the
# demonstration SUCCEEDED (see the repo README's note on demonstration jobs).
#
# GREEN == all of:
#   (a) SEED RECONSTRUCTED FROM TEXT: rendering the checked-in commented
#       listing `seed/hex0_armv7l.hex0` yields exactly the 460-byte seed
#       (sha256 pinned).  Nothing opaque is trusted: the bytes that run are
#       provably the bytes a human can audit in the listing.
#   (b) LADDER EDGE: that seed, run on itself, reproduces itself
#       (hex0(hex0_armv7l.hex0) == the seed) and builds the 1,162-byte kaem
#       seed (sha256 pinned).
#   (c) FROM-SEED ENFORCED, NOT ASSERTED: the tree is scanned and must contain
#       EXACTLY TWO pre-existing ELF binaries -- the two seeds above.  A third
#       ELF anywhere fails the job.  (Upstream ships executable *.sh test
#       scripts; those are not ELF and the ladder never invokes them.)
#   (d) THE LADDER RUNS: `kaem.armv7l` drives seed-kaem -> mini-kaem (phases
#       1-11) -> kaem.run -> full-kaem -> mescc-tools-extra, entirely under
#       binaries it built itself.
#   (e) ANSWERS REPRODUCE: `sha256sum -c armv7l.answers` prints OK for all 20
#       binaries -- once using the ladder's OWN chain-built sha256sum (as the
#       ladder's kaem.run does), and once using the runner's GNU coreutils
#       sha256sum.  Those two are an INDEPENDENT reference for each other;
#       see the labelling note below.
#   (f) KEY ARTEFACTS ARE BIT-REPRODUCIBLE: four intermediate binaries match
#       sha256 values fixed at authoring time on a different machine.
#   (g) RED LEGS FIRE (run every time, not just at authoring): corrupting one
#       byte of a built binary must make the answers check name that binary
#       FAILED, and planting a third ELF must make the from-seed scan fail.
#       A vacuous harness that always passed would be caught by these.
#
# WHAT THIS JOB DOES **NOT** CLAIM -- scope, stated so nothing is inferred:
#   * It makes NO cross-lineage byte-identity claim.  Separately (not here)
#     these artefacts have been reproduced by two other stage0 lineages, but
#     THIS job runs one lineage only, so it demonstrates from-seed
#     reproducibility, not lineage diversity.
#   * The two sha256sum implementations in (e) ARE mutually independent (a
#     chain-built C implementation vs GNU coreutils, sharing no code), which
#     is why both are run.  Everything else in this job is one implementation
#     checked against fixed values -- reproducibility, not independent
#     confirmation.  The distinction is deliberate: agreement between two
#     copies of the same implementation would prove portability, not
#     correctness, and is not claimed anywhere below.
#   * It says nothing about whether any of this should be adopted upstream.
#
# Red-for-the-right-reason: legs (g) run on every invocation and each fails
# with a NAMED assertion.  A third, more expensive red (perturbing one
# `--base-address` flag in mini-kaem so that exactly `armv7l/bin/M1` fails the
# answers check, and nothing else does) was verified at authoring time and is
# not re-run here because it doubles the ladder build.
cd "$(dirname "$0")"
. ../common.sh
DEMO_DIR=$PWD
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for t in git python3 sha256sum; do
  command -v "$t" >/dev/null || die "missing required tool: $t"
done

banner "0. environment: armv7l binaries must be executable on this runner"
# The ladder execs the ARM binaries it builds, so the runner needs an arm
# binfmt handler (the CI workflow installs one with docker/setup-qemu-action).
if [ ! -e /proc/sys/fs/binfmt_misc/qemu-arm ] && [ ! -e /proc/sys/fs/binfmt_misc/qemu-arm-static ]; then
  die "no arm binfmt handler registered -- cannot execute armv7l binaries"
fi
loud "arm binfmt handler present"

# ---------------------------------------------------------------------------
banner "1. fetch the pinned upstream sources (commit-hash verified)"
# The ladder's own files are checked in under payload/ (all TEXT -- listings,
# M1/hex2 sources and kaem scripts).  Everything else is upstream and is
# fetched fresh here at a pinned commit, then verified.
clone_pinned () { # clone_pinned <repo-url> <commit> <dest>
  local url="$1" commit="$2" dest="$3"
  loud "cloning $url @ $commit"
  git init -q "$dest"
  git -C "$dest" remote add origin "$url"
  if ! git -C "$dest" fetch -q --depth 1 origin "$commit" 2>/dev/null; then
    loud "shallow fetch of the exact commit failed; falling back to a full fetch"
    git -C "$dest" fetch -q origin || die "cannot fetch $url (host unreachable?)"
  fi
  git -C "$dest" checkout -q "$commit" 2>/dev/null || git -C "$dest" checkout -q FETCH_HEAD
  local got; got=$(git -C "$dest" rev-parse HEAD)
  [ "$got" = "$commit" ] || die "$dest: checked out $got, expected $commit"
  loud "  verified at $got"
  rm -rf "$dest/.git"
}
cd "$WORK"
clone_pinned https://github.com/oriansj/M2libc.git            68a23cfd05d5a355ba7a30c770d684cbe86fcc4e M2libc
clone_pinned https://github.com/oriansj/M2-Planet.git         bd2fe4b0659fd0ad3f476a5ad0ef801bd134665d M2-Planet
clone_pinned https://github.com/oriansj/M2-Mesoplanet.git     4b011a85da73a7c97212468d41f17e806ba99547 M2-Mesoplanet
clone_pinned https://github.com/oriansj/mescc-tools.git       5adfbf3364261a77109878a56b100aeeb6ef9ac4 mescc-tools
clone_pinned https://github.com/oriansj/mescc-tools-extra.git a151c245e512076971a3c85bb1502cf92cfa83b6 mescc-tools-extra

# ---------------------------------------------------------------------------
banner "2. lay out the tree (the ladder's own files are all TEXT)"
mkdir -p armv7l/artifact armv7l/bin bootstrap-seeds/POSIX/armv7l
cp "$DEMO_DIR"/payload/armv7l/* armv7l/
cp "$DEMO_DIR"/payload/seed/hex0_armv7l.hex0 "$DEMO_DIR"/payload/seed/kaem-minimal.hex0 armv7l/
cp "$DEMO_DIR"/payload/kaem.armv7l .
cp "$DEMO_DIR"/payload/armv7l.answers .
# after.kaem is the EMBEDDER's hook: kaem.run ends by exec'ing it, and
# upstream stage0-posix does not ship one either.  A no-op keeps the
# unmodified kaem.run runnable standalone.
printf '# standalone demonstration: no post-build hook\n' > after.kaem
loud "checked-in ladder files (all text, no binaries):"
find armv7l -maxdepth 1 -type f -printf '    %-32f %6s bytes\n' | sort

# ---------------------------------------------------------------------------
banner "3. (a) RECONSTRUCT the 460-byte seed from its commented listing"
HEX0_SEED_SHA=3d6a8119ae0e5982050b8a36a7330674c0c85c383428b151f16af04cfe330e9a
KAEM_SEED_SHA=b076da2cbbad9f67076dcf2559fda60410581e86740bf7f3ae488c5c2eee2761
loud "the listing is human-auditable hex with comments; here are its first lines:"
head -12 armv7l/hex0_armv7l.hex0 | sed 's/^/    /'
python3 "$DEMO_DIR/payload/seed/render_hex0.py" armv7l/hex0_armv7l.hex0 \
        bootstrap-seeds/POSIX/armv7l/hex0-seed
chmod +x bootstrap-seeds/POSIX/armv7l/hex0-seed
SZ=$(stat -c%s bootstrap-seeds/POSIX/armv7l/hex0-seed)
[ "$SZ" -eq 460 ] || die "rendered seed is $SZ bytes, expected 460"
echo "$HEX0_SEED_SHA  bootstrap-seeds/POSIX/armv7l/hex0-seed" | sha256sum -c - \
  || die "rendered seed does not match the pinned sha256"
loud "SEED RECONSTRUCTED FROM TEXT: 460 bytes, sha256 $HEX0_SEED_SHA"

banner "3. (b) LADDER EDGE: the seed reproduces itself, then builds kaem-0"
./bootstrap-seeds/POSIX/armv7l/hex0-seed armv7l/hex0_armv7l.hex0 armv7l/artifact/hex0
chmod +x armv7l/artifact/hex0
cmp armv7l/artifact/hex0 bootstrap-seeds/POSIX/armv7l/hex0-seed \
  || die "hex0(its own source) != the seed -- the ladder edge is broken"
loud "hex0(hex0_armv7l.hex0) == the seed, byte-identically"
./armv7l/artifact/hex0 armv7l/kaem-minimal.hex0 bootstrap-seeds/POSIX/armv7l/kaem-optional-seed
chmod +x bootstrap-seeds/POSIX/armv7l/kaem-optional-seed
SZ=$(stat -c%s bootstrap-seeds/POSIX/armv7l/kaem-optional-seed)
[ "$SZ" -eq 1162 ] || die "kaem seed is $SZ bytes, expected 1162"
echo "$KAEM_SEED_SHA  bootstrap-seeds/POSIX/armv7l/kaem-optional-seed" | sha256sum -c - \
  || die "built kaem seed does not match the pinned sha256"
loud "hex0(kaem-minimal.hex0) == the 1,162-byte kaem seed, sha256 pinned"

# ---------------------------------------------------------------------------
banner "4. (c) FROM-SEED ENFORCED: exactly two pre-existing ELF binaries"
count_elf () { # prints every ELF outside the build output dirs
  find . -type f \
       ! -path './armv7l/artifact/*' ! -path './armv7l/bin/*' \
       ! -path './bootstrap-seeds/*' -print0 \
  | while IFS= read -r -d '' f; do
      if [ "$(head -c4 "$f" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ]; then echo "$f"; fi
    done
}
STRAY=$(count_elf | head -20)
if [ -n "$STRAY" ]; then
  echo "$STRAY" | sed 's/^/    UNEXPECTED ELF: /'
  die "the tree contains pre-existing binaries beyond the two seeds"
fi
loud "no ELF anywhere except the two seeds -- 'from seed' is enforced, not asserted"
ls -l bootstrap-seeds/POSIX/armv7l/ | sed 's/^/    /'

# ---------------------------------------------------------------------------
banner "5. (d) RUN THE LADDER: kaem.armv7l, seed -> bin/*"
loud "this is the whole ladder; it takes a while under emulation"
set +e
./bootstrap-seeds/POSIX/armv7l/kaem-optional-seed ./kaem.armv7l > ladder.log 2>&1
LRC=$?
set -e
if [ $LRC -ne 0 ] || grep -q "ABORTING" ladder.log; then
  echo "---- last 40 lines of the ladder log ----"; tail -40 ladder.log
  die "the ladder did not complete (exit $LRC)"
fi
loud "ladder completed; $(wc -l < ladder.log) log lines"
loud "the binaries it built:"
ls -l armv7l/bin | sed 's/^/    /'

# ---------------------------------------------------------------------------
banner "6. (e) ANSWERS REPRODUCE -- twice, by two independent implementations"
OKS=$(grep -c ': OK' ladder.log || true)
[ "$OKS" -eq 20 ] || { grep -E ': (OK|FAILED)' ladder.log | sed 's/^/    /'
                       die "chain-built sha256sum verified $OKS/20 answers"; }
loud "IMPLEMENTATION 1 -- the ladder's OWN chain-built sha256sum, run inside"
loud "  the ladder by its own kaem.run: 20/20 OK"
grep -E ': (OK|FAILED)' ladder.log | sed 's/^/    /'
sha256sum -c armv7l.answers > coreutils.log 2>&1 \
  || { cat coreutils.log; die "GNU coreutils sha256sum disagrees with armv7l.answers"; }
loud "IMPLEMENTATION 2 -- the runner's GNU coreutils sha256sum: 20/20 OK"
loud "  These two share no code: one is C compiled by this ladder, the other"
loud "  is the runner's system tool.  That makes them an INDEPENDENT reference"
loud "  for each other -- the only independence claim this job makes."

banner "7. (f) key intermediates are bit-reproducible across machines"
# Fixed at authoring time on a different machine; the ladder is deterministic.
check_sha () { echo "$1  $2" | sha256sum -c - || die "$2 is not bit-reproducible"; }
check_sha d54d4a20ad5987b18b150c15ab400ce5a3e4db8ef0fcc38bbc4691c323b5ef27 armv7l/artifact/M2
check_sha bfda723b0b169be0c4fd6ecf283fac8d9c652d30db9f599b154ca72ae404c94c armv7l/artifact/blood-elf-0
check_sha e6511294902ca7b87f1a25fddea38e0d57743e68e298cb83031ac2499f0137d3 armv7l/artifact/M1-0
check_sha c0c0580cf21ceb49cce565b694cc81d1be1df861b0f0e9e5d2763189afdfa1d8 armv7l/artifact/hex2-1
loud "M2-Planet, blood-elf-0, M1-0 and hex2-1 all match values fixed elsewhere"
loud "the C compiler the ladder built, doing its job:"
printf 'int main() {\n  return 1 + 2;\n}\n' > probe.c
./armv7l/bin/M2-Planet --architecture armv7l -f probe.c -o probe.M1
sed 's/^/    /' probe.M1
grep -q "LOADI8_ALWAYS" probe.M1 || die "M2-Planet did not emit armv7l code"

# ---------------------------------------------------------------------------
banner "8. (g) RED LEGS -- the checks above must be capable of failing"
loud "RED 1: corrupt ONE byte of a built binary; the answers check must name it"
cp armv7l/bin/match match.orig
# FLIP a byte rather than SET one: writing a fixed value is silently a no-op
# when the byte already holds it, which would make this red leg vacuous.
# (It did, at authoring time -- offset 200 was already 0x00 and the "corrupted"
# file still verified.  The setup assertion below is what caught it.)
python3 -c 'import sys
p = "armv7l/bin/match"
b = bytearray(open(p, "rb").read())
b[200] ^= 0xFF
open(p, "wb").write(bytes(b))'
cmp -s armv7l/bin/match match.orig \
  && die "RED 1 setup failed: the byte flip did not change the file"
loud "  one byte flipped at offset 200 (file now differs from the built binary)"
set +e
sha256sum -c armv7l.answers > red1.log 2>&1
R1=$?
set -e
grep -q 'armv7l/bin/match: FAILED' red1.log \
  || { cat red1.log; die "RED 1 did not fire: a corrupted binary still passed"; }
[ $R1 -ne 0 ] || die "RED 1 did not fire: sha256sum -c returned success"
loud "  fired, with the expected named assertion:"
grep -E 'FAILED|WARNING' red1.log | sed 's/^/      /'
cp match.orig armv7l/bin/match
sha256sum -c armv7l.answers >/dev/null 2>&1 || die "failed to restore the corrupted binary"
# Remove the backup too: it is itself an ELF, and leaving it in the tree would
# make the RED 2 scan below report it alongside the planted file.  (It did, at
# authoring time -- which is the from-seed scan behaving exactly as intended.)
rm -f match.orig
loud "  (binary restored, backup removed; answers verify again)"

loud "RED 2: plant a third ELF; the from-seed scan must refuse the tree"
cp armv7l/bin/match armv7l/planted-elf
STRAY=$(count_elf | head -5)
[ -n "$STRAY" ] || die "RED 2 did not fire: the from-seed scan missed a planted ELF"
loud "  fired; the scan reported:"
echo "$STRAY" | sed 's/^/      UNEXPECTED ELF: /'
rm -f armv7l/planted-elf
[ -z "$(count_elf | head -1)" ] || die "failed to clean up the planted ELF"
loud "  (planted ELF removed; scan clean again)"

banner "DEMONSTRATION SUCCEEDED"
cat <<'SUMMARY'
    From ONE 460-byte hex0 seed -- itself reconstructed in this job from a
    commented text listing -- the armv7l stage0 ladder built 20 binaries and
    reproduced armv7l.answers exactly, verified by two independent sha256
    implementations, with the from-seed constraint enforced by a scan and
    both red legs firing.

    Scope: one lineage, so this shows from-seed reproducibility, NOT
    cross-lineage diversity; and it takes no position on upstream adoption.
SUMMARY
