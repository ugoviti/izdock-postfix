FROM debian:buster-slim

MAINTAINER Ugo Viti <ugo.viti@initzero.it>

ENV APP_NAME        "postfix"
ENV APP_DESCRIPTION "Postfix Mail Transport Agent"

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

# container pre-entrypoint variables
ENV MULTISERVICE    "true"
ENV ENTRYPOINT_TINI "true"
ENV UMASK           0022

# add files to container
ADD Dockerfile filesystem VERSION README.md /

# start the container process
ENTRYPOINT ["/entrypoint.sh"]
CMD ["postfix", "start-fg"]
