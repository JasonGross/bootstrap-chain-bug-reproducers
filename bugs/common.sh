# Shared helpers for the bug reproducer scripts.  Source, don't execute.
# Convention: a script exits 0 IFF the bug REPRODUCES (and the control leg,
# where present, behaves correctly).  All evidence is printed loudly.

set -euo pipefail

banner () {
  echo
  echo "=============================================================================="
  echo "== $*"
  echo "=============================================================================="
}

loud () { echo ">>> $*"; }

die () { echo "FATAL: $*" >&2; exit 1; }

# fetch <url> <sha256> <dest-file>
fetch () {
  local url="$1" sha="$2" out="$3"
  if [ -f "$out" ] && echo "$sha  $out" | sha256sum -c --quiet - 2>/dev/null; then
    loud "already fetched: $out"
    return 0
  fi
  loud "fetching $url"
  curl -fsSL --retry 5 --retry-delay 5 -o "$out" "$url"
  echo "$sha  $out" | sha256sum -c - || die "sha256 mismatch for $out (pinned $sha)"
}

MES_URL=https://ftp.gnu.org/gnu/mes/mes-0.27.1.tar.gz
MES_SHA=183a40ea47ea49f8a1e3bd1b9d12e676374d64d63bc79e7bc1ae7d673dfdf25d

fetch_mes () { # extracts into $1/mes-0.27.1
  local dir="$1"
  mkdir -p "$dir"
  fetch "$MES_URL" "$MES_SHA" "$dir/mes-0.27.1.tar.gz"
  [ -d "$dir/mes-0.27.1" ] || tar -xzf "$dir/mes-0.27.1.tar.gz" -C "$dir"
}

NYACC_URL=https://download.savannah.nongnu.org/releases/nyacc/nyacc-1.00.2.tar.gz
NYACC_SHA=f36e4fb7dd524dc3f4b354d3d5313f69e7ce5a6ae93711e8cf6d51eaa8d2b318

fetch_nyacc () { # extracts into $1/nyacc-1.00.2 (the C99 parser MesCC uses)
  local dir="$1"
  mkdir -p "$dir"
  fetch "$NYACC_URL" "$NYACC_SHA" "$dir/nyacc-1.00.2.tar.gz"
  [ -d "$dir/nyacc-1.00.2" ] || tar -xzf "$dir/nyacc-1.00.2.tar.gz" -C "$dir"
}

# --- live upstream re-check -------------------------------------------------
# A pinned reproducer proves the bug existed at the pin.  It cannot notice that
# upstream has since FIXED it -- so a report can quietly go stale while its
# workflow stays green.  upstream_still_has() re-reads the accused file from
# upstream's live default branch on every run and fails loudly if the accused
# construct is gone.
#
# Crucially it distinguishes two very different failures:
#   * fetched, and the construct is ABSENT  -> die: upstream may have fixed it,
#     which is a real signal that a human must look at the report.
#   * could not fetch at all                -> WARN and continue: a host being
#     down says nothing about the bug, and going red for it would be a red
#     that teaches nobody anything.  (Every git host we depend on has been
#     unreachable at least once during this project.)
#
# usage: upstream_still_has <label> <raw-url> <fixed-string>
upstream_still_has () {
  local label="$1" url="$2" needle="$3" tmp
  tmp=$(mktemp)
  if ! curl -fsSL --max-time 60 --retry 2 -o "$tmp" "$url" 2>/dev/null; then
    loud "UPSTREAM RE-CHECK SKIPPED ($label): could not reach $url"
    loud "  (host unreachable != bug fixed -- not failing the run over it)"
    rm -f "$tmp"
    return 0
  fi
  if grep -qF -- "$needle" "$tmp"; then
    loud "upstream re-check OK ($label): still present on the live default branch"
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  echo >&2
  echo "!! UPSTREAM RE-CHECK FAILED ($label)" >&2
  echo "!! $url no longer contains:" >&2
  echo "!!   $needle" >&2
  echo "!! Upstream may have FIXED this. The pinned reproduction below may" >&2
  echo "!! still be valid history, but the REPORT needs a human to re-read" >&2
  echo "!! it before it is sent. This is the intended way for that to" >&2
  echo "!! surface -- do not just re-pin to silence it." >&2
  die "upstream re-check failed for $label"
}
