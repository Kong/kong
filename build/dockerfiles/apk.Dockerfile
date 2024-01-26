ARG KONG_BASE_IMAGE=alpine:3.16
FROM --platform=$TARGETPLATFORM $KONG_BASE_IMAGE

LABEL maintainer="Kong Docker Maintainers <docker@konghq.com> (@team-gateway-bot)"

ARG KONG_VERSION
ENV KONG_VERSION $KONG_VERSION

ARG KONG_PREFIX=/usr/local/kong
ENV KONG_PREFIX $KONG_PREFIX

ARG EE_PORTS

ARG TARGETARCH

ARG KONG_ARTIFACT=kong.${TARGETARCH}.apk.tar.gz
ARG KONG_ARTIFACT_PATH=
COPY ${KONG_ARTIFACT_PATH}${KONG_ARTIFACT} /tmp/kong.apk.tar.gz

RUN apk upgrade --update-cache \
    && apk add --virtual .build-deps tar gzip \
    && tar -C / -xzf /tmp/kong.apk.tar.gz \
    && apk add --no-cache libstdc++ libgcc perl tzdata libcap zlib zlib-dev bash yaml \
    && adduser -S kong \
    && addgroup -S kong \
    && mkdir -p "${KONG_PREFIX}" \
    && chown -R kong:0 ${KONG_PREFIX} \
    && chown kong:0 /usr/local/bin/kong \
    && chmod -R g=u ${KONG_PREFIX} \
    && rm -rf /tmp/kong.apk.tar.gz \
    && ln -sf /usr/local/openresty/bin/resty /usr/local/bin/resty \
    && ln -sf /usr/local/openresty/luajit/bin/luajit /usr/local/bin/luajit \
    && ln -sf /usr/local/openresty/luajit/bin/luajit /usr/local/bin/lua \
    && ln -sf /usr/local/openresty/nginx/sbin/nginx /usr/local/bin/nginx \
    && apk del .build-deps \
    && kong version

COPY build/dockerfiles/entrypoint.sh /entrypoint.sh

USER kong

ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 8000 8443 8001 8444 $EE_PORTS

STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=60s --timeout=10s --retries=10 CMD kong-health

CMD ["kong", "docker-start"]
