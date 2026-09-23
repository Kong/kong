FROM ubuntu:latest AS expat-build

ARG expat_version=2.6.3

SHELL ["/bin/bash", "-c"]

WORKDIR /workspace

RUN apt update \
    && apt install -y curl

RUN curl -L https://github.com/libexpat/libexpat/releases/download/R_${expat_version//./_}/expat-${expat_version}.tar.gz | tar -xz \
    && cd expat-${expat_version} \
    && apt install -y build-essential \
    && ./configure --prefix=/expat_lib \
    && make && make install

FROM ubuntu:latest

COPY --from=expat-build /expat_lib /expat_lib

RUN apt update && apt install -y curl libssl-dev libyaml-dev lua5.4 luarocks

WORKDIR /workspace
CMD ["/bin/bash", "-c", "OPENSSL_DIR=/usr EXPAT_DIR=/expat_lib scripts/update-copyright"]

VOLUME /workspace
