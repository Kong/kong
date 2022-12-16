ARG KONG_BASE_IMAGE=alpine:3.16
FROM $KONG_BASE_IMAGE

LABEL maintainer="Kong Docker Maintainers <docker@konghq.com> (@team-gateway-bot)"

ARG KONG_VERSION
ENV KONG_VERSION $KONG_VERSION

ARG KONG_PREFIX=/usr/local/kong
ENV KONG_PREFIX $KONG_PREFIX

ARG EE_PORTS

ARG KONG_ARTIFACT=kong.apk.tar.gz
COPY ${KONG_ARTIFACT} /tmp/kong.apk.tar.gz

RUN apk add --virtual .build-deps tar gzip \
    && tar -C / -xzf /tmp/kong.apk.tar.gz \
    && apk add --no-cache libstdc++ libgcc pcre perl tzdata libcap zlib zlib-dev bash \
    && adduser -S kong \
    && addgroup -S kong \
    && mkdir -p "${KONG_PREFIX}" \
    && chown -R kong:0 ${KONG_PREFIX} \
    && chown kong:0 /usr/local/bin/kong \
    && chmod -R g=u ${KONG_PREFIX} \
    && rm -rf /tmp/kong.apk.tar.gz \
    && ln -s /usr/local/openresty/bin/resty /usr/local/bin/resty \
    && ln -s /usr/local/openresty/luajit/bin/luajit /usr/local/bin/luajit \
    && ln -s /usr/local/openresty/luajit/bin/luajit /usr/local/bin/lua \
    && ln -s /usr/local/openresty/nginx/sbin/nginx /usr/local/bin/nginx \
    && apk del .build-deps \
    && kong version

COPY build/dockerfiles/entrypoint.sh /entrypoint.sh

USER kong

ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 8000 8443 8001 8444 $EE_PORTS

STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=60s --timeout=10s --retries=10 CMD kong health

CMD ["kong", "docker-start"]
