# Description
Production ready Mail Transport Agent Container using Postfix

# Supported tags
-	`3.4.5-BUILD`, `3.5.5`, `3.4`, `3`, `latest`

Where **X** is the patch version number, and **BUILD** is the build number (look into project [Tags](/repository/docker/izdock/postfix/tags/) page to discover the latest versions)

# Dockerfile
- https://github.com/ugoviti/izdock/blob/master/postfix/Dockerfile

# Features
- Small image footprint (based on **slim** version of [Linux Debian](/_/debian/) image)
- Many customizable variables to use
- Using [tini](https://github.com/krallin/tini) as init process integrated with runit as process manager and socklog as syslog server for very small image footprint
- Switchable init process using ```MULTISERVICE``` variable

# What is Postfix?
Postfix is a free and open-source mail transfer agent (MTA) that routes and delivers electronic mail.

It is released under the IBM Public License 1.0 which is a free software license. Alternatively, starting with version 3.2.5, it is available under the Eclipse Public License 2.0 at the user's option.

Originally written in 1997 by Wietse Venema at the IBM Thomas J. Watson Research Center in New York, and first released in December 1998[3], Postfix continues as of 2018 to be actively developed by its creator and other contributors. The software is also known by its former names VMailer and IBM Secure Mailer.

In a December 2017 study performed by E-Soft, Inc., approximately 34% of the publicly reachable mail-servers on the Internet ran Postfix.

> [wikipedia.org/wiki/Postfix_(software)](https://en.wikipedia.org/wiki/Postfix_(software))

![logo](http://www.postfix.org/mysza.gif)

# How to use this image

```docker pull izdock/postfix```

```docker run -it --rm izdock/postfix```

You can test it by configuring your smtp client to use **container-ip:25** or **container-ip:465** or **container-ip:587**

If you need access outside the host, on port 25, 465, 587:
```docker run -it --rm -p 25:25 -p 465:465 -p 587:587 izdock/postfix```

# Environment variables

Follow all usable runtime environment variables with default values

## multiservice management
```
: ${MULTISERVICE:="true"}
```
  * **true** = use runit as multi service process manager and start socklog as syslog server
  * **false** = start postfix in foreground (using the new 3.3.x ```start-fg``` command)

## postfix config files
```
: ${file_master_cf:="/etc/postfix/master.cf"}
: ${file_main_cf:="/etc/postfix/main.cf"}
: ${file_allowed_senders:="/etc/postfix/allowed_senders"}
: ${file_header_checks:="/etc/postfix/header_checks"}
: ${file_sasl_passwd:="/etc/postfix/sasl_passwd"}
: ${file_aliases:="/etc/aliases"}
```

## /etc/aliases mails to root address
```
: ${aliases_root:="root"}
```

## local domain configuration
```
: ${mydomain:="$HOSTNAME"}
: ${myhostname:="$HOSTNAME"}
: ${mydestination:="$myhostname, localhost.$mydomain, localhost"}
: ${myorigin:="$mydomain"}
: ${mynetworks:="127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"}
: ${relay_domains:=""}
: ${allowed_senders_domains:=""}
```

## external smart host configuration
```
: ${relayhost:=""}
: ${relayhost_password:=""}
: ${relayhost_username:=""}
```

## message specific configuration
```
: ${mailbox_size_limit:=0}
: ${message_size_limit:=8000000}
```

## smtp configuration
```
: ${smtputf8_enable:="no"}
: ${smtp_sasl_auth_enable:="yes"}
: ${smtp_sasl_security_options:="noanonymous"}
: ${smtp_tls_security_level:="may"}
: ${smtpd_tls_security_level:="none"}
: ${smtpd_delay_reject:="yes"}
: ${smtpd_helo_required:="yes"}
: ${smtpd_helo_restrictions:="permit_mynetworks,reject_invalid_helo_hostname,permit"}
: ${smtpd_restriction_classes:="allowed_domains_only"}
: ${allowed_domains_only:="permit_mynetworks, reject_non_fqdn_sender reject"}
: ${smtpd_recipient_restrictions:="reject_non_fqdn_recipient,reject_unknown_recipient_domain,reject_unverified_recipient"}
```

### Configuration
To customize the configuration just `COPY` your custom configuration in `/etc/postfix/master.cf` and `/etc/postfix/main.cf`.

```dockerfile
FROM izdock/tomcat
COPY ./master.cf /etc/postfix/master.cf
COPY ./main.cf /etc/postfix/main.cf
```

# Quick reference

-	**Where to get help**:
	[InitZero Enterprise Support](https://www.initzero.it/)

-	**Where to file issues**:
	[https://github.com/ugoviti](https://github.com/ugoviti)

-	**Maintained by**:
	[Ugo Viti](https://github.com/ugoviti)

-	**Supported architectures**:
	[`amd64`]

-	**Supported Docker versions**:
	[the latest release](https://github.com/docker/docker-ce/releases/latest) (down to 1.6 on a best-effort basis)

# License

View [Eclipse Public License - v 2.0](http://www.eclipse.org/legal/epl-v20.html) and for the software contained in this image.

As with all Docker images, these likely also contain other software which may be under other licenses (such as Bash, etc from the base distribution, along with any direct or indirect dependencies of the primary software being contained).

As for any pre-built image usage, it is the image user's responsibility to ensure that any use of this image complies with any relevant licenses for all software contained within.
