#!/bin/bash
# verify-image.sh: post-build checks run INSIDE the image, before it is published.
#   docker run -i --rm --entrypoint "" -e APP_VER_EXPECTED=3.10.13 IMAGE bash -s < verify-image.sh
# The expected versions are read from the versions.env shipped in the image.
# Prints one OK/FAIL line per check, exit 1 if any check fails.
set -u

FAIL=0
ok() { echo "OK   $*"; }
ko() { echo "FAIL $*"; FAIL=1; }
has() { if [ -e "$1" ]; then ok "${2:-$1}"; else ko "${2:-$1} missing"; fi; }
cmd() { local c; for c in "$@"; do if command -v "$c" >/dev/null 2>&1; then ok "command $c"; else ko "command $c missing"; fi; done; }

src=/usr/src/postfix
[ -r "$src/versions.env" ] || { ko "$src/versions.env missing"; exit 1; }
# shellcheck source=build/lib.sh
. "$src/build/lib.sh"
load_versions "$src/versions.env"

# base image: the Debian release of versions.env
codename=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
if [ "$codename" == "$DEBIAN_CODENAME" ]; then ok "Debian $codename $(cat /etc/debian_version)"; else ko "Debian '$codename', expected $DEBIAN_CODENAME"; fi

# image version: APP_VER of the image and of versions.env agree with the one CI built
expected=${APP_VER_EXPECTED:-}
[ -n "$expected" ] || ko "APP_VER_EXPECTED not set"
if [ "${APP_VER:-}" == "$expected" ]; then ok "APP_VER=$APP_VER"; else ko "APP_VER='${APP_VER:-}', expected $expected"; fi

# APP_VER is the Postfix version: a Debian update to a new Postfix must also move APP_VER
# (tools/make-updates.sh proposes it), otherwise the image would be tagged with the old version
pf=$(postconf -dh mail_version 2>/dev/null)
if [ "$pf" == "$APP_VER" ]; then ok "Postfix $pf"; else ko "Postfix '$pf', APP_VER is $APP_VER (update APP_VER in versions.env)"; fi

# default mode of the image: MULTISERVICE=false (postfix in foreground, log on stdout)
if [ "${MULTISERVICE:-}" == "false" ]; then ok "MULTISERVICE=false (default)"; else ko "MULTISERVICE='${MULTISERVICE:-}', expected false"; fi

# services and tools used by the entrypoint and by runit (MULTISERVICE=true)
cmd tini runsvdir runsv chpst socklog svlogd postfix postconf postmap postalias sendmail mailq \
  opendkim opendkim-genkey mailx pmailq curl

# postfix configuration of the image
if postfix check >/dev/null 2>&1; then ok "postfix check"; else ko "postfix check: $(postfix check 2>&1 | tail -1)"; fi

# files of rootfs/ at their path: with a wrong COPY (eg. "filesystem/*") the directory
# contents land in / (/service, /log, /local) and runit finds no service
for f in /etc/service/postfix/run /etc/service/socklog/run /etc/service/socklog/log/run /usr/local/sbin/pfdel; do
  if [ -x "$f" ]; then ok "$f"; else ko "$f missing or not executable"; fi
done
has /var/log/mail/config "svlogd config /var/log/mail/config"
for d in /service /log /local; do
  if [ -e "$d" ]; then ko "$d exists: rootfs/ copied without its directory layout"; else ok "no $d"; fi
done

# entrypoint
has /entrypoint.sh
has /entrypoint-hooks.sh

exit $FAIL
