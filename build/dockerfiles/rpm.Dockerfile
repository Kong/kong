ARG KONG_BASE_IMAGE=redhat/ubi8
FROM $KONG_BASE_IMAGE

LABEL maintainer="Kong Docker Maintainers <docker@konghq.com> (@team-gateway-bot)"

ARG KONG_VERSION
ENV KONG_VERSION $KONG_VERSION

# RedHat required labels
LABEL name="Kong" \
      vendor="Kong" \
      version="$KONG_VERSION" \
      release="1" \
      url="https://konghq.com" \
      summary="Next-Generation API Platform for Modern Architectures" \
      description="Next-Generation API Platform for Modern Architectures"

# RedHat required LICENSE file approved path
COPY LICENSE /licenses/

ARG RPM_PLATFORM=el8

ARG KONG_PREFIX=/usr/local/kong
ENV KONG_PREFIX $KONG_PREFIX

ARG EE_PORTS

ARG TARGETARCH

ARG KONG_ARTIFACT=kong.${RPM_PLATFORM}.${TARGETARCH}.rpm
ARG KONG_ARTIFACT_PATH=
COPY ${KONG_ARTIFACT_PATH}${KONG_ARTIFACT} /tmp/kong.rpm

# hadolint ignore=DL3015
RUN yum install -y /tmp/kong.rpm \
    && rm /tmp/kong.rpm \
    && chown kong:0 /usr/local/bin/kong \
    && chown -R kong:0 /usr/local/kong \
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
