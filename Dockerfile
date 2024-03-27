FROM kong:3.6.0-ubuntu

COPY poc.patch /tmp/poc.patch
COPY lua-resty-protobuf /tmp/lua-resty-protobuf
COPY --chown=root:root --chmod=744  docker-entrypoint.sh /docker-entrypoint.sh

USER root:root
RUN apt-get update -y \
    && apt-get install -y \
            automake \
            build-essential \
            cmake \
            git \
            libprotobuf-dev \
            protobuf-compiler \
            libabsl-dev \
    && echo "Successfully installed protobuf" \
    && cd /tmp/lua-resty-protobuf \
    && make install \
    && gcc -O2 -g3 consumer.c -o /usr/local/bin/consumer \
    && echo "Successfully installed lua-resty-protobuf" \
    && cd /usr/local/share/lua/5.1 \
    && git apply /tmp/poc.patch \
    && echo "Successfully patched kong" \
    && rm -rf /tmp/poc.patch /tmp/lua-resty-protobuf

USER kong:kong
