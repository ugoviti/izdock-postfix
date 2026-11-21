#!/bin/bash
# smoke-test.sh IMAGE: start the image with its real entrypoint in both modes and check that
# postfix answers and logs where expected. Run on the docker host, after verify-image.sh.
#   MULTISERVICE=false (default)  postfix in foreground, log on stdout
#   MULTISERVICE=true             runit + socklog: /var/log/mail/current (the file read by the
#                                 fluent-bit sidecar of the qms chart) and the container log
#   .gitea/actions/build-push/smoke-test.sh izdock/postfix:local
# Prints one OK/FAIL line per check, exit 1 if any check fails. DOCKER=podman to use podman.
set -u
image=${1:?usage: smoke-test.sh IMAGE}
docker=${DOCKER:-docker}
base="postfix-smoke-$$"
name=''
FAIL=0
ok() { echo "OK   $*"; }
ko() { echo "FAIL $*"; FAIL=1; }
inside() { "$docker" exec "$name" bash -c "$1" >/dev/null 2>&1; }
# wait_for SECONDS DESCRIPTION COMMAND: retry the command inside the container
wait_for() {
  local t=$1 what=$2 cmd=$3 i
  for ((i = 0; i < t; i++)); do inside "$cmd" && { ok "$what"; return; }; sleep 1; done
  ko "$what (after ${t}s)"
}
# logged SECONDS DESCRIPTION PATTERN: retry until the container log matches
logged() {
  local t=$1 what=$2 re=$3 i
  for ((i = 0; i < t; i++)); do "$docker" logs "$name" 2>&1 | grep -qE "$re" && { ok "$what"; return; }; sleep 1; done
  ko "$what (after ${t}s)"
}
# start MODE [env...]: start a container, its name in $name
start() {
  name="$base-$1"; shift
  "$docker" run -d --name "$name" -e mydomain=example.com "$@" "$image" >/dev/null || { ko "container $name does not start"; return 1; }
}
dump() { [ "$FAIL" -eq 0 ] || { echo "---------- log of $name (last 40 lines)"; "$docker" logs --tail 40 "$name" 2>&1; }; }
smtp_checks() {
  wait_for 30 "[$1] postfix master running" "pgrep -x master"
  wait_for 30 "[$1] smtp port 25 answers 220" "exec 3<>/dev/tcp/127.0.0.1/25 && timeout 5 head -1 <&3 | grep -q '^220 '"
  wait_for 30 "[$1] submission port 587 open" "echo > /dev/tcp/127.0.0.1/587"
  wait_for 30 "[$1] smtps port 465 open" "echo > /dev/tcp/127.0.0.1/465"
  inside "printf 'Subject: smoke\n\nsmoke test\n' | sendmail -f smoke-$1@example.com smoke@example.org"
}
cleanup() { "$docker" rm -f "$base-default" "$base-multiservice" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# --- default: MULTISERVICE=false
if start default; then
  if inside "pgrep -x runsvdir"; then ko "[default] runsvdir running with MULTISERVICE=false"; else ok "[default] no runit"; fi
  smtp_checks default
  # syslog_name is "docker" in this mode (entrypoint-hooks.sh): eg. docker/qmgr[202]: <queue id>: from=<...>
  logged 30 "[default] message on stdout" "docker/[a-z]+\[[0-9]+\]: [0-9A-F]+: from=<smoke-default@example.com>"
  dump
fi

# --- MULTISERVICE=true (qms chart with podsLogType: fluentd)
if start multiservice -e MULTISERVICE=true; then
  wait_for 30 "[multiservice] runsvdir running" "pgrep -x runsvdir"
  wait_for 30 "[multiservice] socklog running" "pgrep -x socklog"
  wait_for 30 "[multiservice] svlogd running" "pgrep -x svlogd"
  smtp_checks multiservice
  wait_for 30 "[multiservice] message in /var/log/mail/current" "grep -q 'from=<smoke-multiservice@example.com>' /var/log/mail/current"
  # the format of the fluent-bit postfix parser: "<facility>: <time> postfix/<process>[pid]: ..."
  if inside "grep -qE '^mail\.[a-z]+: [A-Z][a-z]{2} +[0-9]+ [0-9:]{8} postfix/' /var/log/mail/current"; then
    ok "[multiservice] log line format (facility: time postfix/process)"
  else
    ko "[multiservice] log line format: $("$docker" exec "$name" tail -1 /var/log/mail/current 2>&1)"
  fi
  logged 30 "[multiservice] message also in the container log" "from=<smoke-multiservice@example.com>"
  dump
fi
exit $FAIL
