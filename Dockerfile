# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
# (IMAGE_FROM is always passed, no default on purpose)
# izdock/postfix: Postfix Mail Transport Agent.
#
# Versions: versions.env (single source of truth).
# IMAGE_FROM has no default: it comes from versions.env (DEBIAN_CODENAME, DEBIAN_DIGEST).
#   tools/build.sh          local build (the same build args as CI)
# CI: .gitea/workflows/build.yml (build + verify), .gitea/workflows/publish.yml (Docker Hub + GitHub)
# docker run -it --rm -p 25:25 -p 465:465 -p 587:587 --name postfix izdock/postfix:local

ARG IMAGE_FROM
FROM ${IMAGE_FROM}
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL maintainer="Ugo Viti <u.viti@wearequantico.it>"

ENV APP_NAME="postfix"
ENV APP_DESCRIPTION="Postfix Mail Transport Agent"

## full app version (APP_VER of versions.env, passed by tools/build.sh and CI)
ARG APP_VER
ENV APP_VER="${APP_VER}"

## debian apt warnings workaround
ENV DEBIAN_FRONTEND=noninteractive

# OS_UPDATE_STAMP: changes every week in CI, so the cached OS upgrade layer is rebuilt
ARG OS_UPDATE_STAMP=""
RUN : "os update ${OS_UPDATE_STAMP}" \
  && apt-get update && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    bash \
    tini \
    tar \
    gzip \
    bzip2 \
    xz-utils \
    less \
    procps \
    net-tools \
    iputils-ping \
    runit \
    socklog \
    file \
    curl \
    ca-certificates \
    postfix \
    libterm-readline-perl-perl \
    libsasl2-2 \
    libsasl2-modules \
    bsd-mailx \
    pmailq \
    opendkim \
    opendkim-tools \
  && update-ca-certificates \
  && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
  && rm -rf /var/lib/apt/lists/* /tmp/*

# postfix config
RUN sed '/^\$manpage_directory/d' -i /etc/postfix/postfix-files \
  # disable chroot configuration
  && awk '$5=="y" {$5="n"}1' OFS="\t" /etc/postfix/master.cf > /tmp/master.cf \
  && cat /tmp/master.cf > /etc/postfix/master.cf && rm -f /tmp/master.cf \
  && postfix set-permissions \
  && postfix check

# versions of the build, read by .gitea/actions/build-push/verify-image.sh
COPY versions.env /usr/src/postfix/versions.env
COPY build/ /usr/src/postfix/build/

# define volumes
VOLUME ["/var/lib/postfix", "/var/mail", "/var/spool/postfix", "/etc/opendkim/keys", "/etc/postfix"]

# exposed ports
EXPOSE 25/TCP 465/TCP 587/TCP

# add files to container
# NB. COPY rootfs/ / keeps the directory layout (etc/service, var/log/mail, usr/local/sbin):
# with "filesystem/*" every directory content was copied into / losing the parent directories
COPY Dockerfile README.md /
COPY rootfs/ /

# container pre-entrypoint variables
# MULTISERVICE=false (default): postfix in foreground (postfix start-fg), log on stdout
# MULTISERVICE=true: runit starts postfix and socklog, svlogd writes /var/log/mail/current
# (eg. for a fluent-bit sidecar, as the qms chart does) and copies every line to stderr
ENV APP_RUNAS=""
ENV MULTISERVICE="false"
ENV ENTRYPOINT_TINI="true"
ENV UMASK=0002

## CI args
ARG APP_VER_BUILD
ARG APP_BUILD_COMMIT
ARG APP_BUILD_DATE

# define other build variables
ENV APP_VER_BUILD="${APP_VER_BUILD}"
ENV APP_BUILD_COMMIT="${APP_BUILD_COMMIT}"
ENV APP_BUILD_DATE="${APP_BUILD_DATE}"

# start the container process
ENTRYPOINT ["/entrypoint.sh"]
CMD ["postfix", "start-fg"]
