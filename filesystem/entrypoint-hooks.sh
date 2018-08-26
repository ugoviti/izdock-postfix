#!/bin/sh

# app hooks
hooks_always() {
echo "=> Executing $APP configuration hooks 'always'..."

if [ -e "/etc/rsyslog.conf" ]; then
echo "=> Configuring rsyslog logging server..."
echo '$ModLoad immark.so # provides --MARK-- message capability
$ModLoad imuxsock.so # provides support for local system logging (e.g. via logger command)

# default permissions for all log files.
$FileOwner root
$FileGroup adm
$FileCreateMode 0640
$DirCreateMode 0755
$Umask 0022

# log all to stdout
*.* /dev/stdout
' > /etc/rsyslog.conf

elif [ -e "/etc/syslog.conf" ]; then
echo "=> Configuring syslogd logging server..."
echo '*.=debug  |/dev/stdout
*.=info   |/dev/stdout
*.warn    |/dev/stderr' > /etc/syslog.conf
fi


echo "=> Configuring Postfix MTA server..."
# log mail subjects
echo '/^Subject:/ WARN' > /etc/postfix/header_checks
postconf -e header_checks="regexp:/etc/postfix/header_checks"

# update aliases database. It's not used, but postfix complains if the .db file is missing
postalias /etc/postfix/aliases

# syslog test
#postconf syslog_name=docker

# valorize default variables
mydomain="${mydomain:-$HOSTNAME}"
myhostname="${myhostname:-$HOSTNAME}"
myorigin="${myorigin:-$mydomain}"

# set external domain
postconf -e mydomain="${mydomain:-$HOSTNAME}"

# set external hostname
postconf -e myhostname="${myhostname:-$HOSTNAME}"

# set as outgoing mails came from
postconf -e myorigin="${myorigin:-$mydomain}"

# disable local mail delivery
postconf -e mydestination="${mydestination:-$myhostname, localhost.$mydomain, localhost}"

# define allowed networks to use this mta as mail server
postconf -e mynetworks="${mynetworks:-127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16}"

# docker syslog management (verificare quando postfix 3.3.1)
#postconf -e syslog_name="${syslog_name:-postfix}"

# don't relay for any domains
postconf -e relay_domains="${relay_domains:-}"

postconf -e smtp_tls_security_level="${smtp_tls_security_level:-may}"

postconf -e smtpd_tls_security_level="${smtpd_tls_security_level:-none}"

# disable SMTPUTF8, because libraries (ICU) are missing in alpine
postconf -e smtputf8_enable="${smtputf8_enable:-no}"

# as this is a server-based service, allow any message size -- we hope the server knows what it is doing
postconf -e mailbox_size_limit="${mailbox_size_limit:-0}"
postconf -e message_size_limit="${message_size_limit:-8000000}"

# reject invalid HELOs
postconf -e smtpd_delay_reject=yes
postconf -e smtpd_helo_required=yes
postconf -e smtpd_helo_restrictions=permit_mynetworks,reject_invalid_helo_hostname,permit


# set up a relayhost, if needed
if [ ! -z "$relayhost" ]; then
  echo -n "--> forwarding all emails to: $relayhost"

  postconf -e relayhost="${relayhost:-}"

  relayhost_username="${relayhost_username:-}"
  relayhost_password="${relayhost_password:-}"

  if [ -n "$relayhost_username" ] && [ -n "$relayhost_password" ]; then
		echo " using username: $relayhost_username"
		echo "$relayhost $relayhost_username:$relayhost_password" >> /etc/postfix/sasl_passwd
		postmap hash:/etc/postfix/sasl_passwd
		postconf -e smtp_sasl_auth_enable="${smtp_sasl_auth_enable:-yes}"
		postconf -e smtp_sasl_password_maps="hash:/etc/postfix/sasl_passwd"
		postconf -e smtp_sasl_security_options="${smtp_sasl_security_options:-noanonymous}"
	else
		echo "--> no 'relayhost_username' and 'relayhost_password' variables defined."
    echo "   sending email to the relayhost server without any authentication."
    echo "   make sure your server is configured to accept emails coming from this IP."
	fi
else
	echo "--> will try to deliver emails directly to the final server. Make sure your DNS is setup properly!"
	postconf -# relayhost
	postconf -# smtp_sasl_auth_enable
	postconf -# smtp_sasl_password_maps
	postconf -# smtp_sasl_security_options
fi

# Set up my networks to list only networks in the local loopback range
#network_table=/etc/postfix/network_table
#touch $network_table
#echo "127.0.0.0/8    any_value" >  $network_table
#echo "10.0.0.0/8     any_value" >> $network_table
#echo "172.16.0.0/12  any_value" >> $network_table
#echo "192.168.0.0/16 any_value" >> $network_table
## Ignore IPv6 for now
##echo "fd00::/8" >> $network_table
#postmap $network_table
#postconf -e mynetworks=hash:$network_table

# split with space
if [ ! -z "$allowed_senders_domains" ]; then
	echo -n "- Setting up 'allowed_senders' domains:"
	allowed_senders=/etc/postfix/allowed_senders
	rm -f $allowed_senders $allowed_senders.db > /dev/null
	touch $allowed_senders
	for i in $allowed_senders_domains; do
		echo -n " $i"
		echo -e "$i\tOK" >> $allowed_senders
	done
	echo
	postmap $allowed_senders

	postconf -e smtpd_restriction_classes="allowed_domains_only"
	postconf -e allowed_domains_only="permit_mynetworks, reject_non_fqdn_sender reject"
	postconf -e smtpd_recipient_restrictions="reject_non_fqdn_recipient, reject_unknown_recipient_domain, reject_unverified_recipient, check_sender_access hash:$allowed_senders, reject"
else
	postconf -# smtpd_restriction_classes
	postconf -e smtpd_recipient_restrictions="reject_non_fqdn_recipient,reject_unknown_recipient_domain,reject_unverified_recipient"
fi

# Use 587 (submission)
sed -i -r -e 's/^#submission/submission/' /etc/postfix/master.cf

[ -e "/etc/rc.local" ] && echo && echo "=> Executing /etc/rc.local" && /etc/rc.local
}

hooks_oneshot() {
echo "=> Executing $APP configuration hooks 'oneshot'..."

# save the configuration status for later usage with persistent volumes
#touch "${APP_CONF_DEFAULT}/.configured"
}

hooks_always
#[ ! -f "${APP_CONF_DEFAULT}/.configured" ] && hooks_oneshot || echo "=> Detected $APP configuration files already present in ${APP_CONF_DEFAULT}... skipping automatic configuration"
