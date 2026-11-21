#!/bin/bash
# Compare versions.env with upstream and propose updates.
#
#   tools/make-updates.sh [--apply] [--versions FILE]
#
# Prints one line per component of versions.env: current, latest, status
# (ok | UPDATE | unavailable), and for every UPDATE the new KEY=value lines.
#   DEBIAN_DIGEST  the digest of debian:<DEBIAN_CODENAME>-slim, when the tag was rebuilt
#                  upstream (same codename: OS security updates); a newer Debian stable
#                  is only shown as a note, change DEBIAN_CODENAME by hand
#   APP_VER        the upstream Postfix version of the newest postfix package of
#                  DEBIAN_CODENAME (main, -updates, -security): APP_VER is the Postfix version
# "unavailable" = the upstream lookup failed.
#
# Pin: APP_VER_PIN=<version> in versions.env keeps APP_VER on <version>.
#
# --apply writes the proposed lines into versions.env (only KEY=value lines
# already present; every value checked, nothing written if one is missing or
# invalid). Then: tools/build.sh, test, commit.
#
# Exit code: 0 all current (or, with --apply, updates applied), 10 updates
# available, 2 incomplete (lookups unavailable), 1 error.
# Requires: curl, jq, xz.

set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
versions="$root/versions.env"
apply=''
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=1 ;;
    --versions) versions=${2:?--versions FILE}; shift ;;
    -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
# shellcheck source=build/lib.sh
. "$root/build/lib.sh"
load_versions "$versions"

updates=0
unavailable=0
proposals=()

row() { printf '%-24s %-24s %-24s %s\n' "$1" "$2" "$3" "$4"; }
report() { # component current latest [note]
  local name=$1 cur=$2 new=$3 note=${4:-}
  if [ "$cur" == "$new" ]; then row "$name" "$cur" "$new" "ok${note:+ ($note)}"
  else row "$name" "$cur" "$new" "UPDATE${note:+ ($note)}"; updates=$((updates + 1)); return 1
  fi
}
propose() { proposals+=("$@"); }
# lookup: like report, but an empty "latest" means the upstream lookup failed
lookup() { # component current latest source [note]
  if [ -z "$3" ]; then row "$1" "$2" "?" "unavailable ($4)"; unavailable=$((unavailable + 1)); return 0; fi
  report "$1" "$2" "$3" "${5:-}"
}
# every request retries transient failures; curl messages only when it fails for good
fetch() {
  local err rc=0
  err=$(mktemp)
  curl -fsSL --proto '=https' --connect-timeout 30 --speed-limit 1024 --speed-time 60 --retry 3 --retry-delay 2 --retry-connrefused "$@" 2>"$err" || rc=$?
  [ "$rc" -eq 0 ] || tail -n 1 "$err" >&2
  rm -f "$err"
  return "$rc"
}

row COMPONENT CURRENT LATEST STATUS

# --- base image: digest of debian:<codename>-slim (a newer codename is only a note)
new='' note=''
token=$(fetch "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/debian:pull" | jq -r '.token // empty' || true)
if [ -n "$token" ]; then
  new=$(fetch -I -H "Authorization: Bearer $token" -H 'Accept: application/vnd.oci.image.index.v1+json' \
    "https://registry-1.docker.io/v2/library/debian/manifests/${DEBIAN_CODENAME}-slim" |
    tr -d '\r' | sed -n 's/^docker-content-digest: *//Ip' || true)
fi
stable=$(fetch https://deb.debian.org/debian/dists/stable/Release | sed -n 's/^Codename: *//p' || true)
[ -z "$stable" ] || [ "$stable" == "$DEBIAN_CODENAME" ] || note="Debian stable is now $stable"
lookup DEBIAN_DIGEST "${DEBIAN_DIGEST:7:12}" "${new:7:12}" "Docker Hub" "$DEBIAN_CODENAME-slim${note:+, $note}" ||
  propose "DEBIAN_DIGEST=$new"

# --- Postfix: newest postfix package of DEBIAN_CODENAME, -updates and -security
# pkg_version URL: Version of the postfix package in a Packages.xz index (empty if missing)
pkg_version() { (fetch "$1" || true) | (xz -dc 2>/dev/null || true) | awk '/^Package: postfix$/{f=1} f&&/^Version:/{print $2; exit}'; }
debs=$(
  pkg_version "https://deb.debian.org/debian/dists/$DEBIAN_CODENAME/main/binary-amd64/Packages.xz"
  pkg_version "https://deb.debian.org/debian/dists/$DEBIAN_CODENAME-updates/main/binary-amd64/Packages.xz"
  pkg_version "https://security.debian.org/debian-security/dists/$DEBIAN_CODENAME-security/main/binary-amd64/Packages.xz"
)
deb=$(grep -v '^$' <<< "$debs" | sort -V | tail -1 || true)
# upstream part of the Debian version: 3.10.13-0+deb13u1 -> 3.10.13
new=${deb%%-*} note=${deb:+package $deb}
if [ -n "${APP_VER_PIN:-}" ]; then
  [ -z "$new" ] || [ "$new" == "$APP_VER_PIN" ] || note="pinned, latest $new"
  [ -z "$new" ] || [ "$new" != "$APP_VER_PIN" ] || note="pinned"
  [ -z "$new" ] || new=$APP_VER_PIN
fi
lookup APP_VER "$APP_VER" "$new" "deb.debian.org" "$note" || propose "APP_VER=$new"

echo
[ "$unavailable" -eq 0 ] || echo "$unavailable lookup(s) unavailable: the report is incomplete" >&2
if [ "$updates" -eq 0 ]; then
  [ "$unavailable" -eq 0 ] || exit 2
  echo "all components are current"
  exit 0
fi
echo "$updates update(s) available, proposed versions.env lines:"
printf '  %s\n' "${proposals[@]}"
[ -n "$apply" ] || exit 10

# --- --apply: replace the KEY=value lines, all or nothing
for line in "${proposals[@]}"; do
  k=${line%%=*} v=${line#*=}
  [[ "$k" =~ ^[A-Z0-9_]+$ ]] || { echo "apply: invalid line '$line'" >&2; exit 1; }
  grep -q "^$k=" "$versions" || { echo "apply: $k is not in $versions" >&2; exit 1; }
  [ -n "$v" ] || { echo "apply: $k has no value (upstream lookup failed): nothing written" >&2; exit 1; }
  case "$k" in
    *_DIGEST) [[ "$v" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "apply: $k is not a digest ('$v'): nothing written" >&2; exit 1; } ;;
    APP_VER) [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "apply: $k is not a version ('$v'): nothing written" >&2; exit 1; } ;;
  esac
done
out=$(mktemp "$versions.XXXXXX")
awk 'NR == FNR { i = index($0, "="); val[substr($0, 1, i - 1)] = substr($0, i + 1); next }
     !/^#/ && (i = index($0, "=")) > 1 && ((k = substr($0, 1, i - 1)) in val) { print k "=" val[k]; next }
     { print }' <(printf '%s\n' "${proposals[@]}") "$versions" > "$out"
chmod --reference="$versions" "$out"
mv -f "$out" "$versions"
echo
echo "applied ${#proposals[@]} line(s) to $versions"
echo "next: tools/build.sh, test, then commit (git diff to review)"
[ "$unavailable" -eq 0 ] || exit 2
exit 0
