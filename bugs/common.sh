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
