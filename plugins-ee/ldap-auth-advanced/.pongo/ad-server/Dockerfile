FROM nginx:1.17.3-alpine

USER root

COPY . /setup

COPY ssl/myKey.pem /var/lib/samba/private/tls/myKey.pem
COPY ssl/myCert.pem /var/lib/samba/private/tls/myCert.pem

RUN apk add --no-cache samba-dc bash ldb-tools openldap-clients && \
    chmod 600 /var/lib/samba/private/tls/myKey.pem && \
    chmod 600 /var/lib/samba/private/tls/myCert.pem && \
    chown root:root /var/lib/samba/private/tls/myKey.pem && \
    chown root:root /var/lib/samba/private/tls/myCert.pem && \
    mkdir -p /etc/ldap/ && \
    chmod +x /setup/run.sh && \
    chmod +x /setup/setup.sh && \
    chmod +x /setup/add-seed-data.sh && \
	echo 'TLS_REQCERT allow' | tee -a /etc/ldap/ldap.conf 

ENV PATH=/setup:${PATH}

# Needs to run on startup due to a bug in samba.
# also it needs to run as privileged to workaround this issue
# error message:
# set_nt_acl_no_snum: fset_nt_acl returned NT_STATUS_ACCESS_DENIED
ENTRYPOINT [ "/setup/run.sh" ]

EXPOSE 389 636

CMD ["samba", "-F"]
