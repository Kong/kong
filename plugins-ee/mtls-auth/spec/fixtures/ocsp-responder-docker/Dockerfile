FROM ubuntu:jammy
RUN apt update
RUN apt install openssl nginx -y
COPY create_ca.sh create_ca.sh
COPY create_client.sh create_client
COPY revoke_client.sh revoke_client
COPY get_chain.sh get_chain
COPY get_cert.sh get_cert
COPY get_issuer.sh get_issuer
COPY get_key.sh get_key
COPY get_ca.sh get_ca
COPY get_crl.sh get_crl
COPY root-openssl.conf /root/ca/openssl.cnf
COPY intermediate-openssl.conf /root/ca/intermediate/openssl.cnf
COPY crl_nginx.conf /etc/nginx/conf.d/crl_nginx.conf
RUN chmod +x create_ca.sh && \
    chmod +x create_client && \
    chmod +x revoke_client && \
    chmod +x get_chain && \
    chmod +x get_cert && \
    chmod +x get_key && \
    chmod +x get_issuer && \
    chmod +x get_ca && \
    chmod +x get_crl
RUN ./create_ca.sh
COPY docker-entrypoint.sh docker-entrypoint.sh
EXPOSE 2560
EXPOSE 8080
ENTRYPOINT [ "/bin/sh", "docker-entrypoint.sh" ]
