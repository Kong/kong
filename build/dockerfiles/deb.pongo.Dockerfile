# This Dockerfile is used to build the Pongo image for testing purposes on CI.
# It copies the Kong source code and the Enterprise plugins into
# the image to make sure the source code is up to date with the latest changes.

ARG PONGO_BASE_IMAGE
FROM $PONGO_BASE_IMAGE

USER root
COPY kong/ /tmp/kong
COPY kong-ee-old/ /tmp/kong-ee-old
COPY plugins-ee/ /tmp/plugins-ee
RUN cp -r /tmp/kong/. /usr/local/share/lua/5.1/kong \
    && rm -rf /tmp/kong \
    && cp -r /tmp/kong-ee-old/. /usr/local/share/lua/5.1/kong/kong-ee-old \
    && rm -rf /tmp/kong-ee-old \
    && cd /tmp \
    && tar zc plugins-ee/*/kong/plugins/* --transform='s,plugins-ee/[^/]*/kong,kong,' | tar zx -C /usr/local/share/lua/5.1 \
    && rm -rf /tmp/plugins-ee \
    && find /usr/local/share/lua/5.1/kong/plugins -name '*.ljbc' -delete \
    && find /usr/local/share/lua/5.1/kong/enterprise_edition -name '*.ljbc' -delete \
    && chown -R kong:0 /usr/local/share/lua/5.1/kong

USER kong
