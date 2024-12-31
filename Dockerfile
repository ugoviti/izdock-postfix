FROM debian:bullseye-slim

LABEL maintainer="Ugo Viti <u.viti@wearequantico.it>"

ENV APP_NAME        "postfix"
ENV APP_DESCRIPTION "Postfix Mail Transport Agent"

# full app version
ARG APP_VER
ENV APP_VER "${APP_VER}"

# debian specific
ENV DEBIAN_FRONTEND noninteractive

RUN set -xe \
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
  # install socklog from debian 8
  && curl -fSL --connect-timeout 30 http://archive.debian.org/debian/pool/main/s/socklog/socklog_2.1.0-8_amd64.deb -o socklog_2.1.0-8_amd64.deb \
  && dpkg -i socklog_2.1.0-8_amd64.deb \
  && rm -f socklog_2.1.0-8_amd64.deb \
  # cleanup system
  && : "---------- Removing build dependencies and clean temporary files ----------" \
  && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
  && rm -rf /var/lib/apt/lists/* /tmp/*

# postfix config
#RUN mkdir -p /var/spool/postfix/ \
# && mkdir -p /var/spool/postfix/pid \
# && chown root: /var/spool/postfix/ \
# && chown root: /var/spool/postfix/pid

# postfix config
RUN set -xe \
  # fix permissions
  && sed '/^\$manpage_directory/d' -i /etc/postfix/postfix-files \
  # disable chroot configuration
  && echo "$(awk '$5=="y" {$5="n"}1' OFS="\t" /etc/postfix/master.cf)" > /etc/postfix/master.cf \
  && postfix set-permissions \
  && postfix check

# define volumes
VOLUME ["/var/lib/postfix", "/var/mail", "/var/spool/postfix", "/etc/opendkim/keys", "/etc/postfix"]

# exposed ports
EXPOSE 25/TCP 465/TCP 587/TCP

# add files to container
ADD Dockerfile filesystem README.md /

# container pre-entrypoint variables
ENV APP_RUNAS          ""
ENV MULTISERVICE       "true"
ENV ENTRYPOINT_TINI    "true"
ENV UMASK              0002

## CI args
ARG APP_VER_BUILD
ARG APP_BUILD_COMMIT
ARG APP_BUILD_DATE

# define other build variables
ENV APP_VER_BUILD    "${APP_VER_BUILD}"
ENV APP_BUILD_COMMIT "${APP_BUILD_COMMIT}"
ENV APP_BUILD_DATE   "${APP_BUILD_DATE}"

# start the container process
ENTRYPOINT ["/entrypoint.sh"]
CMD ["postfix", "start-fg"]
