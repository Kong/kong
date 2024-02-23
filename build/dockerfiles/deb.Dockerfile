ARG KONG_BASE_IMAGE=debian:bookworm-slim
FROM --platform=$TARGETPLATFORM $KONG_BASE_IMAGE

LABEL maintainer="Kong Docker Maintainers <docker@konghq.com> (@team-gateway-bot)"

ARG KONG_VERSION
ENV KONG_VERSION $KONG_VERSION

ARG KONG_PREFIX=/usr/local/kong
ENV KONG_PREFIX $KONG_PREFIX

ARG EE_PORTS

ARG TARGETARCH

ARG KONG_ARTIFACT=kong.${TARGETARCH}.deb
ARG KONG_ARTIFACT_PATH=
COPY ${KONG_ARTIFACT_PATH}${KONG_ARTIFACT} /tmp/kong.deb

RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get -y autoremove \
    && apt-get install -y --no-install-recommends /tmp/kong.deb \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/kong.deb \
    && chown kong:0 /usr/local/bin/kong \
    && chown -R kong:0 ${KONG_PREFIX} \
    && ln -sf /usr/local/openresty/bin/resty /usr/local/bin/resty \
    && ln -sf /usr/local/openresty/luajit/bin/luajit /usr/local/bin/luajit \
    && ln -sf /usr/local/openresty/luajit/bin/luajit /usr/local/bin/lua \
    && ln -sf /usr/local/openresty/nginx/sbin/nginx /usr/local/bin/nginx \
    && kong version

COPY build/dockerfiles/entrypoint.sh /entrypoint.sh

USER kong

ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 8000 8443 8001 8444 $EE_PORTS

STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=60s --timeout=10s --retries=10 CMD kong-health

CMD ["kong", "docker-start"]
