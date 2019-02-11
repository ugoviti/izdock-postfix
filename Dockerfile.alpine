FROM alpine:3.8

MAINTAINER Ugo Viti <ugo.viti@initzero.it>

ENV APP      "Postfix Mail Transport Agent"
ENV APP_NAME "postfix"

RUN set -x \
  && apk upgrade --update --no-cache \
  && apk add \
	tini \
	bash \
	runit \
	socklog \
	ca-certificates \
	postfix \
	cyrus-sasl \
	cyrus-sasl-crammd5 \
	cyrus-sasl-digestmd5 \
	heirloom-mailx \
 && rm -rf /var/cache/apk/* /tmp/*

# rsyslog config
#RUN sed 's/mail.*/mail.info \/dev\/stdout/' -i /etc/rsyslog.conf

# postfix config
RUN mkdir -p /var/spool/postfix/ \
 && mkdir -p /var/spool/postfix/pid \
 && chown root: /var/spool/postfix/ \
 && chown root: /var/spool/postfix/pid 

# add files to container
ADD Dockerfile /
ADD filesystem /

# define volumes
VOLUME	[ "/var/spool/postfix", "/etc/postfix" ]

# exposed ports
EXPOSE 25/TCP 465/TCP 587/TCP

# init
ENTRYPOINT ["tini", "-g", "--"]
CMD ["/entrypoint.sh", "runsvdir", "-P", "/etc/runit/services"]

# in futuro con postfix >= 3.3.0 è stato aggiunto il supporto a docker nativo per girare in foreground
# al momento 20180313 è necessario alpine:edge ma rsyslog da un errore di firma
#CMD ["/entrypoint.sh", "postfix", "start-fg"]

ENV APP_VER "3.3.0-17"
