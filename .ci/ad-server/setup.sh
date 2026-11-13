#!/bin/sh

set -e

# add samba
apk add --no-cache samba-dc bash ldb-tools

# verify samba version
smbstatus | grep version

# remove conflicting config
rm -f /etc/samba/smb.conf

samba-tool domain provision --server-role=dc --use-rfc2307 --dns-backend=SAMBA_INTERNAL --realm=ldap.mashape.com --domain=ldap --adminpass=Passw0rd

# Add `ldap server require strong auth = no` setting to the conf
cat /setup-ad/smb.conf > /etc/samba/smb.conf
